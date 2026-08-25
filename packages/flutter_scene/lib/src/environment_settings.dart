/// A snapshot of a scene's blendable look (image-based lighting, exposure,
/// tone mapping, and post-processing), captured as a copyable value that can be
/// interpolated. Drives scripted environment transitions.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/ambient_occlusion.dart';
import 'package:flutter_scene/src/depth_of_field.dart';
import 'package:flutter_scene/src/fog.dart';
import 'package:flutter_scene/src/global_illumination.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/post_process/color_lut.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_environment.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/sun_light.dart';
import 'package:flutter_scene/src/tone_mapping.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

Vector3 _lerpVec3(Vector3 a, Vector3 b, double t) =>
    Vector3(_lerp(a.x, b.x, t), _lerp(a.y, b.y, t), _lerp(a.z, b.z, t));

/// A copyable, interpolatable snapshot of a [Scene]'s scene-wide look.
///
/// Read one with `Scene.environmentSettings` and apply one by assigning it
/// back. [lerp] blends two snapshots: continuous fields (exposure, intensities,
/// color-grading and post-effect parameters) interpolate; discrete fields (the
/// image-based-lighting environment, skybox, sky lighting, sun light, tone
/// mapping operator, and each effect's `enabled` flag) switch at the halfway
/// point so the endpoints reproduce the inputs exactly. To cross-fade an effect
/// on or off smoothly, animate its amount (e.g. bloom intensity) rather than
/// relying on the flag.
///
/// A typical scripted transition drives `t` from an animation each frame:
/// ```dart
/// scene.environmentSettings = EnvironmentSettings.lerp(dayLook, nightLook, t);
/// ```
/// {@category Lighting and environment}
class EnvironmentSettings {
  // TODO(environment-settings): compose per-feature snapshots that each
  // capture, apply, and interpolate their fields in one place.
  /// Creates a settings snapshot. Most callers use `Scene.environmentSettings`
  /// or [EnvironmentSettings.lerp] instead of this directly.
  EnvironmentSettings({
    this.environment,
    Matrix3? environmentTransform,
    this.skybox,
    this.skyEnvironment,
    this.sunLight,
    this.toneMapping = ToneMappingMode.pbrNeutral,
    this.agxWhite = 16.29,
    this.agxContrast = 1.25,
    this.environmentIntensity = 1.0,
    this.exposure = 1.0,
    this.colorGradingEnabled = false,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    Vector3? lift,
    Vector3? gamma,
    Vector3? gain,
    this.colorGradingLut,
    this.colorGradingLutBlend = 1.0,
    this.bloomEnabled = false,
    this.bloomThreshold = 1.0,
    this.bloomIntensity = 0.15,
    this.bloomScatter = 0.7,
    this.lensFlareEnabled = false,
    this.lensFlareIntensity = 1.0,
    this.lensFlareGhostCount = 4,
    this.lensFlareGhostSpacing = 0.3,
    this.lensFlareHaloRadius = 0.35,
    this.lensFlareHaloIntensity = 1.0,
    this.lensFlareChromaticAberration = 0.005,
    this.vignetteEnabled = false,
    this.vignetteIntensity = 0.5,
    this.vignetteRadius = 0.75,
    this.vignetteSmoothness = 0.5,
    this.chromaticAberrationEnabled = false,
    this.chromaticAberrationIntensity = 0.2,
    this.filmGrainEnabled = false,
    this.filmGrainIntensity = 0.3,
    this.ambientOcclusionEnabled = false,
    this.ambientOcclusionMethod = AmbientOcclusionMethod.obscurance,
    this.ambientOcclusionRadius = 0.33,
    this.ambientOcclusionIntensity = 1.0,
    this.ambientOcclusionBias = 0.07,
    this.ambientOcclusionPower = 1.5,
    this.ambientOcclusionDetail = 0.5,
    this.ambientOcclusionHorizonAngle = 0.06,
    this.ambientOcclusionDirectLightAffect = 0.0,
    this.ambientOcclusionMultiBounce = 0.0,
    this.ambientOcclusionSampleCount = 16,
    this.ambientOcclusionSliceCount = 3,
    this.ambientOcclusionStepsPerSlice = 3,
    this.ambientOcclusionVisibilityBitmask = false,
    this.ambientOcclusionThickness = 0.5,
    this.ambientOcclusionThicknessHeuristic = 0.004,
    this.ambientOcclusionBentNormals = false,
    this.ambientOcclusionIndirectLight = 0.0,
    this.ambientOcclusionHalfResolution = true,
    this.ambientOcclusionDepthMipChain = false,
    this.ambientOcclusionSpecularMode = SpecularAmbientOcclusionMode.none,
    this.screenSpaceReflectionsEnabled = false,
    this.screenSpaceReflectionsIntensity = 1.0,
    this.screenSpaceReflectionsMaxDistance = 24.4,
    this.screenSpaceReflectionsThickness = 0.46,
    this.screenSpaceReflectionsStride = 9.0,
    this.screenSpaceReflectionsMaxSteps = 90,
    this.screenSpaceReflectionsBlur = 0.3,
    this.screenSpaceReflectionsDistanceFadeStart = 0.0,
    this.screenSpaceReflectionsResolutionScale = 1.0,
    this.globalIlluminationEnabled = false,
    this.globalIlluminationVolumeMode = IrradianceVolumeMode.followCamera,
    Vector3? globalIlluminationResolution,
    Vector3? globalIlluminationExtents,
    this.globalIlluminationIntensity = 1.0,
    this.globalIlluminationHysteresis = 0.95,
    this.globalIlluminationShadowBias = 0.3,
    this.globalIlluminationVisibility = 0.7,
    this.globalIlluminationVisibilityBias = 0.08,
    this.globalIlluminationProbeUpdateBudget = 0,
    this.globalIlluminationInjectionResolution =
        IrradianceInjectionResolution.eighth,
    this.globalIlluminationFireflyClamp = 8.0,
    this.globalIlluminationEmissiveBoost = 1.0,
    this.globalIlluminationUpdateWhenIdleOnly = false,
    this.globalIlluminationBakeOnly = false,
    this.fogEnabled = false,
    this.fogMode = FogMode.exponential,
    Vector3? fogColor,
    this.fogSkyColorInfluence = 0.0,
    this.fogDensity = 0.02,
    this.fogStart = 0.0,
    this.fogEnd = 200.0,
    this.fogMaxOpacity = 1.0,
    this.fogCutoffDistance = 0.0,
    this.fogHeight = 0.0,
    this.fogHeightFalloff = 0.0,
    this.fogSunInScatter = 0.0,
    this.fogSunInScatterExponent = 8.0,
    this.godRaysEnabled = false,
    this.godRaysIntensity = 1.0,
    this.godRaysDensity = 0.5,
    this.godRaysAnisotropy = 0.7,
    this.godRaysStepCount = 24,
    this.godRaysMaxDistance = 200.0,
    this.godRaysJitter = 1.0,
    Vector3? godRaysColor,
    this.depthOfFieldEnabled = false,
    this.depthOfFieldFocusDistance = 10.0,
    this.depthOfFieldFStop = 2.8,
    this.depthOfFieldFocalLength = 0.0,
    this.depthOfFieldSensorHeight = 0.024,
    this.depthOfFieldBlurScale = 1.0,
    this.depthOfFieldMaxForegroundBlur = 24.0,
    this.depthOfFieldMaxBackgroundBlur = 32.0,
    this.depthOfFieldBladeCount = 0,
    this.depthOfFieldBladeRotation = 0.0,
    this.depthOfFieldBladeCurvature = 0.0,
    this.depthOfFieldQuality = DepthOfFieldQuality.medium,
    this.autoExposureEnabled = false,
    this.autoExposureStrength = 0.55,
    this.autoExposureCompensation = 0.0,
    this.autoExposureMinEv = -4.0,
    this.autoExposureMaxEv = 4.0,
    this.autoExposureSpeedUp = 3.0,
    this.autoExposureSpeedDown = 1.0,
  }) : environmentTransform = environmentTransform ?? Matrix3.identity(),
       lift = lift ?? Vector3.zero(),
       gamma = gamma ?? Vector3.all(1.0),
       gain = gain ?? Vector3.all(1.0),
       globalIlluminationResolution =
           globalIlluminationResolution ?? Vector3(16, 8, 16),
       globalIlluminationExtents =
           globalIlluminationExtents ?? Vector3(20, 10, 20),
       fogColor = fogColor ?? Vector3(0.6, 0.7, 0.8),
       godRaysColor = godRaysColor ?? Vector3.all(1.0);

  // Image-based lighting and sky (discrete: switched, not blended).
  EnvironmentMap? environment;
  Matrix3 environmentTransform;
  Skybox? skybox;
  SkyEnvironment? skyEnvironment;
  SunLight? sunLight;
  ToneMappingMode toneMapping;
  double agxWhite;
  double agxContrast;

  // Scene scalars (continuous).
  double environmentIntensity;
  double exposure;

  // Color grading.
  bool colorGradingEnabled;
  double brightness;
  double contrast;
  double saturation;
  double temperature;
  double tint;
  Vector3 lift;
  Vector3 gamma;
  Vector3 gain;
  ColorLut? colorGradingLut;
  double colorGradingLutBlend;

  // Bloom.
  bool bloomEnabled;
  double bloomThreshold;
  double bloomIntensity;
  double bloomScatter;
  bool lensFlareEnabled;
  double lensFlareIntensity;
  int lensFlareGhostCount;
  double lensFlareGhostSpacing;
  double lensFlareHaloRadius;
  double lensFlareHaloIntensity;
  double lensFlareChromaticAberration;

  // Vignette.
  bool vignetteEnabled;
  double vignetteIntensity;
  double vignetteRadius;
  double vignetteSmoothness;

  // Chromatic aberration.
  bool chromaticAberrationEnabled;
  double chromaticAberrationIntensity;

  // Film grain.
  bool filmGrainEnabled;
  double filmGrainIntensity;

  // Ambient occlusion.
  bool ambientOcclusionEnabled;
  AmbientOcclusionMethod ambientOcclusionMethod;
  double ambientOcclusionRadius;
  double ambientOcclusionIntensity;
  double ambientOcclusionBias;
  double ambientOcclusionPower;
  double ambientOcclusionDetail;
  double ambientOcclusionHorizonAngle;
  double ambientOcclusionDirectLightAffect;
  double ambientOcclusionMultiBounce;
  int ambientOcclusionSampleCount;
  int ambientOcclusionSliceCount;
  int ambientOcclusionStepsPerSlice;
  bool ambientOcclusionVisibilityBitmask;
  double ambientOcclusionThickness;
  double ambientOcclusionThicknessHeuristic;
  bool ambientOcclusionBentNormals;
  double ambientOcclusionIndirectLight;
  bool ambientOcclusionHalfResolution;
  bool ambientOcclusionDepthMipChain;
  SpecularAmbientOcclusionMode ambientOcclusionSpecularMode;

  // Screen-space reflections.
  bool screenSpaceReflectionsEnabled;
  double screenSpaceReflectionsIntensity;
  double screenSpaceReflectionsMaxDistance;
  double screenSpaceReflectionsThickness;
  double screenSpaceReflectionsStride;
  int screenSpaceReflectionsMaxSteps;
  double screenSpaceReflectionsBlur;
  double screenSpaceReflectionsDistanceFadeStart;
  double screenSpaceReflectionsResolutionScale;

  // World-space global illumination.
  bool globalIlluminationEnabled;
  IrradianceVolumeMode globalIlluminationVolumeMode;
  Vector3 globalIlluminationResolution;
  Vector3 globalIlluminationExtents;
  double globalIlluminationIntensity;
  double globalIlluminationHysteresis;
  double globalIlluminationShadowBias;
  double globalIlluminationVisibility;
  double globalIlluminationVisibilityBias;
  int globalIlluminationProbeUpdateBudget;
  IrradianceInjectionResolution globalIlluminationInjectionResolution;
  double globalIlluminationFireflyClamp;
  double globalIlluminationEmissiveBoost;
  bool globalIlluminationUpdateWhenIdleOnly;
  bool globalIlluminationBakeOnly;

  // Fog.
  bool fogEnabled;
  FogMode fogMode;
  Vector3 fogColor;
  double fogSkyColorInfluence;
  double fogDensity;
  double fogStart;
  double fogEnd;
  double fogMaxOpacity;
  double fogCutoffDistance;
  double fogHeight;
  double fogHeightFalloff;
  double fogSunInScatter;
  double fogSunInScatterExponent;

  // God rays.
  bool godRaysEnabled;
  double godRaysIntensity;
  double godRaysDensity;
  double godRaysAnisotropy;
  int godRaysStepCount;
  double godRaysMaxDistance;
  double godRaysJitter;
  Vector3 godRaysColor;

  // Depth of field.
  bool depthOfFieldEnabled;
  double depthOfFieldFocusDistance;
  double depthOfFieldFStop;
  double depthOfFieldFocalLength;
  double depthOfFieldSensorHeight;
  double depthOfFieldBlurScale;
  double depthOfFieldMaxForegroundBlur;
  double depthOfFieldMaxBackgroundBlur;
  int depthOfFieldBladeCount;
  double depthOfFieldBladeRotation;
  double depthOfFieldBladeCurvature;
  DepthOfFieldQuality depthOfFieldQuality;

  // Automatic exposure.
  bool autoExposureEnabled;
  double autoExposureStrength;
  double autoExposureCompensation;
  double autoExposureMinEv;
  double autoExposureMaxEv;
  double autoExposureSpeedUp;
  double autoExposureSpeedDown;

  /// Reads the current look of [scene] into a snapshot. The IBL/sky references
  /// are shared (not deep-copied); the scalar look is captured by value.
  factory EnvironmentSettings.fromScene(Scene scene) {
    final cg = scene.postProcess.colorGrading;
    final bloom = scene.postProcess.bloom;
    final vignette = scene.postProcess.vignette;
    final ca = scene.postProcess.chromaticAberration;
    final grain = scene.postProcess.filmGrain;
    final ao = scene.ambientOcclusion;
    final ssr = scene.screenSpaceReflections;
    final gi = scene.globalIllumination;
    final fog = scene.fog;
    final rays = scene.godRays;
    final dof = scene.depthOfField;
    final auto = scene.autoExposure;
    return EnvironmentSettings(
      environment: scene.environment,
      environmentTransform: scene.environmentTransform.clone(),
      skybox: scene.skybox,
      skyEnvironment: scene.skyEnvironment,
      sunLight: scene.sunLight,
      toneMapping: scene.toneMapping,
      agxWhite: scene.agxWhite,
      agxContrast: scene.agxContrast,
      environmentIntensity: scene.environmentIntensity,
      exposure: scene.exposure,
      colorGradingEnabled: cg.enabled,
      brightness: cg.brightness,
      contrast: cg.contrast,
      saturation: cg.saturation,
      temperature: cg.temperature,
      tint: cg.tint,
      lift: cg.lift.clone(),
      gamma: cg.gamma.clone(),
      gain: cg.gain.clone(),
      colorGradingLut: cg.lut,
      colorGradingLutBlend: cg.lutBlend,
      bloomEnabled: bloom.enabled,
      bloomThreshold: bloom.threshold,
      bloomIntensity: bloom.intensity,
      bloomScatter: bloom.scatter,
      lensFlareEnabled: bloom.lensFlare.enabled,
      lensFlareIntensity: bloom.lensFlare.intensity,
      lensFlareGhostCount: bloom.lensFlare.ghostCount,
      lensFlareGhostSpacing: bloom.lensFlare.ghostSpacing,
      lensFlareHaloRadius: bloom.lensFlare.haloRadius,
      lensFlareHaloIntensity: bloom.lensFlare.haloIntensity,
      lensFlareChromaticAberration: bloom.lensFlare.chromaticAberration,
      vignetteEnabled: vignette.enabled,
      vignetteIntensity: vignette.intensity,
      vignetteRadius: vignette.radius,
      vignetteSmoothness: vignette.smoothness,
      chromaticAberrationEnabled: ca.enabled,
      chromaticAberrationIntensity: ca.intensity,
      filmGrainEnabled: grain.enabled,
      filmGrainIntensity: grain.intensity,
      ambientOcclusionEnabled: ao.enabled,
      ambientOcclusionMethod: ao.method,
      ambientOcclusionRadius: ao.radius,
      ambientOcclusionIntensity: ao.intensity,
      ambientOcclusionBias: ao.bias,
      ambientOcclusionPower: ao.power,
      ambientOcclusionDetail: ao.detail,
      ambientOcclusionHorizonAngle: ao.horizonAngle,
      ambientOcclusionDirectLightAffect: ao.directLightAffect,
      ambientOcclusionMultiBounce: ao.multiBounce,
      ambientOcclusionSampleCount: ao.sampleCount,
      ambientOcclusionSliceCount: ao.sliceCount,
      ambientOcclusionStepsPerSlice: ao.stepsPerSlice,
      ambientOcclusionVisibilityBitmask: ao.visibilityBitmask,
      ambientOcclusionThickness: ao.thickness,
      ambientOcclusionThicknessHeuristic: ao.thicknessHeuristic,
      ambientOcclusionBentNormals: ao.bentNormals,
      ambientOcclusionIndirectLight: ao.indirectLight,
      ambientOcclusionHalfResolution: ao.halfResolution,
      ambientOcclusionDepthMipChain: ao.depthMipChain,
      ambientOcclusionSpecularMode: ao.specularMode,
      screenSpaceReflectionsEnabled: ssr.enabled,
      screenSpaceReflectionsIntensity: ssr.intensity,
      screenSpaceReflectionsMaxDistance: ssr.maxDistance,
      screenSpaceReflectionsThickness: ssr.thickness,
      screenSpaceReflectionsStride: ssr.stride,
      screenSpaceReflectionsMaxSteps: ssr.maxSteps,
      screenSpaceReflectionsBlur: ssr.blur,
      screenSpaceReflectionsDistanceFadeStart: ssr.distanceFadeStart,
      screenSpaceReflectionsResolutionScale: ssr.resolutionScale,
      globalIlluminationEnabled: gi.enabled,
      globalIlluminationVolumeMode: gi.volumeMode,
      globalIlluminationResolution: gi.resolution.clone(),
      globalIlluminationExtents: gi.extents.clone(),
      globalIlluminationIntensity: gi.intensity,
      globalIlluminationHysteresis: gi.hysteresis,
      globalIlluminationShadowBias: gi.shadowBias,
      globalIlluminationVisibility: gi.visibility,
      globalIlluminationVisibilityBias: gi.visibilityBias,
      globalIlluminationProbeUpdateBudget: gi.probeUpdateBudget,
      globalIlluminationInjectionResolution: gi.injectionResolution,
      globalIlluminationFireflyClamp: gi.fireflyClamp,
      globalIlluminationEmissiveBoost: gi.emissiveGiBoost,
      globalIlluminationUpdateWhenIdleOnly: gi.updateWhenIdleOnly,
      globalIlluminationBakeOnly: gi.bakeOnly,
      fogEnabled: fog.enabled,
      fogMode: fog.mode,
      fogColor: fog.color.clone(),
      fogSkyColorInfluence: fog.skyColorInfluence,
      fogDensity: fog.density,
      fogStart: fog.start,
      fogEnd: fog.end,
      fogMaxOpacity: fog.maxOpacity,
      fogCutoffDistance: fog.cutoffDistance,
      fogHeight: fog.height,
      fogHeightFalloff: fog.heightFalloff,
      fogSunInScatter: fog.sunInScatter,
      fogSunInScatterExponent: fog.sunInScatterExponent,
      godRaysEnabled: rays.enabled,
      godRaysIntensity: rays.intensity,
      godRaysDensity: rays.density,
      godRaysAnisotropy: rays.anisotropy,
      godRaysStepCount: rays.stepCount,
      godRaysMaxDistance: rays.maxDistance,
      godRaysJitter: rays.jitter,
      godRaysColor: rays.color.clone(),
      depthOfFieldEnabled: dof.enabled,
      depthOfFieldFocusDistance: dof.focusDistance,
      depthOfFieldFStop: dof.fStop,
      depthOfFieldFocalLength: dof.focalLength,
      depthOfFieldSensorHeight: dof.sensorHeight,
      depthOfFieldBlurScale: dof.blurScale,
      depthOfFieldMaxForegroundBlur: dof.maxForegroundBlur,
      depthOfFieldMaxBackgroundBlur: dof.maxBackgroundBlur,
      depthOfFieldBladeCount: dof.bladeCount,
      depthOfFieldBladeRotation: dof.bladeRotation,
      depthOfFieldBladeCurvature: dof.bladeCurvature,
      depthOfFieldQuality: dof.quality,
      autoExposureEnabled: auto.enabled,
      autoExposureStrength: auto.strength,
      autoExposureCompensation: auto.compensation,
      autoExposureMinEv: auto.minEv,
      autoExposureMaxEv: auto.maxEv,
      autoExposureSpeedUp: auto.speedUp,
      autoExposureSpeedDown: auto.speedDown,
    );
  }

  /// Applies the environment, sky, exposure, and tone mapping to [scene].
  void applyLookTo(Scene scene) {
    // A sky-lit look has no static [environment]; its sky bakes the scene
    // environment over the next frames. Keep the previously baked environment
    // until then, so re-applying a sky-lit look (an editor edit, or the volume
    // blend each frame) does not briefly drop to the default environment.
    if (environment != null || skyEnvironment == null) {
      scene.environment = environment;
    }
    scene.skybox = skybox;
    scene.skyEnvironment = skyEnvironment;
    scene.sunLight = sunLight;
    scene.toneMapping = toneMapping;
    scene.agxWhite = agxWhite;
    scene.agxContrast = agxContrast;
    scene.environmentIntensity = environmentIntensity;
    scene.environmentTransform.setFrom(environmentTransform);
    scene.exposure = exposure;
  }

  /// Applies this snapshot to [scene], mutating its live look fields.
  void applyTo(Scene scene) {
    applyLookTo(scene);

    final cg = scene.postProcess.colorGrading;
    cg
      ..enabled = colorGradingEnabled
      ..brightness = brightness
      ..contrast = contrast
      ..saturation = saturation
      ..temperature = temperature
      ..tint = tint
      ..lift.setFrom(lift)
      ..gamma.setFrom(gamma)
      ..gain.setFrom(gain)
      ..lut = colorGradingLut
      ..lutBlend = colorGradingLutBlend;

    final bloom = scene.postProcess.bloom;
    bloom
      ..enabled = bloomEnabled
      ..threshold = bloomThreshold
      ..intensity = bloomIntensity
      ..scatter = bloomScatter;
    bloom.lensFlare
      ..enabled = lensFlareEnabled
      ..intensity = lensFlareIntensity
      ..ghostCount = lensFlareGhostCount
      ..ghostSpacing = lensFlareGhostSpacing
      ..haloRadius = lensFlareHaloRadius
      ..haloIntensity = lensFlareHaloIntensity
      ..chromaticAberration = lensFlareChromaticAberration;

    final vignette = scene.postProcess.vignette;
    vignette
      ..enabled = vignetteEnabled
      ..intensity = vignetteIntensity
      ..radius = vignetteRadius
      ..smoothness = vignetteSmoothness;

    scene.postProcess.chromaticAberration
      ..enabled = chromaticAberrationEnabled
      ..intensity = chromaticAberrationIntensity;

    scene.postProcess.filmGrain
      ..enabled = filmGrainEnabled
      ..intensity = filmGrainIntensity;

    scene.ambientOcclusion
      ..enabled = ambientOcclusionEnabled
      ..method = ambientOcclusionMethod
      ..radius = ambientOcclusionRadius
      ..intensity = ambientOcclusionIntensity
      ..bias = ambientOcclusionBias
      ..power = ambientOcclusionPower
      ..detail = ambientOcclusionDetail
      ..horizonAngle = ambientOcclusionHorizonAngle
      ..directLightAffect = ambientOcclusionDirectLightAffect
      ..multiBounce = ambientOcclusionMultiBounce
      ..sampleCount = ambientOcclusionSampleCount
      ..sliceCount = ambientOcclusionSliceCount
      ..stepsPerSlice = ambientOcclusionStepsPerSlice
      ..visibilityBitmask = ambientOcclusionVisibilityBitmask
      ..thickness = ambientOcclusionThickness
      ..thicknessHeuristic = ambientOcclusionThicknessHeuristic
      ..bentNormals = ambientOcclusionBentNormals
      ..indirectLight = ambientOcclusionIndirectLight
      ..halfResolution = ambientOcclusionHalfResolution
      ..depthMipChain = ambientOcclusionDepthMipChain
      ..specularMode = ambientOcclusionSpecularMode;

    scene.screenSpaceReflections
      ..enabled = screenSpaceReflectionsEnabled
      ..intensity = screenSpaceReflectionsIntensity
      ..maxDistance = screenSpaceReflectionsMaxDistance
      ..thickness = screenSpaceReflectionsThickness
      ..stride = screenSpaceReflectionsStride
      ..maxSteps = screenSpaceReflectionsMaxSteps
      ..blur = screenSpaceReflectionsBlur
      ..distanceFadeStart = screenSpaceReflectionsDistanceFadeStart
      ..resolutionScale = screenSpaceReflectionsResolutionScale;

    scene.globalIllumination
      ..enabled = globalIlluminationEnabled
      ..volumeMode = globalIlluminationVolumeMode
      ..resolution = globalIlluminationResolution.clone()
      ..extents = globalIlluminationExtents.clone()
      ..intensity = globalIlluminationIntensity
      ..hysteresis = globalIlluminationHysteresis
      ..shadowBias = globalIlluminationShadowBias
      ..visibility = globalIlluminationVisibility
      ..visibilityBias = globalIlluminationVisibilityBias
      ..probeUpdateBudget = globalIlluminationProbeUpdateBudget
      ..injectionResolution = globalIlluminationInjectionResolution
      ..fireflyClamp = globalIlluminationFireflyClamp
      ..emissiveGiBoost = globalIlluminationEmissiveBoost
      ..updateWhenIdleOnly = globalIlluminationUpdateWhenIdleOnly
      ..bakeOnly = globalIlluminationBakeOnly;

    scene.fog
      ..enabled = fogEnabled
      ..mode = fogMode
      ..color.setFrom(fogColor)
      ..skyColorInfluence = fogSkyColorInfluence
      ..density = fogDensity
      ..start = fogStart
      ..end = fogEnd
      ..maxOpacity = fogMaxOpacity
      ..cutoffDistance = fogCutoffDistance
      ..height = fogHeight
      ..heightFalloff = fogHeightFalloff
      ..sunInScatter = fogSunInScatter
      ..sunInScatterExponent = fogSunInScatterExponent;

    scene.godRays
      ..enabled = godRaysEnabled
      ..intensity = godRaysIntensity
      ..density = godRaysDensity
      ..anisotropy = godRaysAnisotropy
      ..stepCount = godRaysStepCount
      ..maxDistance = godRaysMaxDistance
      ..jitter = godRaysJitter
      ..color.setFrom(godRaysColor);

    scene.depthOfField
      ..enabled = depthOfFieldEnabled
      ..focusDistance = depthOfFieldFocusDistance
      ..fStop = depthOfFieldFStop
      ..focalLength = depthOfFieldFocalLength
      ..sensorHeight = depthOfFieldSensorHeight
      ..blurScale = depthOfFieldBlurScale
      ..maxForegroundBlur = depthOfFieldMaxForegroundBlur
      ..maxBackgroundBlur = depthOfFieldMaxBackgroundBlur
      ..bladeCount = depthOfFieldBladeCount
      ..bladeRotation = depthOfFieldBladeRotation
      ..bladeCurvature = depthOfFieldBladeCurvature
      ..quality = depthOfFieldQuality;

    scene.autoExposure
      ..enabled = autoExposureEnabled
      ..strength = autoExposureStrength
      ..compensation = autoExposureCompensation
      ..minEv = autoExposureMinEv
      ..maxEv = autoExposureMaxEv
      ..speedUp = autoExposureSpeedUp
      ..speedDown = autoExposureSpeedDown;
  }

  /// Interpolates from [a] to [b] by [t] (0 = [a], 1 = [b]). See the class doc
  /// for which fields blend and which switch.
  static EnvironmentSettings lerp(
    EnvironmentSettings a,
    EnvironmentSettings b,
    double t,
  ) {
    final pickB = t >= 0.5;
    EnvironmentSettings d = pickB ? b : a;
    return EnvironmentSettings(
      environment: d.environment,
      environmentTransform: d.environmentTransform.clone(),
      skybox: d.skybox,
      skyEnvironment: d.skyEnvironment,
      sunLight: d.sunLight,
      toneMapping: d.toneMapping,
      agxWhite: _lerp(a.agxWhite, b.agxWhite, t),
      agxContrast: _lerp(a.agxContrast, b.agxContrast, t),
      environmentIntensity: _lerp(
        a.environmentIntensity,
        b.environmentIntensity,
        t,
      ),
      exposure: _lerp(a.exposure, b.exposure, t),
      colorGradingEnabled: d.colorGradingEnabled,
      brightness: _lerp(a.brightness, b.brightness, t),
      contrast: _lerp(a.contrast, b.contrast, t),
      saturation: _lerp(a.saturation, b.saturation, t),
      temperature: _lerp(a.temperature, b.temperature, t),
      tint: _lerp(a.tint, b.tint, t),
      lift: _lerpVec3(a.lift, b.lift, t),
      gamma: _lerpVec3(a.gamma, b.gamma, t),
      gain: _lerpVec3(a.gain, b.gain, t),
      colorGradingLut: d.colorGradingLut,
      colorGradingLutBlend: _lerp(
        a.colorGradingLutBlend,
        b.colorGradingLutBlend,
        t,
      ),
      bloomEnabled: d.bloomEnabled,
      bloomThreshold: _lerp(a.bloomThreshold, b.bloomThreshold, t),
      bloomIntensity: _lerp(a.bloomIntensity, b.bloomIntensity, t),
      bloomScatter: _lerp(a.bloomScatter, b.bloomScatter, t),
      lensFlareEnabled: d.lensFlareEnabled,
      lensFlareIntensity: _lerp(a.lensFlareIntensity, b.lensFlareIntensity, t),
      lensFlareGhostCount: d.lensFlareGhostCount,
      lensFlareGhostSpacing: _lerp(
        a.lensFlareGhostSpacing,
        b.lensFlareGhostSpacing,
        t,
      ),
      lensFlareHaloRadius: _lerp(
        a.lensFlareHaloRadius,
        b.lensFlareHaloRadius,
        t,
      ),
      lensFlareHaloIntensity: _lerp(
        a.lensFlareHaloIntensity,
        b.lensFlareHaloIntensity,
        t,
      ),
      lensFlareChromaticAberration: _lerp(
        a.lensFlareChromaticAberration,
        b.lensFlareChromaticAberration,
        t,
      ),
      vignetteEnabled: d.vignetteEnabled,
      vignetteIntensity: _lerp(a.vignetteIntensity, b.vignetteIntensity, t),
      vignetteRadius: _lerp(a.vignetteRadius, b.vignetteRadius, t),
      vignetteSmoothness: _lerp(a.vignetteSmoothness, b.vignetteSmoothness, t),
      chromaticAberrationEnabled: d.chromaticAberrationEnabled,
      chromaticAberrationIntensity: _lerp(
        a.chromaticAberrationIntensity,
        b.chromaticAberrationIntensity,
        t,
      ),
      filmGrainEnabled: d.filmGrainEnabled,
      filmGrainIntensity: _lerp(a.filmGrainIntensity, b.filmGrainIntensity, t),
      ambientOcclusionEnabled: d.ambientOcclusionEnabled,
      ambientOcclusionRadius: _lerp(
        a.ambientOcclusionRadius,
        b.ambientOcclusionRadius,
        t,
      ),
      ambientOcclusionIntensity: _lerp(
        a.ambientOcclusionIntensity,
        b.ambientOcclusionIntensity,
        t,
      ),
      ambientOcclusionBias: _lerp(
        a.ambientOcclusionBias,
        b.ambientOcclusionBias,
        t,
      ),
      ambientOcclusionPower: _lerp(
        a.ambientOcclusionPower,
        b.ambientOcclusionPower,
        t,
      ),
      ambientOcclusionDetail: _lerp(
        a.ambientOcclusionDetail,
        b.ambientOcclusionDetail,
        t,
      ),
      ambientOcclusionHorizonAngle: _lerp(
        a.ambientOcclusionHorizonAngle,
        b.ambientOcclusionHorizonAngle,
        t,
      ),
      ambientOcclusionDirectLightAffect: _lerp(
        a.ambientOcclusionDirectLightAffect,
        b.ambientOcclusionDirectLightAffect,
        t,
      ),
      ambientOcclusionMethod: d.ambientOcclusionMethod,
      ambientOcclusionMultiBounce: _lerp(
        a.ambientOcclusionMultiBounce,
        b.ambientOcclusionMultiBounce,
        t,
      ),
      ambientOcclusionSampleCount: d.ambientOcclusionSampleCount,
      ambientOcclusionSliceCount: d.ambientOcclusionSliceCount,
      ambientOcclusionStepsPerSlice: d.ambientOcclusionStepsPerSlice,
      ambientOcclusionVisibilityBitmask: d.ambientOcclusionVisibilityBitmask,
      ambientOcclusionBentNormals: d.ambientOcclusionBentNormals,
      ambientOcclusionIndirectLight: _lerp(
        a.ambientOcclusionIndirectLight,
        b.ambientOcclusionIndirectLight,
        t,
      ),
      ambientOcclusionThickness: _lerp(
        a.ambientOcclusionThickness,
        b.ambientOcclusionThickness,
        t,
      ),
      ambientOcclusionThicknessHeuristic: _lerp(
        a.ambientOcclusionThicknessHeuristic,
        b.ambientOcclusionThicknessHeuristic,
        t,
      ),
      ambientOcclusionHalfResolution: d.ambientOcclusionHalfResolution,
      ambientOcclusionDepthMipChain: d.ambientOcclusionDepthMipChain,
      ambientOcclusionSpecularMode: d.ambientOcclusionSpecularMode,
      screenSpaceReflectionsEnabled: d.screenSpaceReflectionsEnabled,
      screenSpaceReflectionsIntensity: _lerp(
        a.screenSpaceReflectionsIntensity,
        b.screenSpaceReflectionsIntensity,
        t,
      ),
      screenSpaceReflectionsMaxDistance: _lerp(
        a.screenSpaceReflectionsMaxDistance,
        b.screenSpaceReflectionsMaxDistance,
        t,
      ),
      screenSpaceReflectionsThickness: _lerp(
        a.screenSpaceReflectionsThickness,
        b.screenSpaceReflectionsThickness,
        t,
      ),
      screenSpaceReflectionsStride: _lerp(
        a.screenSpaceReflectionsStride,
        b.screenSpaceReflectionsStride,
        t,
      ),
      screenSpaceReflectionsMaxSteps: d.screenSpaceReflectionsMaxSteps,
      screenSpaceReflectionsBlur: _lerp(
        a.screenSpaceReflectionsBlur,
        b.screenSpaceReflectionsBlur,
        t,
      ),
      screenSpaceReflectionsDistanceFadeStart: _lerp(
        a.screenSpaceReflectionsDistanceFadeStart,
        b.screenSpaceReflectionsDistanceFadeStart,
        t,
      ),
      screenSpaceReflectionsResolutionScale: _lerp(
        a.screenSpaceReflectionsResolutionScale,
        b.screenSpaceReflectionsResolutionScale,
        t,
      ),
      globalIlluminationEnabled: d.globalIlluminationEnabled,
      globalIlluminationVolumeMode: d.globalIlluminationVolumeMode,
      globalIlluminationResolution: d.globalIlluminationResolution.clone(),
      globalIlluminationExtents: d.globalIlluminationExtents.clone(),
      globalIlluminationIntensity: _lerp(
        a.globalIlluminationIntensity,
        b.globalIlluminationIntensity,
        t,
      ),
      globalIlluminationHysteresis: d.globalIlluminationHysteresis,
      globalIlluminationShadowBias: d.globalIlluminationShadowBias,
      globalIlluminationVisibility: _lerp(
        a.globalIlluminationVisibility,
        b.globalIlluminationVisibility,
        t,
      ),
      globalIlluminationVisibilityBias: d.globalIlluminationVisibilityBias,
      globalIlluminationProbeUpdateBudget:
          d.globalIlluminationProbeUpdateBudget,
      globalIlluminationInjectionResolution:
          d.globalIlluminationInjectionResolution,
      globalIlluminationFireflyClamp: d.globalIlluminationFireflyClamp,
      globalIlluminationEmissiveBoost: d.globalIlluminationEmissiveBoost,
      globalIlluminationUpdateWhenIdleOnly:
          d.globalIlluminationUpdateWhenIdleOnly,
      globalIlluminationBakeOnly: d.globalIlluminationBakeOnly,
      fogEnabled: d.fogEnabled,
      fogMode: d.fogMode,
      fogColor: _lerpVec3(a.fogColor, b.fogColor, t),
      fogSkyColorInfluence: _lerp(
        a.fogSkyColorInfluence,
        b.fogSkyColorInfluence,
        t,
      ),
      fogDensity: _lerp(a.fogDensity, b.fogDensity, t),
      fogStart: _lerp(a.fogStart, b.fogStart, t),
      fogEnd: _lerp(a.fogEnd, b.fogEnd, t),
      fogMaxOpacity: _lerp(a.fogMaxOpacity, b.fogMaxOpacity, t),
      fogCutoffDistance: _lerp(a.fogCutoffDistance, b.fogCutoffDistance, t),
      fogHeight: _lerp(a.fogHeight, b.fogHeight, t),
      fogHeightFalloff: _lerp(a.fogHeightFalloff, b.fogHeightFalloff, t),
      fogSunInScatter: _lerp(a.fogSunInScatter, b.fogSunInScatter, t),
      fogSunInScatterExponent: _lerp(
        a.fogSunInScatterExponent,
        b.fogSunInScatterExponent,
        t,
      ),
      godRaysEnabled: d.godRaysEnabled,
      godRaysIntensity: _lerp(a.godRaysIntensity, b.godRaysIntensity, t),
      godRaysDensity: _lerp(a.godRaysDensity, b.godRaysDensity, t),
      godRaysAnisotropy: _lerp(a.godRaysAnisotropy, b.godRaysAnisotropy, t),
      godRaysStepCount: d.godRaysStepCount,
      godRaysMaxDistance: _lerp(a.godRaysMaxDistance, b.godRaysMaxDistance, t),
      godRaysJitter: _lerp(a.godRaysJitter, b.godRaysJitter, t),
      godRaysColor: _lerpVec3(a.godRaysColor, b.godRaysColor, t),
      depthOfFieldEnabled: d.depthOfFieldEnabled,
      depthOfFieldFocusDistance: _lerp(
        a.depthOfFieldFocusDistance,
        b.depthOfFieldFocusDistance,
        t,
      ),
      depthOfFieldFStop: _lerp(a.depthOfFieldFStop, b.depthOfFieldFStop, t),
      depthOfFieldFocalLength: _lerp(
        a.depthOfFieldFocalLength,
        b.depthOfFieldFocalLength,
        t,
      ),
      depthOfFieldSensorHeight: _lerp(
        a.depthOfFieldSensorHeight,
        b.depthOfFieldSensorHeight,
        t,
      ),
      depthOfFieldBlurScale: _lerp(
        a.depthOfFieldBlurScale,
        b.depthOfFieldBlurScale,
        t,
      ),
      depthOfFieldMaxForegroundBlur: _lerp(
        a.depthOfFieldMaxForegroundBlur,
        b.depthOfFieldMaxForegroundBlur,
        t,
      ),
      depthOfFieldMaxBackgroundBlur: _lerp(
        a.depthOfFieldMaxBackgroundBlur,
        b.depthOfFieldMaxBackgroundBlur,
        t,
      ),
      depthOfFieldBladeCount: d.depthOfFieldBladeCount,
      depthOfFieldBladeRotation: _lerp(
        a.depthOfFieldBladeRotation,
        b.depthOfFieldBladeRotation,
        t,
      ),
      depthOfFieldBladeCurvature: _lerp(
        a.depthOfFieldBladeCurvature,
        b.depthOfFieldBladeCurvature,
        t,
      ),
      depthOfFieldQuality: d.depthOfFieldQuality,
      autoExposureEnabled: d.autoExposureEnabled,
      autoExposureStrength: _lerp(
        a.autoExposureStrength,
        b.autoExposureStrength,
        t,
      ),
      autoExposureCompensation: _lerp(
        a.autoExposureCompensation,
        b.autoExposureCompensation,
        t,
      ),
      autoExposureMinEv: _lerp(a.autoExposureMinEv, b.autoExposureMinEv, t),
      autoExposureMaxEv: _lerp(a.autoExposureMaxEv, b.autoExposureMaxEv, t),
      autoExposureSpeedUp: _lerp(
        a.autoExposureSpeedUp,
        b.autoExposureSpeedUp,
        t,
      ),
      autoExposureSpeedDown: _lerp(
        a.autoExposureSpeedDown,
        b.autoExposureSpeedDown,
        t,
      ),
    );
  }
}
