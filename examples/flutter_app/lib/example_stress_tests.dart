// Stress-test catalog: downloads Khronos glTF Sample Assets at runtime
// and renders them via the runtime glTF importer. Lets the renderer be
// exercised against PBR fidelity, animation/skinning, and correctness
// scenes without committing big binary blobs to the repo.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart' hide Animation;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:native_mouse_cursor/native_mouse_cursor.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';
import 'example_chrome.dart';
import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_panel.dart';
import 'lighting_panel.dart';
import 'example_settings.dart';
import 'focus_lock_observer.dart';
import 'quake_camera.dart';

// The in-memory offline (ahead-of-time) glTF -> .fsceneb conversion, used by
// the per-test importer toggle below. Reaching into flutter_scene's internals
// is intentional here: this is a renderer stress test, not a typical consumer.
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/loader.dart';

// Toggle these on to inspect scenes as they load. Both are off by
// default; flip them locally when debugging a renderer regression in
// a specific stress test.
const bool _kDebugDumpScene = false;
const bool _kDebugTintMaterials = false;

/// Which importer path a stress test exercises. [runtime] uses the direct GLB
/// importer (`Node.fromGlbBytes` / `Node.fromGltfBytes`). [offline] runs the
/// ahead-of-time glTF -> .fsceneb conversion in memory and realizes the
/// result, the same conversion the `buildScenes` build hook performs. Offline
/// is `.glb` only (the offline importer has no multi-file `.gltf` path).
enum _ImporterMode { runtime, offline }

class _StressTest {
  const _StressTest({
    required this.id,
    required this.title,
    required this.description,
    required this.url,
    required this.sizeBytes,
    this.animationName,
    this.modelScale = 1.0,
    this.settings,
  });

  final String id;
  final String title;
  final String description;
  final String url;
  final int sizeBytes;
  final double modelScale;
  // If set, the first matching animation is played on a loop after load.
  final String? animationName;
  final ExampleSettings Function()? settings;

  /// True when [url] points at a multi-file glTF (a `.gltf` JSON with
  /// external `.bin` and image files) rather than a single-file `.glb`.
  bool get isMultiFile => url.endsWith('.gltf');
}

_StressTest _sampleAsset({
  required String id,
  required String title,
  required String description,
  required int sizeBytes,
  String variant = 'glTF-Binary',
}) {
  final extension = variant == 'glTF-Binary' ? 'glb' : 'gltf';
  return _StressTest(
    id: id,
    title: title,
    description: description,
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/$id/$variant/$id.$extension',
    sizeBytes: sizeBytes,
  );
}

final _catalog = <_StressTest>[
  _StressTest(
    id: 'ABeautifulGame',
    title: 'A Beautiful Game',
    description:
        'Chess set with rich PBR materials, many meshes, many textures. '
        'Stresses material variety and draw-call count.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/ABeautifulGame/glTF-Binary/ABeautifulGame.glb',
    sizeBytes: 42977928,
  ),
  _StressTest(
    id: 'AntiqueCamera',
    title: 'Antique Camera',
    description:
        'High-fidelity PBR with normal maps, occlusion, and emissive. A '
        'good "looks right by default" check.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AntiqueCamera/glTF-Binary/AntiqueCamera.glb',
    sizeBytes: 17540348,
  ),
  _StressTest(
    id: 'DamagedHelmet',
    title: 'Damaged Helmet',
    description:
        'The canonical glTF PBR test asset: one mesh with base color, '
        'normal, metallic-roughness, emissive, and occlusion maps. A quick '
        'all-in-one PBR fidelity check.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb',
    sizeBytes: 3773916,
  ),
  _StressTest(
    id: 'SciFiHelmet',
    title: 'Sci-Fi Helmet',
    description:
        'High-detail PBR helmet shipped as multi-file glTF: a .gltf plus '
        'a .bin buffer and four large textures. Exercises external '
        'resource resolution.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/SciFiHelmet/glTF/SciFiHelmet.gltf',
    sizeBytes: 30286979,
  ),
  _StressTest(
    id: 'FlightHelmet',
    title: 'Flight Helmet',
    description:
        'The Khronos high-fidelity reference: many separate meshes and '
        'textures. Multi-file glTF.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/FlightHelmet/glTF/FlightHelmet.gltf',
    sizeBytes: 48392569,
  ),
  _StressTest(
    id: 'Sponza',
    title: 'Sponza',
    description:
        'The classic architectural scene: large, many materials and '
        'textures, lots of draw calls. Multi-file glTF (71 files).',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/Sponza/glTF/Sponza.gltf',
    sizeBytes: 52686624,
    settings: () => ExampleSettings()
      ..directionalLightEnabled = true
      ..shadowOnly = false
      ..lightAzimuthDegrees = 111.14397321428582
      ..lightElevationDegrees = 78.69349888392773
      ..lightIntensity = 10.0
      ..lightColor.setValues(1.0, 1.0, 1.0)
      ..lightCastsShadow = true
      ..shadowSoftness = 0.08844517299107145
      ..shadowFilter = DirectionalShadowFilter.rotatedPoisson
      ..angularRadius = 0.03139428710937498
      ..contactShadows = true
      ..contactShadowDistance = 1.1032121930803565
      ..shadowFadeRange = 9.031808035714285
      ..shadowCascadeCount = 4
      ..shadowMaxDistance = 185.68359375000014
      ..shadowCascadeSplitLambda = 0.4551130022321431
      ..cascadeOverlap = 0.0
      ..shadowMapResolution = 2048
      ..shadowDepthBias = 0.03456682477678571
      ..shadowNormalBias = 0.00204729352678569
      ..shadowAmbientStrength = 0.15035574776785832
      ..ambientOcclusion.enabled = true
      ..ambientOcclusion.method = AmbientOcclusionMethod.groundTruth
      ..ambientOcclusion.radius = 0.33
      ..ambientOcclusion.intensity = 1.0
      ..ambientOcclusion.power = 1.5
      ..ambientOcclusion.detail = 0.5
      ..ambientOcclusion.horizonAngle = 0.06
      ..ambientOcclusion.directLightAffect = 0.0
      ..ambientOcclusion.indirectLight = 8.209821428571372
      ..ambientOcclusion.thicknessHeuristic = 0.005043247767857112
      ..ambientOcclusion.depthMipChain = true
      ..ambientOcclusion.bias = 0.07
      ..ambientOcclusion.sampleCount = 16
      ..ambientOcclusion.sliceCount = 3
      ..ambientOcclusion.stepsPerSlice = 3
      ..ambientOcclusion.visibilityBitmask = true
      ..ambientOcclusion.thickness = 0.5698050362723207
      ..ambientOcclusion.multiBounce = 1.0
      ..ambientOcclusion.bentNormals = false
      ..ambientOcclusion.halfResolution = false
      ..ambientOcclusion.specularMode = SpecularAmbientOcclusionMode.bentCone
      ..colorGrading.enabled = true
      ..colorGrading.brightness = 1.0018136160714266
      ..colorGrading.contrast = 0.9995117187499986
      ..colorGrading.saturation = 0.9974190848214235
      ..colorGrading.temperature = 0.26067243303570997
      ..colorGrading.tint = 0.0011160714285713969
      ..colorGrading.lift.setValues(0.0, 0.0, 0.0)
      ..colorGrading.gamma.setValues(1.0, 1.0, 1.0)
      ..colorGrading.gain.setValues(1.0, 1.0, 1.0)
      ..colorGrading.lutBlend = 1.0
      ..bloom.enabled = true
      ..bloom.threshold = 0.8173828124999993
      ..bloom.intensity = 0.15
      ..bloom.scatter = 0.7
      ..bloom.lensFlare.enabled = true
      ..bloom.lensFlare.intensity = 0.2453962053571428
      ..bloom.lensFlare.ghostCount = 4
      ..bloom.lensFlare.ghostSpacing = 0.3
      ..bloom.lensFlare.haloRadius = 0.35
      ..bloom.lensFlare.haloIntensity = 1.0
      ..bloom.lensFlare.chromaticAberration = 0.028416224888392863
      ..godRays.enabled = true
      ..godRays.intensity = 0.5785435267857144
      ..godRays.density = 0.2507672991071428
      ..godRays.anisotropy = 0.7
      ..godRays.stepCount = 24
      ..godRays.maxDistance = 200.0
      ..godRays.jitter = 1.0
      ..godRays.color.setValues(1.0, 1.0, 1.0)
      ..depthOfField.enabled = true
      ..depthOfField.focusDistance = 6.0950195312500055
      ..depthOfField.fStop = 2.939798409598211
      ..depthOfField.focalLength = 0.06454380580357147
      ..depthOfField.sensorHeight = 0.024
      ..depthOfField.blurScale = 1.0
      ..depthOfField.maxForegroundBlur = 24.0
      ..depthOfField.maxBackgroundBlur = 32.0
      ..depthOfField.bladeCount = 0
      ..depthOfField.bladeRotation = 0.0
      ..depthOfField.bladeCurvature = 0.0
      ..depthOfField.quality = DepthOfFieldQuality.high
      ..chromaticAberration.enabled = true
      ..chromaticAberration.intensity = 0.06166294642857137
      ..vignette.enabled = true
      ..vignette.intensity = 0.5
      ..vignette.radius = 0.75
      ..vignette.smoothness = 0.5
      ..filmGrain.enabled = false
      ..filmGrain.intensity = 0.03962053571428574
      ..screenSpaceReflections.enabled = true
      ..screenSpaceReflections.intensity = 1.0
      ..screenSpaceReflections.maxDistance = 24.4
      ..screenSpaceReflections.thickness = 0.46
      ..screenSpaceReflections.stride = 9.0
      ..screenSpaceReflections.maxSteps = 90
      ..screenSpaceReflections.blur = 0.3
      ..screenSpaceReflections.distanceFadeStart = 0.0
      ..screenSpaceReflections.resolutionScale = 1.0
      ..screenSpaceReflections.debugView = SsrDebugView.composite
      ..globalIllumination.enabled = true
      ..globalIllumination.volumeMode = IrradianceVolumeMode.followCamera
      ..globalIllumination.resolution.setValues(16.0, 8.0, 16.0)
      ..globalIllumination.extents.setValues(60.0, 30.602888107299805, 60.0)
      ..globalIllumination.intensity = 0.9461495535714289
      ..globalIllumination.hysteresis = 0.95
      ..globalIllumination.shadowBias = 0.3
      ..globalIllumination.visibility = 0.7
      ..globalIllumination.visibilityBias = 0.08
      ..globalIllumination.probeUpdateBudget = 0
      ..globalIllumination.injectionResolution =
          IrradianceInjectionResolution.eighth
      ..globalIllumination.fireflyClamp = 8.0
      ..globalIllumination.emissiveGiBoost = 1.0
      ..globalIllumination.updateWhenIdleOnly = false
      ..globalIllumination.bakeOnly = false
      ..temporalAntiAliasing.minimumCurrentWeight = 0.108504115513393
      ..temporalAntiAliasing.varianceGamma = 1.2
      ..temporalAntiAliasing.sharpness = 0.0
      ..temporalAntiAliasing.jitterSequenceLength = 32
      ..temporalAntiAliasing.jitterScale = 0.4471714564732142
      ..temporalAntiAliasing.objectMotion = true
      ..temporalAntiAliasing.skinnedMotion = true
      ..exposure = 1.0
      ..toneMapping = ToneMappingMode.pbrNeutral
      ..environmentIntensity = 0.0
      ..autoExposure.enabled = true
      ..autoExposure.strength = 0.55
      ..autoExposure.compensation = 0.0
      ..autoExposure.minEv = -4.0
      ..autoExposure.maxEv = 4.0
      ..autoExposure.speedUp = 3.0
      ..autoExposure.speedDown = 1.0
      ..antiAliasingMode = AntiAliasingMode.taa
      ..renderScale = 1.0
      ..filterQuality = FilterQuality.medium,
  ),
  _StressTest(
    id: 'MetalRoughSpheres',
    title: 'Metal/Rough Spheres',
    description:
        'Grid of spheres varying metallic and roughness across the full '
        'range. Material-coverage sanity check.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/MetalRoughSpheres/glTF-Binary/MetalRoughSpheres.glb',
    sizeBytes: 11221356,
  ),
  _StressTest(
    id: 'Lantern',
    title: 'Lantern',
    description:
        'Emissive PBR test: the lantern glass should glow above the IBL '
        'while the metal frame stays grounded.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/Lantern/glTF-Binary/Lantern.glb',
    sizeBytes: 9564264,
  ),
  _StressTest(
    id: 'WaterBottle',
    title: 'Water Bottle',
    description:
        'Compact PBR; bottle label, cap, plastic. Without KHR_transmission '
        'support the bottle reads as opaque white plastic.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/WaterBottle/glTF-Binary/WaterBottle.glb',
    sizeBytes: 8966700,
  ),
  _StressTest(
    id: 'ClearCoatTest',
    title: 'Clearcoat Test',
    description:
        'Reference grid for clearcoat strength, roughness, and normal layers. '
        'Exposes channel, energy, and layering errors.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/ClearCoatTest/glTF-Binary/ClearCoatTest.glb',
    sizeBytes: 258048,
  ),
  _StressTest(
    id: 'ToyCar',
    title: 'Toy Car',
    description:
        'Showcase model combining clearcoat, sheen, and transmission. Checks '
        'that several advanced lobes compose convincingly.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/ToyCar/glTF-Binary/ToyCar.glb',
    sizeBytes: 5422412,
    modelScale: 10.0,
  ),
  _StressTest(
    id: 'CarConcept',
    title: 'Car Concept',
    description:
        'Detailed concept car combining clearcoat, iridescence, transmission, '
        'emissive strength, texture transforms, variants, and UV1 occlusion.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/CarConcept/glTF-Binary/CarConcept.glb',
    sizeBytes: 11778688,
  ),
  _StressTest(
    id: 'AnisotropyBarnLamp',
    title: 'Anisotropy Barn Lamp',
    description:
        'Brushed metal with directional highlights. Exercises anisotropy '
        'strength, rotation, texture direction, and tangent reconstruction.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AnisotropyBarnLamp/glTF-Binary/AnisotropyBarnLamp.glb',
    sizeBytes: 7833440,
  ),
  _StressTest(
    id: 'GlamVelvetSofa',
    title: 'Glam Velvet Sofa',
    description:
        'High-quality fabric model combining sheen and specular materials. '
        'Checks grazing-angle response across textured upholstery.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/GlamVelvetSofa/glTF-Binary/GlamVelvetSofa.glb',
    sizeBytes: 3149844,
  ),
  _StressTest(
    id: 'IridescenceLamp',
    title: 'Iridescence Lamp',
    description:
        'Layered lamp using iridescence, transmission, and volume. Exercises '
        'thin-film color while light travels through the shade.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/IridescenceLamp/glTF-Binary/IridescenceLamp.glb',
    sizeBytes: 4083912,
  ),
  _StressTest(
    id: 'DragonAttenuation',
    title: 'Dragon Attenuation',
    description:
        'Dense translucent material with varying thickness. Checks volume '
        'attenuation, scale handling, transmission, and material variants.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/DragonAttenuation/glTF-Binary/DragonAttenuation.glb',
    sizeBytes: 6401616,
  ),
  _StressTest(
    id: 'DispersionTest',
    title: 'Dispersion Test',
    description:
        'Reference objects with controlled dispersion values. Reveals whether '
        'refracted wavelengths separate consistently.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/DispersionTest/glTF-Binary/DispersionTest.glb',
    sizeBytes: 2310944,
  ),
  _StressTest(
    id: 'SpecularTest',
    title: 'Specular Test',
    description:
        'Compact grid for dielectric specular strength and color. Catches '
        'factor, texture-channel, and IOR interaction errors.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/SpecularTest/glTF-Binary/SpecularTest.glb',
    sizeBytes: 223376,
  ),
  _StressTest(
    id: 'AnisotropyStrengthTest',
    title: 'Anisotropy Strength Test',
    description:
        'Controlled anisotropy-strength sweep. Reveals lobe stretching and '
        'isotropic fallback errors without texture noise.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AnisotropyStrengthTest/glTF-Binary/'
        'AnisotropyStrengthTest.glb',
    sizeBytes: 94444,
  ),
  _StressTest(
    id: 'AnisotropyRotationTest',
    title: 'Anisotropy Rotation Test',
    description:
        'Controlled anisotropy-rotation sweep. Catches tangent-frame and '
        'texture-direction sign errors.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AnisotropyRotationTest/glTF-Binary/'
        'AnisotropyRotationTest.glb',
    sizeBytes: 832340,
  ),
  _StressTest(
    id: 'DiffuseTransmissionTest',
    title: 'Diffuse Transmission Test',
    description:
        'Thin diffuse-transmission reference lit from both sides. Checks '
        'factors, color, textures, and back-side lighting.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/DiffuseTransmissionTest/glTF-Binary/'
        'DiffuseTransmissionTest.glb',
    sizeBytes: 238336,
  ),
  _StressTest(
    id: 'EmissiveStrengthTest',
    title: 'Emissive Strength Test',
    description:
        'Small controlled emissive-strength grid. Catches HDR range, factor, '
        'and tone-mapping regressions.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/EmissiveStrengthTest/glTF-Binary/'
        'EmissiveStrengthTest.glb',
    sizeBytes: 10668,
  ),
  _StressTest(
    id: 'IORTestGrid',
    title: 'IOR Test Grid',
    description:
        'Grid combining IOR, specular, transmission, and volume. Exposes '
        'incorrect dielectric Fresnel and refraction interactions.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/IORTestGrid/glTF-Binary/IORTestGrid.glb',
    sizeBytes: 2628524,
  ),
  _StressTest(
    id: 'IridescenceSuzanne',
    title: 'Iridescence Suzanne',
    description:
        'Textured thin-film thickness over a curved surface. Checks view-angle '
        'color shifts and interaction with transmission and volume.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/IridescenceSuzanne/glTF-Binary/IridescenceSuzanne.glb',
    sizeBytes: 507608,
  ),
  _StressTest(
    id: 'SheenTestGrid',
    title: 'Sheen Test Grid',
    description:
        'Controlled sheen color and roughness grid. Exposes grazing-angle '
        'energy and texture-channel errors.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/SheenTestGrid/glTF-Binary/SheenTestGrid.glb',
    sizeBytes: 1841064,
  ),
  _StressTest(
    id: 'AttenuationTest',
    title: 'Attenuation Test',
    description:
        'Controlled volume thickness, attenuation distance, and scale cases. '
        'Catches incorrect transmission absorption.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AttenuationTest/glTF-Binary/AttenuationTest.glb',
    sizeBytes: 57532,
  ),
  _StressTest(
    id: 'TransmissionTest',
    title: 'Transmission Test',
    description:
        'Controlled transmission factors and textures. Verifies that opaque '
        'and transmissive regions share the same material correctly.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/TransmissionTest/glTF-Binary/TransmissionTest.glb',
    sizeBytes: 1473792,
  ),
  _StressTest(
    id: 'TransmissionRoughnessTest',
    title: 'Transmission Roughness Test',
    description:
        'Transmission across controlled roughness and IOR values. Reveals '
        'missing or incorrectly filtered rough refraction.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/TransmissionRoughnessTest/glTF-Binary/'
        'TransmissionRoughnessTest.glb',
    sizeBytes: 393808,
  ),
  _StressTest(
    id: 'TransmissionOrderTest',
    title: 'Transmission Order Test',
    description:
        'Overlapping transmissive volumes. Exposes draw ordering, depth, and '
        'nested volume-composition errors.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/TransmissionOrderTest/glTF-Binary/'
        'TransmissionOrderTest.glb',
    sizeBytes: 2312512,
  ),
  _StressTest(
    id: 'TextureTransformMultiTest',
    title: 'Texture Transform Multi Test',
    description:
        'Independent texture transforms across base and clearcoat inputs. '
        'Catches shared-transform and UV-selection bugs.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/TextureTransformMultiTest/glTF-Binary/'
        'TextureTransformMultiTest.glb',
    sizeBytes: 388264,
  ),
  _StressTest(
    id: 'RecursiveSkeletons',
    title: 'Recursive Skeletons',
    description:
        'Deeply nested skinning hierarchy. Worst-case for the joint-matrix '
        'texture upload.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/RecursiveSkeletons/glTF-Binary/RecursiveSkeletons.glb',
    sizeBytes: 561620,
    animationName: 'Skeleton_Pose',
  ),
  _StressTest(
    id: 'BrainStem',
    title: 'Brain Stem',
    description:
        'The Khronos walking animation reference; common skinning baseline.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/BrainStem/glTF-Binary/BrainStem.glb',
    sizeBytes: 3194848,
    animationName: 'animation_0',
  ),
  _StressTest(
    id: 'Fox',
    title: 'Fox',
    description:
        'Quadruped skinning. Has Survey/Walk/Run clips; we play whichever '
        'lands first in the list.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/Fox/glTF-Binary/Fox.glb',
    sizeBytes: 162852,
    animationName: 'Run',
  ),
  _StressTest(
    id: 'AlphaBlendModeTest',
    title: 'Alpha Blend Mode Test',
    description:
        'Validation grid for OPAQUE / MASK / BLEND alpha modes. Surfaces '
        'sort-order and premultiplication regressions.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AlphaBlendModeTest/glTF-Binary/AlphaBlendModeTest.glb',
    sizeBytes: 2978812,
  ),
  _StressTest(
    id: 'NormalTangentTest',
    title: 'Normal/Tangent Test',
    description:
        'Pairs of identical surfaces with and without tangents. Catches '
        'normal-map orientation and screen-space-derivative regressions.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/NormalTangentTest/glTF-Binary/NormalTangentTest.glb',
    sizeBytes: 1796996,
  ),
  _StressTest(
    id: 'OrientationTest',
    title: 'Orientation Test',
    description:
        'Axis-labelled cubes for catching coordinate-system and winding-flip '
        'bugs at a glance.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/OrientationTest/glTF-Binary/OrientationTest.glb',
    sizeBytes: 38920,
  ),
  ..._additionalStressTests,
];

final _additionalStressTests = <_StressTest>[
  _sampleAsset(
    id: 'AnisotropyDiscTest',
    title: 'Anisotropy Disc Test',
    description:
        'Radial brushed-metal reference with textured anisotropy direction. '
        'Catches tangent orientation and seam errors.',
    sizeBytes: 242128,
  ),
  _sampleAsset(
    id: 'CarbonFibre',
    title: 'Carbon Fibre',
    description:
        'Woven carbon fiber using an anisotropy texture. Checks fine-scale '
        'direction changes over a curved glossy surface.',
    sizeBytes: 429880,
  ),
  _sampleAsset(
    id: 'ChairDamaskPurplegold',
    title: 'Damask Chair',
    description:
        'Patterned upholstery combining sheen, specular, and texture '
        'transforms over detailed geometry.',
    sizeBytes: 2028924,
  ),
  _sampleAsset(
    id: 'ChronographWatch',
    title: 'Chronograph Watch',
    description:
        'Detailed watch with transmissive glass, material variants, and '
        'texture transforms over many small parts.',
    sizeBytes: 7446368,
  ),
  _sampleAsset(
    id: 'ClearCoatCarPaint',
    title: 'Clearcoat Car Paint',
    description:
        'Compact layered paint reference with separate base and clearcoat '
        'texture transforms.',
    sizeBytes: 116948,
  ),
  _sampleAsset(
    id: 'ClearcoatWicker',
    title: 'Clearcoat Wicker',
    description:
        'Textured wicker beneath a glossy clear layer. Exposes clearcoat '
        'normal and base-lobe energy errors.',
    sizeBytes: 1299752,
  ),
  _sampleAsset(
    id: 'CommercialRefrigerator',
    title: 'Commercial Refrigerator',
    description:
        'Large appliance combining coated metal and transmissive glass '
        'across many meshes and textures.',
    sizeBytes: 10131180,
  ),
  _sampleAsset(
    id: 'CompareAlphaCoverage',
    title: 'Compare Alpha Coverage',
    description:
        'Thin masked geometry at several scales. Catches alpha cutoff, '
        'coverage, filtering, and mip regressions.',
    sizeBytes: 3872604,
  ),
  _sampleAsset(
    id: 'CompareAmbientOcclusion',
    title: 'Compare Ambient Occlusion',
    description:
        'Controlled occlusion strength and texture cases for verifying '
        'indirect-light attenuation.',
    sizeBytes: 4828680,
  ),
  _sampleAsset(
    id: 'CompareAnisotropy',
    title: 'Compare Anisotropy',
    description:
        'Side-by-side isotropic and anisotropic materials with controlled '
        'strength, rotation, and texture inputs.',
    sizeBytes: 1085084,
  ),
  _sampleAsset(
    id: 'CompareBaseColor',
    title: 'Compare Base Color',
    description:
        'Base-color factors, textures, alpha, and texture transforms in one '
        'small material reference.',
    sizeBytes: 1507816,
  ),
  _sampleAsset(
    id: 'CompareClearcoat',
    title: 'Compare Clearcoat',
    description:
        'Clearcoat factors and roughness compared across dielectric IOR '
        'values. Useful for energy-conservation checks.',
    sizeBytes: 193920,
  ),
  _sampleAsset(
    id: 'CompareDispersion',
    title: 'Compare Dispersion',
    description:
        'Controlled transmissive volumes with increasing chromatic '
        'dispersion and fixed IOR.',
    sizeBytes: 60432,
  ),
  _sampleAsset(
    id: 'CompareEmissiveStrength',
    title: 'Compare Emissive Strength',
    description:
        'HDR emissive factors spanning dim to intense output. Catches '
        'clamping and tone-mapping errors.',
    sizeBytes: 111796,
  ),
  _sampleAsset(
    id: 'CompareIor',
    title: 'Compare IOR',
    description:
        'Transmissive volumes with controlled index of refraction. Exposes '
        'Fresnel and ray-bending errors.',
    sizeBytes: 213104,
  ),
  _sampleAsset(
    id: 'CompareIridescence',
    title: 'Compare Iridescence',
    description:
        'Thin-film factor, IOR, and thickness sweeps under identical '
        'lighting.',
    sizeBytes: 214756,
  ),
  _sampleAsset(
    id: 'CompareMetallic',
    title: 'Compare Metallic',
    description:
        'Metallic factors and textures over a controlled material grid. '
        'Catches channel and color-space mistakes.',
    sizeBytes: 172180,
  ),
  _sampleAsset(
    id: 'CompareNormal',
    title: 'Compare Normal Maps',
    description:
        'Normal-map scale and orientation cases under consistent geometry '
        'and lighting.',
    sizeBytes: 220900,
  ),
  _sampleAsset(
    id: 'CompareRoughness',
    title: 'Compare Roughness',
    description:
        'Roughness factors and textures across dielectric and metallic '
        'surfaces.',
    sizeBytes: 155660,
  ),
  _sampleAsset(
    id: 'CompareSheen',
    title: 'Compare Sheen',
    description:
        'Controlled sheen color and roughness combinations with a shared '
        'base material.',
    sizeBytes: 883968,
  ),
  _sampleAsset(
    id: 'CompareSpecular',
    title: 'Compare Specular',
    description:
        'Dielectric specular strength and tint combinations with factor and '
        'texture coverage.',
    sizeBytes: 1408364,
  ),
  _sampleAsset(
    id: 'CompareTransmission',
    title: 'Compare Transmission',
    description:
        'Thin-surface transmission factors and textures against an opaque '
        'reference.',
    sizeBytes: 357024,
  ),
  _sampleAsset(
    id: 'CompareVolume',
    title: 'Compare Volume',
    description:
        'Volume thickness, attenuation color, and attenuation distance under '
        'controlled transmission.',
    sizeBytes: 399760,
  ),
  _sampleAsset(
    id: 'DiffuseTransmissionPlant',
    title: 'Diffuse Transmission Plant',
    description:
        'Thin leaves lit from both sides with textured diffuse transmission '
        'and punctual lights.',
    sizeBytes: 5759100,
  ),
  _sampleAsset(
    id: 'DiffuseTransmissionTeacup',
    title: 'Diffuse Transmission Teacup',
    description:
        'A thin ceramic shell that glows under backlighting. Checks diffuse '
        'transmission over curved geometry.',
    sizeBytes: 4795028,
  ),
  _sampleAsset(
    id: 'DragonDispersion',
    title: 'Dragon Dispersion',
    description:
        'Dense transmissive dragon combining volume attenuation, IOR, and '
        'chromatic dispersion.',
    sizeBytes: 6401724,
  ),
  _sampleAsset(
    id: 'GlassBrokenWindow',
    title: 'Glass Broken Window',
    description:
        'Thin transmission mixed with masked holes and sharp edges. Exposes '
        'alpha, depth, and glass ordering errors.',
    sizeBytes: 1076624,
  ),
  _sampleAsset(
    id: 'GlassHurricaneCandleHolder',
    title: 'Glass Hurricane Candle Holder',
    description:
        'Glass lamp enclosure using transmission and volume around an '
        'emissive candle. Checks layered curved glass.',
    sizeBytes: 2705400,
  ),
  _sampleAsset(
    id: 'GlassVaseFlowers',
    title: 'Glass Vase Flowers',
    description:
        'Volume glass around opaque stems and alpha-blended flowers. Checks '
        'transparent composition across material modes.',
    sizeBytes: 1819824,
  ),
  _sampleAsset(
    id: 'IridescenceAbalone',
    title: 'Iridescence Abalone',
    description:
        'Detailed organic shell with textured thin-film thickness and '
        'strong view-dependent color.',
    sizeBytes: 9300744,
  ),
  _sampleAsset(
    id: 'IridescenceDielectricSpheres',
    title: 'Iridescence Dielectric Spheres',
    description:
        'Dielectric spheres sweeping iridescence thickness and IOR. '
        'Multi-file glTF.',
    sizeBytes: 329260,
    variant: 'glTF',
  ),
  _sampleAsset(
    id: 'IridescenceMetallicSpheres',
    title: 'Iridescence Metallic Spheres',
    description:
        'Metallic spheres sweeping thin-film thickness and IOR. Multi-file '
        'glTF.',
    sizeBytes: 301607,
    variant: 'glTF',
  ),
  _sampleAsset(
    id: 'IridescentDishWithOlives',
    title: 'Iridescent Dish with Olives',
    description:
        'Realistic dish combining iridescence, transmission, volume, and IOR '
        'around opaque contents.',
    sizeBytes: 5742828,
  ),
  _sampleAsset(
    id: 'LightsPunctualLamp',
    title: 'Punctual Lights Lamp',
    description:
        'Lamp scene containing point, spot, and directional lights. Checks '
        'asset-authored light import and material response.',
    sizeBytes: 4341320,
  ),
  _sampleAsset(
    id: 'MandarinOrange',
    title: 'Mandarin Orange',
    description:
        'Textured fruit skin using diffuse transmission for soft '
        'backlighting. Multi-file glTF.',
    sizeBytes: 4148292,
    variant: 'glTF',
  ),
  _sampleAsset(
    id: 'MaterialsVariantsShoe',
    title: 'Material Variants Shoe',
    description:
        'Detailed shoe with several authored material variants. Exercises '
        'variant metadata and textured PBR materials.',
    sizeBytes: 7833592,
  ),
  _sampleAsset(
    id: 'MosquitoInAmber',
    title: 'Mosquito in Amber',
    description:
        'Opaque geometry embedded inside a thick absorbing transmissive '
        'volume. A demanding nested-material case.',
    sizeBytes: 24229904,
  ),
  _sampleAsset(
    id: 'MultiUVTest',
    title: 'Multiple UV Sets',
    description:
        'Controlled texture assignments across multiple UV sets. Catches '
        'per-texture coordinate-selection mistakes.',
    sizeBytes: 43004,
  ),
  _sampleAsset(
    id: 'NormalTangentMirrorTest',
    title: 'Mirrored Normal/Tangent Test',
    description:
        'Mirrored and non-mirrored tangent frames with normal maps. Reveals '
        'handedness and interpolation seams.',
    sizeBytes: 1567084,
  ),
  _sampleAsset(
    id: 'PointLightIntensityTest',
    title: 'Point Light Intensity Test',
    description:
        'Point lights at controlled luminous intensities and distances. '
        'Catches falloff and unit conversion errors.',
    sizeBytes: 30148,
  ),
  _sampleAsset(
    id: 'PotOfCoals',
    title: 'Pot of Coals',
    description:
        'Emissive coals, textured pottery, and clearcoat in a compact '
        'showcase scene.',
    sizeBytes: 4696240,
  ),
  _sampleAsset(
    id: 'ScatteringSkull',
    title: 'Scattering Skull',
    description:
        'Advanced translucent volume combining diffuse transmission, '
        'dispersion, IOR, and volume scattering.',
    sizeBytes: 8959044,
  ),
  _sampleAsset(
    id: 'SheenChair',
    title: 'Sheen Chair',
    description:
        'Fabric chair with textured sheen, transforms, and material variants '
        'across detailed upholstery.',
    sizeBytes: 4125648,
  ),
  _sampleAsset(
    id: 'SheenWoodLeatherSofa',
    title: 'Sheen Wood Leather Sofa',
    description:
        'Large sofa combining sheen, specular, texture transforms, and WebP '
        'textures.',
    sizeBytes: 10107912,
  ),
  _sampleAsset(
    id: 'SpecularSilkPouf',
    title: 'Specular Silk Pouf',
    description:
        'Silk upholstery combining tinted dielectric specular and sheen over '
        'a curved woven surface.',
    sizeBytes: 4632512,
  ),
  _sampleAsset(
    id: 'StainedGlassLamp',
    title: 'Stained Glass Lamp',
    description:
        'Multi-file stained-glass lamp combining transmission, clearcoat, '
        'emission, alpha, and many external textures.',
    sizeBytes: 35125810,
    variant: 'glTF',
  ),
  _sampleAsset(
    id: 'SunglassesKhronos',
    title: 'Sunglasses',
    description:
        'Thin lenses combining transmission, volume, IOR, and iridescence '
        'inside a detailed opaque frame.',
    sizeBytes: 371188,
  ),
  _sampleAsset(
    id: 'TransmissionThinwallTestGrid',
    title: 'Transmission Thin-Wall Grid',
    description:
        'Thin and volumetric transmission cases across IOR and attenuation '
        'settings.',
    sizeBytes: 1188724,
  ),
  _sampleAsset(
    id: 'UnlitTest',
    title: 'Unlit Test',
    description:
        'Compact reference for materials that must ignore scene lighting and '
        'display their authored color directly.',
    sizeBytes: 3992,
  ),
  _sampleAsset(
    id: 'USDShaderBallForGltf',
    title: 'Transmission Shader Ball',
    description:
        'Complex shader-ball geometry with textured transmission, volume, '
        'and attenuation.',
    sizeBytes: 1319652,
  ),
];

// Generates a procedural test environment: a low-resolution equirect
// colored by the dominant world axis of each direction (+X red, -X cyan,
// +Y green, -Y magenta, +Z blue, -Z yellow). Solid colors make the
// environment's orientation unambiguous in reflections and ambient light.
class ExampleStressTests extends StatefulWidget {
  const ExampleStressTests({super.key});

  @override
  State<ExampleStressTests> createState() => _ExampleStressTestsState();
}

class _ExampleStressTestsState extends State<ExampleStressTests> {
  _StressTest? _active;

  void _open(_StressTest test) {
    setState(() => _active = test);
  }

  void _back() {
    resetExampleSettings(
      () => ExampleSettings()..directionalLightEnabled = false,
    );
    setState(() => _active = null);
  }

  void _moveActive(int delta) {
    final active = _active;
    if (active == null || _catalog.isEmpty) return;
    final index = _catalog.indexOf(active);
    final nextIndex = (index + delta) % _catalog.length;
    setState(() => _active = _catalog[nextIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (active == null) {
      return _CatalogList(onOpen: _open);
    }
    final index = _catalog.indexOf(active);
    return _StressScene(
      key: ValueKey(active.id),
      test: active,
      catalogIndex: index,
      catalogLength: _catalog.length,
      onBack: _back,
      onPrevious: () => _moveActive(-1),
      onNext: () => _moveActive(1),
    );
  }
}

class _CatalogList extends StatelessWidget {
  const _CatalogList({required this.onOpen});
  final ValueChanged<_StressTest> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
      itemCount: _catalog.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final test = _catalog[i];
        return Card(
          child: ListTile(
            title: Text(test.title),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(test.description),
                  const SizedBox(height: 4),
                  Text(
                    _formatBytes(test.sizeBytes),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(test),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

class _StressScene extends StatefulWidget {
  const _StressScene({
    super.key,
    required this.test,
    required this.catalogIndex,
    required this.catalogLength,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
  });

  final _StressTest test;
  final int catalogIndex;
  final int catalogLength;
  final VoidCallback onBack;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  State<_StressScene> createState() => _StressSceneState();
}

class _StressSceneState extends State<_StressScene> {
  final Scene _scene = Scene();
  final FocusNode _focusNode = FocusNode();

  // FPS-style free-look camera. Speed is scaled to the model size at load
  // time so the same controls feel right for a 10-cm bottle and a 100-m
  // architectural scene.
  final QuakeCamera _quake = QuakeCamera()
    ..speed = 3.0
    ..movementSmoothing = 10.0
    ..lookSmoothing = 18.0;
  late double _modelScale;
  double _cameraSpeed = 3.0;
  double _cameraSoftness = 0.1;
  Node? _modelRoot;
  vm.Matrix4? _modelBaseTransform;
  final InfiniteDragController _focusPointer = InfiniteDragController(
    axis: InfiniteDragAxis.both,
    edgeMargin: 24,
  );
  late final FocusLockObserver _focusLockObserver;
  bool _focused = false;

  // Load state. `null` total means the server didn't send a Content-Length
  // — the screen still shows downloaded bytes so users see motion.
  bool _ready = false;
  int _downloaded = 0;
  int? _total;
  Object? _error;

  // Which importer to exercise. Switchable per test via the toggle; offline
  // is only offered for single-file .glb tests.
  _ImporterMode _importerMode = _ImporterMode.runtime;

  // Image-based-lighting environment (the shared selector caches loaded
  // HDRs; the renderer's built-in studio environment is the default).
  final EnvironmentSelector _environmentSelector = EnvironmentSelector();

  @override
  void initState() {
    super.initState();
    resetExampleSettings(
      widget.test.settings ??
          () => ExampleSettings()..directionalLightEnabled = false,
    );
    _modelScale = widget.test.modelScale;
    _applyCameraSoftness();
    _focusLockObserver = createFocusLockObserver(() {
      if (_focused) _exitFocus();
    });
    // Keep an actual scene visible while a remote stress asset is downloading.
    _scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.06, 0.08, 0.12),
        horizonColor: vm.Vector3(0.18, 0.22, 0.29),
        groundColor: vm.Vector3(0.035, 0.045, 0.065),
      ),
    );
    // Lighting (the directional key light and shadows) is driven by the
    // shared settings panel via ExampleSettings.applyTo.
    unawaited(_load());
  }

  // Accumulates downloaded bytes (across every file of a multi-file
  // model) into the progress display.
  void _reportChunk(int bytes) {
    if (!mounted) return;
    setState(() {
      _downloaded += bytes;
      _total = widget.test.sizeBytes;
    });
  }

  Future<void> _load() async {
    try {
      final node = await _importTest(widget.test, _importerMode, _reportChunk);
      node.name = widget.test.id;
      _modelRoot = node;
      _modelBaseTransform = node.localTransform.clone();
      _applyModelScale();

      if (_kDebugDumpScene) {
        _debugDumpScene(node);
      }
      if (_kDebugTintMaterials) {
        _debugTintMaterials(node);
      }

      // Frame the camera around the model. combinedLocalBounds returns
      // null when the subtree contains skinned content (bind-pose AABB
      // under-covers once joints animate, so the engine conservatively
      // refuses to commit to a number). When that happens fall back to
      // a translation hull of every node in the subtree — a rough but
      // robust scale estimate that gets Fox/BrainStem/RecursiveSkeletons
      // into frame instead of "model is way bigger than the camera
      // expected" territory.
      vm.Vector3 lookAt = vm.Vector3.zero();
      double radius = 1;
      final bounds = node.combinedLocalBounds ?? _nodeTranslationHull(node);
      if (bounds != null) {
        lookAt = vm.Vector3.copy(bounds.center);
        final extent = bounds.max - bounds.min;
        radius = max(extent.length * 0.5, 0.1);
      }
      // ~2.4× the bounding radius fills a 60-deg FOV without clipping.
      final double distance = max(radius * 2.4, 0.5);
      final double height = lookAt.y + radius * 0.4;
      // Initial camera: on the -Z side looking toward +Z. After the
      // importer's scene-root Z-flip, glTF models face -Z, so this puts
      // the camera in front of the model rather than behind it. Yaw=pi
      // turns the camera around to look back at the model; pitch tilts
      // down so it stays centered.
      _quake.position = vm.Vector3(lookAt.x, height, lookAt.z - distance);
      final dir = (lookAt - _quake.position)..normalize();
      _quake.yaw = pi;
      _quake.pitch = asin(
        dir.y,
      ).clamp(-QuakeCamera.pitchLimit, QuakeCamera.pitchLimit);
      _cameraSpeed = max(radius * 0.5, 0.5);
      _quake.speed = _cameraSpeed;

      // Kick off the first matching animation if requested.
      final wantedAnim = widget.test.animationName;
      if (wantedAnim != null) {
        final anim = _findAnimation(node, wantedAnim) ?? _firstAnimation(node);
        if (anim != null) {
          node.createAnimationClip(anim)
            ..loop = true
            ..play();
        }
      }

      _scene.add(node);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  // Switches the importer path and reloads the model. The download is cached,
  // so this just re-imports the same bytes via the chosen path.
  void _setImporterMode(_ImporterMode mode) {
    if (mode == _importerMode) return;
    _scene.removeAll();
    _modelRoot = null;
    _modelBaseTransform = null;
    setState(() {
      _importerMode = mode;
      _ready = false;
      _downloaded = 0;
      _error = null;
    });
    unawaited(_load());
  }

  void _applyModelScale() {
    final root = _modelRoot;
    final baseTransform = _modelBaseTransform;
    if (root == null || baseTransform == null) return;
    root.localTransform = baseTransform.clone()
      ..scaleByDouble(_modelScale, _modelScale, _modelScale, 1.0);
  }

  void _setModelScale(double value) {
    setState(() {
      _modelScale = value;
      _applyModelScale();
    });
  }

  void _setCameraSpeed(double value) {
    setState(() {
      _cameraSpeed = value;
      _quake.speed = value;
    });
  }

  void _applyCameraSoftness() {
    if (_cameraSoftness <= 0.0) {
      _quake.movementSmoothing = 0.0;
      _quake.lookSmoothing = 0.0;
      return;
    }
    final response = 1.0 / _cameraSoftness;
    _quake.movementSmoothing = response;
    _quake.lookSmoothing = response * 1.8;
  }

  void _setCameraSoftness(double value) {
    setState(() {
      _cameraSoftness = value;
      _applyCameraSoftness();
    });
  }

  // Switches the scene's image-based-lighting environment. Downloads and
  // decodes the HDR on first use (cached afterward); the built-in studio
  // environment needs no download.

  Animation? _findAnimation(Node root, String name) {
    final hit = root.findAnimationByName(name);
    if (hit != null) return hit;
    for (final child in root.children) {
      final inChild = _findAnimation(child, name);
      if (inChild != null) return inChild;
    }
    return null;
  }

  Animation? _firstAnimation(Node root) {
    final anims = _collectAnimations(root);
    return anims.isEmpty ? null : anims.first;
  }

  List<Animation> _collectAnimations(Node node) {
    final list = <Animation>[];
    list.addAll(node.parsedAnimations);
    for (final child in node.children) {
      list.addAll(_collectAnimations(child));
    }
    return list;
  }

  // One-shot diagnostic dump for stress-test loads: combinedLocalBounds
  // status, animation list, mesh count, and per-mesh material/texture
  // bindings. Helps sanity-check what the runtime importer produced
  // versus what the source glTF claims.
  void _debugDumpScene(Node root) {
    final bounds = root.combinedLocalBounds;
    final hull = _nodeTranslationHull(root);
    final anims = _collectAnimations(root);
    debugPrint(
      '[stress] ${widget.test.id}: '
      'combinedLocalBounds=${bounds == null ? "null" : "${bounds.min} .. ${bounds.max}"}, '
      'translationHull=${hull == null ? "null" : "${hull.min} .. ${hull.max}"}, '
      'animations.length=${anims.length} '
      '${anims.map((a) => "\"${a.name}\"").join(", ")}',
    );
    var meshIdx = 0;
    void visit(Node n) {
      final mesh = n.mesh;
      if (mesh != null) {
        for (final p in mesh.primitives) {
          final m = p.material;
          var summary = m.runtimeType.toString();
          if (m is PhysicallyBasedMaterial) {
            summary +=
                ' base=${m.baseColorFactor.storage.map((v) => v.toStringAsFixed(2)).toList()}'
                ' tex=${m.baseColorTexture == null ? "<missing>" : "<bound>"}'
                ' metRoughTex=${m.metallicRoughnessTexture == null ? "<missing>" : "<bound>"}'
                ' emissive=${m.emissiveFactor.storage.map((v) => v.toStringAsFixed(2)).toList()}';
          }
          debugPrint('[stress]   mesh#${meshIdx++} node="${n.name}": $summary');
        }
      }
      for (final c in n.children) {
        visit(c);
      }
    }

    visit(root);
  }

  // DEBUG: walk the subtree and set every PhysicallyBasedMaterial's
  // baseColorFactor to bright red. Diagnostic only; remove once we
  // know whether color flows.
  void _debugTintMaterials(Node root) {
    void visit(Node n) {
      final mesh = n.mesh;
      if (mesh != null) {
        for (final p in mesh.primitives) {
          final m = p.material;
          if (m is PhysicallyBasedMaterial) {
            m.baseColorFactor = vm.Vector4(1.0, 0.0, 0.0, 1.0);
          }
        }
      }
      for (final c in n.children) {
        visit(c);
      }
    }

    visit(root);
  }

  // Best-effort scale estimator for subtrees with skinned content (where
  // `combinedLocalBounds` bails). Walks every descendant and unions
  // their global translation. Doesn't account for mesh extent at each
  // node, so the radius can under-cover the actual geometry — but
  // padding the framing distance compensates. Returns null only when
  // the subtree is empty.
  vm.Aabb3? _nodeTranslationHull(Node root) {
    vm.Aabb3? hull;
    void visit(Node n) {
      final pos = n.globalTransform.getTranslation();
      if (hull == null) {
        hull = vm.Aabb3.minMax(vm.Vector3.copy(pos), vm.Vector3.copy(pos));
      } else {
        hull!.hullPoint(pos);
      }
      for (final c in n.children) {
        visit(c);
      }
    }

    visit(root);
    return hull;
  }

  @override
  void dispose() {
    if (_focused) exampleChromeVisible.value = true;
    _focusLockObserver.dispose();
    _focusPointer.dispose();
    _focusNode.dispose();
    _environmentSelector.dispose();
    _scene.removeAll();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _quake.look(d.delta));
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_focused &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        event is KeyDownEvent) {
      _exitFocus();
      return KeyEventResult.handled;
    }
    return _quake.onKeyEvent(node, event);
  }

  void _enterFocus() {
    if (_focused || !_ready) return;
    if (!kIsWeb) {
      unawaited(_enterNativeFocus());
      return;
    }
    _activateFocus();
  }

  Future<void> _enterNativeFocus() async {
    final available = await NativeMouseCursor.canWarpPointer();
    if (!mounted || _focused || !_ready) return;
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Direct mouse input is unavailable on this platform.'),
        ),
      );
      return;
    }
    _activateFocus();
  }

  void _activateFocus() {
    final size = MediaQuery.sizeOf(context);
    final center = Offset(size.width * 0.5, size.height * 0.5);
    setState(() => _focused = true);
    exampleChromeVisible.value = false;
    _focusNode.requestFocus();
    unawaited(
      _focusPointer.start(
        center,
        viewportSize: size,
        onLockedDelta: _onFocusLook,
      ),
    );
  }

  void _exitFocus() {
    if (!_focused) return;
    _quake.releaseKeys();
    unawaited(_focusPointer.end());
    exampleChromeVisible.value = true;
    if (mounted) setState(() => _focused = false);
  }

  void _onFocusLook(Offset delta) {
    if (!_focused) return;
    _quake.look(delta);
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (!_focused) return;
    final size = MediaQuery.sizeOf(context);
    unawaited(
      _focusPointer
          .updateOffset(
            globalPosition: event.position,
            delta: event.delta,
            viewportSize: size,
          )
          .then(_onFocusLook),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Focus(
          focusNode: _focusNode,
          autofocus: _ready,
          onKeyEvent: _onKeyEvent,
          onFocusChange: (focused) {
            if (!focused && _focused) _exitFocus();
          },
          child: IgnorePointer(
            ignoring: !_ready,
            child: MouseRegion(
              cursor: _focused
                  ? SystemMouseCursors.none
                  : _ready
                  ? SystemMouseCursors.move
                  : SystemMouseCursors.basic,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerHover: _onPointerHover,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: _focused ? null : (_) => _focusNode.requestFocus(),
                  onPanUpdate: _focused ? null : _onPanUpdate,
                  child: SceneView(
                    _scene,
                    cameraBuilder: (elapsed) {
                      _quake.move(elapsed.inMicroseconds / 1e6);
                      return _quake.camera;
                    },
                    onTick: (elapsed, deltaSeconds) {
                      exampleSettings.applyTo(_scene);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          ExampleLoadFailureCard(
            title: 'Failed to load ${widget.test.title}',
            detail: '$_error',
          )
        else if (!_ready)
          _LoadingOverlay(
            title: widget.test.title,
            downloaded: _downloaded,
            total: _total,
          ),
        if (!_focused)
          ExampleOverlay.topCenterAction(
            maxWidth: 820,
            minHeaderWidth: 620,
            leadingReservation: 160,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ExampleActionButton(
                      tooltip: 'Back to stress tests',
                      icon: Icons.arrow_back,
                      onPressed: widget.onBack,
                    ),
                    ExampleActionButton(
                      tooltip: 'Previous stress test',
                      icon: Icons.navigate_before,
                      onPressed: widget.onPrevious,
                    ),
                    _StressTestTitle(
                      title: widget.test.title,
                      position: widget.catalogIndex + 1,
                      total: widget.catalogLength,
                    ),
                    ExampleActionButton(
                      tooltip: 'Next stress test',
                      icon: Icons.navigate_next,
                      onPressed: widget.onNext,
                    ),
                    if (_ready && !widget.test.isMultiFile)
                      _ImporterModeControl(
                        selected: _importerMode,
                        onChanged: _setImporterMode,
                      ),
                    if (_ready)
                      ExampleCameraToggle(
                        active: false,
                        inactiveLabel: 'Focus',
                        activeLabel: 'Focused',
                        inactiveIcon: Icons.center_focus_strong,
                        activeIcon: Icons.center_focus_strong,
                        onToggle: _enterFocus,
                      ),
                  ],
                ),
                if (_ready) ...[
                  const SizedBox(height: 8),
                  const ExampleActionHint(
                    message:
                        'WASD move  ·  QE up/down  ·  Drag: look  ·  Shift: boost',
                  ),
                ],
              ],
            ),
          ),
        if (_ready)
          ExampleOverlay.bottomLeftPanel(
            paired: true,
            child: Offstage(
              offstage: _focused,
              child: LightingPanel(
                scene: _scene,
                selector: _environmentSelector,
                initialSkyBlur: 0.40,
                initialEnvironmentId: 'helipad',
              ),
            ),
          ),
        if (_ready)
          ExampleOverlay.bottomRightPanel(
            paired: true,
            child: Offstage(
              offstage: _focused,
              child: _StressControlsPanel(
                modelScale: _modelScale,
                cameraSpeed: _cameraSpeed,
                cameraSoftness: _cameraSoftness,
                onModelScaleChanged: _setModelScale,
                onCameraSpeedChanged: _setCameraSpeed,
                onCameraSoftnessChanged: _setCameraSoftness,
              ),
            ),
          ),
      ],
    );
  }
}

class _StressTestTitle extends StatelessWidget {
  const _StressTestTitle({
    required this.title,
    required this.position,
    required this.total,
  });

  final String title;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$position of $total',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StressControlsPanel extends StatelessWidget {
  const _StressControlsPanel({
    required this.modelScale,
    required this.cameraSpeed,
    required this.cameraSoftness,
    required this.onModelScaleChanged,
    required this.onCameraSpeedChanged,
    required this.onCameraSoftnessChanged,
  });

  final double modelScale;
  final double cameraSpeed;
  final double cameraSoftness;
  final ValueChanged<double> onModelScaleChanged;
  final ValueChanged<double> onCameraSpeedChanged;
  final ValueChanged<double> onCameraSoftnessChanged;

  static double _log10(double value) => log(value) / ln10;

  @override
  Widget build(BuildContext context) {
    return ExamplePanelCard(
      icon: Icons.tune,
      title: 'Scene controls',
      width: 340,
      maxBodyHeight: 220,
      bodyPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledSlider(
            label: 'Model scale',
            value: _log10(modelScale),
            valueText: '${modelScale.toStringAsFixed(2)}×',
            min: -2.0,
            max: 2.0,
            onChanged: (value) =>
                onModelScaleChanged(pow(10.0, value).toDouble()),
          ),
          LabeledSlider(
            label: 'Camera speed',
            value: _log10(cameraSpeed),
            valueText: cameraSpeed.toStringAsFixed(2),
            min: -2.0,
            max: 3.0,
            onChanged: (value) =>
                onCameraSpeedChanged(pow(10.0, value).toDouble()),
          ),
          LabeledSlider(
            label: 'Camera softness',
            value: cameraSoftness,
            valueText: cameraSoftness.toStringAsFixed(2),
            min: 0.0,
            max: 2.0,
            onChanged: onCameraSoftnessChanged,
          ),
        ],
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({
    required this.title,
    required this.downloaded,
    required this.total,
  });

  final String title;
  final int downloaded;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    final progress = (total != null && total > 0) ? downloaded / total : null;
    return ExampleStatusCard(
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Downloading $title',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              color: Colors.deepPurpleAccent,
              backgroundColor: Colors.white24,
            ),
            const SizedBox(height: 8),
            Text(
              total == null
                  ? _formatBytes(downloaded)
                  : '${_formatBytes(downloaded)} / ${_formatBytes(total)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImporterModeControl extends StatelessWidget {
  const _ImporterModeControl({required this.selected, required this.onChanged});

  final _ImporterMode selected;
  final ValueChanged<_ImporterMode> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    borderRadius: BorderRadius.circular(8),
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, right: 8),
            child: Text('Importer', style: TextStyle(color: Colors.white)),
          ),
          SegmentedButton<_ImporterMode>(
            showSelectedIcon: false,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white24
                    : Colors.transparent,
              ),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              side: const WidgetStatePropertyAll(
                BorderSide(color: Colors.white38),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                value: _ImporterMode.runtime,
                label: Text('Runtime'),
              ),
              ButtonSegment(
                value: _ImporterMode.offline,
                label: Text('Offline'),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    ),
  );
}

// Downloads (and caches) the model for `test` and imports it.
//
// Single-file `.glb` models go through Node.fromGlbBytes. Multi-file
// `.gltf` models download the `.gltf` and resolve its `.bin` / image
// siblings on demand through Node.fromGltfBytes; every sibling is
// fetched relative to the `.gltf`'s own URL and cached beside it.
Future<Node> _importTest(
  _StressTest test,
  _ImporterMode mode,
  void Function(int) onChunk,
) async {
  if (!test.isMultiFile) {
    final bytes = await fetchResource(
      test.url,
      onChunk: onChunk,
      expectedSize: test.sizeBytes,
    );
    if (mode == _ImporterMode.offline) {
      // Exercise the offline (ahead-of-time) importer: run the same
      // glTF -> .fsceneb conversion the build hook performs, in memory, then
      // realize the result. This is the path issue #134 lives in.
      final scenebBytes = importGlbToFscenebBytes(bytes);
      return loadFscenebBytesAsync(scenebBytes);
    }
    return Node.fromGlbBytes(bytes);
  }

  // Multi-file glTF: the offline importer is .glb-only, so this is always the
  // runtime path. The `.gltf` and its `.bin` / image siblings are each fetched
  // (and cached) by their own absolute URL, resolved relative to the `.gltf`'s
  // URL.
  final baseUri = Uri.parse(test.url);
  final gltfBytes = await fetchResource(test.url, onChunk: onChunk);
  return Node.fromGltfBytes(
    gltfBytes,
    resolveUri: (uri) =>
        fetchResource(baseUri.resolve(uri).toString(), onChunk: onChunk),
  );
}

// Fetches `url` and returns its bytes. Serves from the platform cache
// (on-disk on native, in-memory on web) when a usable copy is present;
// otherwise streams the download via http, caches it, and returns it.
// `onChunk` is fed each streamed chunk's length -- and the whole length on a
// cache hit -- so callers can show cumulative progress.

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
