/// Realizes a document's stage render settings onto a live [Scene], and
/// serializes them back.
///
/// The stage carries the scene-wide, non-spatial settings: the image-based
/// lighting environment, environment intensity, exposure, tone mapping,
/// post-processing effects, the skybox, and sky-driven lighting.
/// `realizeScene` builds only the node graph; apply the stage to the scene
/// that hosts it with [realizeStage] (`loadScene` does this when given a
/// scene). [serializeStage] reads a scene's settings back into a document,
/// the editor-save direction.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_scene/src/post_process/color_lut.dart';
import 'package:vector_math/vector_math.dart' show Matrix3;

import 'package:flutter_scene/src/ambient_occlusion.dart';
import 'package:flutter_scene/src/depth_of_field.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/environment_settings.dart';
import 'package:flutter_scene/src/fog.dart';
import 'package:flutter_scene/src/global_illumination.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/preprocessed_sky.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_environment.dart';
import 'package:flutter_scene/src/sky_sources.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/sun_light.dart';
import 'package:flutter_scene/src/tone_mapping.dart';

/// Builds the [EnvironmentMap] for an [AssetEnvironment] from outside the asset
/// bundle (the editor loads a user-picked file from disk and prefilters it).
/// Returns null to fall back to the asset bundle. Honors the current
/// [EnvironmentMap.radianceCubeSize], set around the build by the realizer.
typedef EnvironmentAssetLoader =
    Future<EnvironmentMap?> Function(AssetRef asset);

/// Builds the live sky for an `fmat` [FmatSkySpec] from outside the asset
/// bundle (the editor compiles the referenced `.fmat` source from disk and
/// loads the bytes). Returns null to fall back to the DataAssets registry.
typedef FmatSkyLoader = Future<PreprocessedSky?> Function(AssetRef asset);

/// Resolves a [PayloadEnvironment]'s embedded image chunk to its descriptor (the
/// bytes plus `format`), so a self-contained build (which inlines an environment
/// image into a payload) realizes without an asset-bundle lookup. The realizer
/// passes the document's payload table.
typedef EnvironmentPayloadLookup = PayloadSpec? Function(LocalId payload);

/// The working width an inlined equirect environment is capped to on decode; a
/// realtime environment needs no more, and a very large panorama would
/// otherwise upload an enormous radiance source.
const int _maxEnvironmentWidth = 4096;

/// Tags applied environments with the spec they realized from, so
/// [serializeStage] can recover them. (Fmat skies recover through their
/// registry source-path stamp plus their assigned parameter values.)
final Expando<EnvironmentSpec> _environmentSpec = Expando(
  'fscene environment spec',
);

/// Applies [document]'s stage render settings to [scene], including the
/// environment look, post-processing effects, skybox, and sky lighting.
///
/// When the stage binds sky lighting (`skyEnvironment`), the binding owns
/// `Scene.environment` and the stage's environment is not applied. A skybox
/// and a sky-lighting binding whose sources describe the same sky share one
/// live source, so mutating it (or hot reloading its `.fmat`) updates both.
///
/// GPU-bound and async (an asset environment decodes its image, an fmat sky
/// loads by source path from [bundle], default the root bundle).
///
/// [environmentLoader] builds an [AssetEnvironment]'s map from outside the asset
/// bundle (the editor resolves a user-picked file from disk and builds the
/// prefiltered cube), so a disk environment is owned by the environment's own
/// realization rather than patched in afterwards. It honors the current
/// [EnvironmentMap.radianceCubeSize].
Future<void> realizeStage(
  SceneDocument document,
  Scene scene, {
  AssetBundle? bundle,
  EnvironmentAssetLoader? environmentLoader,
  FmatSkyLoader? fmatSkyLoader,
}) async {
  final stage = document.stage;
  // A self-contained build inlines environment images into payload chunks; the
  // realize resolves them from this document's payload table.
  PayloadSpec? payloadLookup(LocalId id) => document.payload(id);
  scene.antiAliasingMode = _byName(
    AntiAliasingMode.values,
    stage.antiAliasingMode,
    AntiAliasingMode.auto,
  );
  scene.renderScale = stage.renderScale;
  scene.filterQuality = _byName(
    ui.FilterQuality.values,
    stage.filterQuality,
    ui.FilterQuality.medium,
  );

  // The stage's global look is its referenced environment resource; a missing
  // or unresolved reference falls back to the studio default.
  final envRef = stage.environmentRef;
  final resource = envRef == null ? null : document.resource(envRef);
  final look = resource is EnvironmentResource ? resource : null;
  final settings = await realizeEnvironmentSettings(
    environment: look?.environment ?? const StudioEnvironment(),
    environmentIntensity: look?.environmentIntensity ?? 1.0,
    exposure: look?.exposure ?? 1.0,
    toneMapping: look?.toneMapping ?? 'pbrNeutral',
    agxWhite: look?.agxWhite ?? 16.29,
    agxContrast: look?.agxContrast ?? 1.25,
    environmentRotationY: look?.environmentRotationY ?? 0.0,
    radianceCubeSize: look?.radianceCubeSize,
    skybox: look?.skybox,
    skyEnvironment: look?.skyEnvironment,
    effects: look?.overridesEffects == true ? look!.effects : null,
    bundle: bundle,
    environmentLoader: environmentLoader,
    payloadLookup: payloadLookup,
    fmatSkyLoader: fmatSkyLoader,
  );
  if (look?.overridesEffects == true) {
    settings.applyTo(scene);
  } else {
    settings.applyLookTo(scene);
  }

  // Spatial environment-volume components blend over the stage as the global
  // base. Capture the just-applied stage look as that base so the components
  // have something to blend over; the per-frame blend is skipped when no volume
  // component is active, so the live fields are used directly in the common
  // case. The manual `Scene.environmentVolumes` list is code-driven, not carried
  // by the document, so a realize clears it.
  scene.baseEnvironment = EnvironmentSettings.fromScene(scene);
  scene.environmentVolumes.clear();
}

/// Realizes a look (the fields an [EnvironmentResource] or a volume carries)
/// into a runtime [EnvironmentSettings]: the image-based-lighting environment,
/// or a sky-lighting binding (with a sun light when it casts shadows), plus the
/// skybox and the scalar look. A skybox and sky lighting describing the same
/// sky share one live source. GPU-bound and async.
//
// TODO(env-realize-layer): this lives in stage.dart so the resource realizer
// can reuse its private build helpers; a leaf realize/environment file would be
// a cleaner home.
Future<EnvironmentSettings> realizeEnvironmentSettings({
  required EnvironmentSpec environment,
  required double environmentIntensity,
  required double exposure,
  required String toneMapping,
  double agxWhite = 16.29,
  double agxContrast = 1.25,
  double environmentRotationY = 0.0,
  int? radianceCubeSize,
  SkyboxSpec? skybox,
  SkyEnvironmentSpec? skyEnvironment,
  EnvironmentEffectsSpec? effects,
  AssetBundle? bundle,
  EnvironmentAssetLoader? environmentLoader,
  EnvironmentPayloadLookup? payloadLookup,
  FmatSkyLoader? fmatSkyLoader,
}) async {
  final settings = EnvironmentSettings(
    environmentIntensity: environmentIntensity,
    exposure: exposure,
    toneMapping: _toneMapping(toneMapping),
    agxWhite: agxWhite,
    agxContrast: agxContrast,
    environmentTransform: Matrix3.rotationY(environmentRotationY),
  );
  _applyEffectSpec(settings, effects ?? EnvironmentEffectsSpec());
  await _applyColorGradingLut(settings, effects, bundle);

  final realized = <String, SkySource?>{};
  Future<SkySource?> sourceFor(SkySourceSpec s) async =>
      realized[canonicalJson(encodeSkySource(s))] ??= await _realizeSkySource(
        s,
        bundle,
        fmatSkyLoader,
      );

  Future<void> applyEnvironment() async {
    await _withRadianceCubeSize(radianceCubeSize, () async {
      settings.environment = await _buildEnvironment(
        environment,
        bundle,
        environmentLoader,
        payloadLookup,
      );
    });
  }

  if (skyEnvironment == null) {
    await applyEnvironment();
  } else {
    final source = await sourceFor(skyEnvironment.source);
    if (source is ShaderSkySource) {
      settings.skyEnvironment = SkyEnvironment(
        source,
        refresh: _refresh(skyEnvironment.refresh),
        interval: Duration(
          microseconds: (skyEnvironment.intervalSeconds * 1e6).round(),
        ),
        faceResolution: skyEnvironment.faceResolution,
        equirectWidth: skyEnvironment.equirectWidth,
      );
      final sunSpec = skyEnvironment.sunLight;
      if (sunSpec != null && source is SunSky) {
        settings.sunLight = _realizeSunLight(source as SunSky, sunSpec);
      }
    } else {
      if (source != null) {
        debugPrint(
          'fscene: a skyEnvironment needs a shader sky (fmat, gradient, or '
          'physical); skipping the binding',
        );
      }
      await applyEnvironment();
    }
  }

  if (skybox != null) {
    final source = await sourceFor(skybox.source);
    settings.skybox = source == null
        ? null
        : Skybox(source, intensity: skybox.intensity);
  }
  return settings;
}

/// Loads the effect spec's `.cube` LUT into [settings] through [bundle],
/// reusing the live table when the reference is unchanged. A failed load
/// keeps the scene rendering without the look.
Future<void> _applyColorGradingLut(
  EnvironmentSettings settings,
  EnvironmentEffectsSpec? effects,
  AssetBundle? bundle,
) async {
  final ref = effects?.colorGradingLut;
  if (ref == null) {
    settings.colorGradingLut = null;
    return;
  }
  if (settings.colorGradingLut?.sourceAsset == ref.key) return;
  try {
    final content = await (bundle ?? rootBundle).loadString(ref.key);
    settings.colorGradingLut = tagColorLutSource(
      ColorLut.fromCubeString(content),
      ref.key,
    );
  } catch (e) {
    debugPrint(
      'flutter_scene: color grading LUT "${ref.key}" failed to load: $e',
    );
  }
}

void _applyEffectSpec(
  EnvironmentSettings settings,
  EnvironmentEffectsSpec effects,
) {
  settings
    ..colorGradingEnabled = effects.colorGradingEnabled
    ..brightness = effects.brightness
    ..contrast = effects.contrast
    ..saturation = effects.saturation
    ..temperature = effects.temperature
    ..tint = effects.tint
    ..lift.setFrom(effects.lift)
    ..gamma.setFrom(effects.gamma)
    ..gain.setFrom(effects.gain)
    // The LUT itself loads asynchronously (_applyColorGradingLut); the
    // in-place path reports not-reusable when the reference changed.
    ..colorGradingLutBlend = effects.colorGradingLutBlend
    ..bloomEnabled = effects.bloomEnabled
    ..bloomThreshold = effects.bloomThreshold
    ..bloomIntensity = effects.bloomIntensity
    ..bloomScatter = effects.bloomScatter
    ..lensFlareEnabled = effects.lensFlareEnabled
    ..lensFlareIntensity = effects.lensFlareIntensity
    ..lensFlareGhostCount = effects.lensFlareGhostCount
    ..lensFlareGhostSpacing = effects.lensFlareGhostSpacing
    ..lensFlareHaloRadius = effects.lensFlareHaloRadius
    ..lensFlareHaloIntensity = effects.lensFlareHaloIntensity
    ..lensFlareChromaticAberration = effects.lensFlareChromaticAberration
    ..vignetteEnabled = effects.vignetteEnabled
    ..vignetteIntensity = effects.vignetteIntensity
    ..vignetteRadius = effects.vignetteRadius
    ..vignetteSmoothness = effects.vignetteSmoothness
    ..chromaticAberrationEnabled = effects.chromaticAberrationEnabled
    ..chromaticAberrationIntensity = effects.chromaticAberrationIntensity
    ..filmGrainEnabled = effects.filmGrainEnabled
    ..filmGrainIntensity = effects.filmGrainIntensity
    ..ambientOcclusionEnabled = effects.ambientOcclusionEnabled
    ..ambientOcclusionMethod = _byName(
      AmbientOcclusionMethod.values,
      effects.ambientOcclusionMethod,
      AmbientOcclusionMethod.obscurance,
    )
    ..ambientOcclusionRadius = effects.ambientOcclusionRadius
    ..ambientOcclusionIntensity = effects.ambientOcclusionIntensity
    ..ambientOcclusionBias = effects.ambientOcclusionBias
    ..ambientOcclusionPower = effects.ambientOcclusionPower
    ..ambientOcclusionDetail = effects.ambientOcclusionDetail
    ..ambientOcclusionHorizonAngle = effects.ambientOcclusionHorizonAngle
    ..ambientOcclusionDirectLightAffect =
        effects.ambientOcclusionDirectLightAffect
    ..ambientOcclusionMultiBounce = effects.ambientOcclusionMultiBounce
    ..ambientOcclusionSampleCount = effects.ambientOcclusionSampleCount
    ..ambientOcclusionSliceCount = effects.ambientOcclusionSliceCount
    ..ambientOcclusionStepsPerSlice = effects.ambientOcclusionStepsPerSlice
    ..ambientOcclusionVisibilityBitmask =
        effects.ambientOcclusionVisibilityBitmask
    ..ambientOcclusionThickness = effects.ambientOcclusionThickness
    ..ambientOcclusionThicknessHeuristic =
        effects.ambientOcclusionThicknessHeuristic
    ..ambientOcclusionBentNormals = effects.ambientOcclusionBentNormals
    ..ambientOcclusionIndirectLight = effects.ambientOcclusionIndirectLight
    ..ambientOcclusionHalfResolution = effects.ambientOcclusionHalfResolution
    ..ambientOcclusionDepthMipChain = effects.ambientOcclusionDepthMipChain
    ..ambientOcclusionSpecularMode = _byName(
      SpecularAmbientOcclusionMode.values,
      effects.ambientOcclusionSpecularMode,
      SpecularAmbientOcclusionMode.none,
    )
    ..screenSpaceReflectionsEnabled = effects.screenSpaceReflectionsEnabled
    ..screenSpaceReflectionsIntensity = effects.screenSpaceReflectionsIntensity
    ..screenSpaceReflectionsMaxDistance =
        effects.screenSpaceReflectionsMaxDistance
    ..screenSpaceReflectionsThickness = effects.screenSpaceReflectionsThickness
    ..screenSpaceReflectionsStride = effects.screenSpaceReflectionsStride
    ..screenSpaceReflectionsMaxSteps = effects.screenSpaceReflectionsMaxSteps
    ..screenSpaceReflectionsBlur = effects.screenSpaceReflectionsBlur
    ..screenSpaceReflectionsDistanceFadeStart =
        effects.screenSpaceReflectionsDistanceFadeStart
    ..screenSpaceReflectionsResolutionScale =
        effects.screenSpaceReflectionsResolutionScale
    ..globalIlluminationEnabled = effects.globalIlluminationEnabled
    ..globalIlluminationVolumeMode = _byName(
      IrradianceVolumeMode.values,
      effects.globalIlluminationVolumeMode,
      IrradianceVolumeMode.followCamera,
    )
    ..globalIlluminationResolution.setFrom(effects.globalIlluminationResolution)
    ..globalIlluminationExtents.setFrom(effects.globalIlluminationExtents)
    ..globalIlluminationIntensity = effects.globalIlluminationIntensity
    ..globalIlluminationHysteresis = effects.globalIlluminationHysteresis
    ..globalIlluminationShadowBias = effects.globalIlluminationShadowBias
    ..globalIlluminationVisibility = effects.globalIlluminationVisibility
    ..globalIlluminationVisibilityBias =
        effects.globalIlluminationVisibilityBias
    ..globalIlluminationProbeUpdateBudget =
        effects.globalIlluminationProbeUpdateBudget
    ..globalIlluminationInjectionResolution = _byName(
      IrradianceInjectionResolution.values,
      effects.globalIlluminationInjectionResolution,
      IrradianceInjectionResolution.eighth,
    )
    ..globalIlluminationFireflyClamp = effects.globalIlluminationFireflyClamp
    ..globalIlluminationEmissiveBoost = effects.globalIlluminationEmissiveBoost
    ..globalIlluminationUpdateWhenIdleOnly =
        effects.globalIlluminationUpdateWhenIdleOnly
    ..globalIlluminationBakeOnly = effects.globalIlluminationBakeOnly
    ..fogEnabled = effects.fogEnabled
    ..fogMode = _byName(FogMode.values, effects.fogMode, FogMode.exponential)
    ..fogColor.setFrom(effects.fogColor)
    ..fogSkyColorInfluence = effects.fogSkyColorInfluence
    ..fogDensity = effects.fogDensity
    ..fogStart = effects.fogStart
    ..fogEnd = effects.fogEnd
    ..fogMaxOpacity = effects.fogMaxOpacity
    ..fogCutoffDistance = effects.fogCutoffDistance
    ..fogHeight = effects.fogHeight
    ..fogHeightFalloff = effects.fogHeightFalloff
    ..fogSunInScatter = effects.fogSunInScatter
    ..fogSunInScatterExponent = effects.fogSunInScatterExponent
    ..godRaysEnabled = effects.godRaysEnabled
    ..godRaysIntensity = effects.godRaysIntensity
    ..godRaysDensity = effects.godRaysDensity
    ..godRaysAnisotropy = effects.godRaysAnisotropy
    ..godRaysStepCount = effects.godRaysStepCount
    ..godRaysMaxDistance = effects.godRaysMaxDistance
    ..godRaysJitter = effects.godRaysJitter
    ..godRaysColor.setFrom(effects.godRaysColor)
    ..depthOfFieldEnabled = effects.depthOfFieldEnabled
    ..depthOfFieldFocusDistance = effects.depthOfFieldFocusDistance
    ..depthOfFieldFStop = effects.depthOfFieldFStop
    ..depthOfFieldFocalLength = effects.depthOfFieldFocalLength
    ..depthOfFieldSensorHeight = effects.depthOfFieldSensorHeight
    ..depthOfFieldBlurScale = effects.depthOfFieldBlurScale
    ..depthOfFieldMaxForegroundBlur = effects.depthOfFieldMaxForegroundBlur
    ..depthOfFieldMaxBackgroundBlur = effects.depthOfFieldMaxBackgroundBlur
    ..depthOfFieldBladeCount = effects.depthOfFieldBladeCount
    ..depthOfFieldBladeRotation = effects.depthOfFieldBladeRotation
    ..depthOfFieldBladeCurvature = effects.depthOfFieldBladeCurvature
    ..depthOfFieldQuality = _byName(
      DepthOfFieldQuality.values,
      effects.depthOfFieldQuality,
      DepthOfFieldQuality.medium,
    )
    ..autoExposureEnabled = effects.autoExposureEnabled
    ..autoExposureStrength = effects.autoExposureStrength
    ..autoExposureCompensation = effects.autoExposureCompensation
    ..autoExposureMinEv = effects.autoExposureMinEv
    ..autoExposureMaxEv = effects.autoExposureMaxEv
    ..autoExposureSpeedUp = effects.autoExposureSpeedUp
    ..autoExposureSpeedDown = effects.autoExposureSpeedDown;
}

/// Re-applies a resource look onto live [target] settings in place, reusing the
/// live sky bindings and the static environment (so their baked image-based
/// lighting is kept and re-bakes smoothly instead of from zero) when the look's
/// structure is unchanged. Returns true when the look was applied in place, and
/// false when a structural change (a different sky source type or sky-binding
/// configuration, or a different environment kind) means the caller must
/// rebuild the settings from scratch with [realizeEnvironmentSettings].
///
/// A parameter-only edit (a dragged sun direction, a recolored sky, a scalar)
/// keeps the existing [SkyEnvironment] binding and only mutates its source and
/// invalidates it, so the time-sliced re-bake holds the current lighting until
/// the new one publishes. This mirrors what the editor's live preview does
/// during a drag, so committing the edit is then a near no-op.
bool reapplyEnvironmentSettingsInPlace({
  required EnvironmentSettings target,
  required EnvironmentSpec environment,
  required double environmentIntensity,
  required double exposure,
  required String toneMapping,
  required double agxWhite,
  required double agxContrast,
  required double environmentRotationY,
  required EnvironmentEffectsSpec? effects,
  SkyboxSpec? skybox,
  SkyEnvironmentSpec? skyEnvironment,
}) {
  if (!_skyEnvironmentReusable(target.skyEnvironment, skyEnvironment)) {
    return false;
  }
  if (!_skyboxReusable(target.skybox, skybox)) return false;
  // A changed LUT reference needs an asynchronous load; only scalar edits
  // (blend included) reuse the live settings.
  if (effects != null &&
      effects.colorGradingLut?.key != target.colorGradingLut?.sourceAsset) {
    return false;
  }
  // The static environment is only live when no sky binding owns it.
  if (skyEnvironment == null &&
      !_environmentReusable(target.environment, environment)) {
    return false;
  }

  target
    ..environmentIntensity = environmentIntensity
    ..exposure = exposure
    ..toneMapping = _toneMapping(toneMapping)
    ..agxWhite = agxWhite
    ..agxContrast = agxContrast
    ..environmentTransform = Matrix3.rotationY(environmentRotationY);
  if (effects != null) _applyEffectSpec(target, effects);

  final liveSkyEnvironment = target.skyEnvironment;
  if (liveSkyEnvironment != null && skyEnvironment != null) {
    _applySkySourceInPlace(liveSkyEnvironment.source, skyEnvironment.source);
    liveSkyEnvironment.invalidate();
    final source = liveSkyEnvironment.source;
    final sunSpec = skyEnvironment.sunLight;
    final wantsSun = sunSpec != null && source is SunSky;
    final hasSun = identical(target.sunLight?.source, source);
    if (wantsSun && !hasSun) {
      target.sunLight = _realizeSunLight(source as SunSky, sunSpec);
    } else if (wantsSun) {
      _applySunLightSpec(target.sunLight!, sunSpec);
    } else if (!wantsSun && target.sunLight != null) {
      target.sunLight = null;
    }
  }

  final liveSkybox = target.skybox;
  if (liveSkybox != null && skybox != null) {
    _applySkySourceInPlace(liveSkybox.source, skybox.source);
    liveSkybox.intensity = skybox.intensity;
  }
  return true;
}

// Whether the [live] sky binding can be reused for [spec] without a rebuild,
// needing the same presence, source type, and bake configuration (the binding
// config is fixed at construction, so a change there needs a fresh binding).
bool _skyEnvironmentReusable(SkyEnvironment? live, SkyEnvironmentSpec? spec) {
  if (live == null || spec == null) return live == null && spec == null;
  if (!_skySourceTypeMatches(live.source, spec.source)) return false;
  return live.refresh == _refresh(spec.refresh) &&
      live.interval.inMicroseconds == (spec.intervalSeconds * 1e6).round() &&
      live.faceResolution == spec.faceResolution &&
      live.equirectWidth == spec.equirectWidth;
}

// Whether the [live] skybox can be reused for [spec], needing the same presence
// and source type. The intensity and source parameters are mutated in place.
bool _skyboxReusable(Skybox? live, SkyboxSpec? spec) {
  if (live == null || spec == null) return live == null && spec == null;
  return _skySourceTypeMatches(live.source, spec.source);
}

// Whether [live] is a static environment this realizer built from a spec equal
// to [spec], so it can be kept rather than rebuilt. A null or externally built
// environment (no spec stamp, such as a disk-loaded HDR) is not reusable here,
// so the caller falls back to a rebuild.
//
// TODO(radiance-size-reapply): a radianceCubeSize-only change is not detected
// (the live map does not expose its built size), so it is ignored on reuse.
bool _environmentReusable(EnvironmentMap? live, EnvironmentSpec spec) {
  if (live == null) return false;
  final current = _environmentSpec[live];
  if (current == null) return false;
  return canonicalJson(_encodeEnvironment(current)) ==
      canonicalJson(_encodeEnvironment(spec));
}

bool _skySourceTypeMatches(SkySource live, SkySourceSpec spec) =>
    switch (spec) {
      EnvironmentSkySpec() => live is EnvironmentSkySource,
      GradientSkySpec() => live is GradientSkySource,
      PhysicalSkySpec() => live is PhysicalSkySource,
      WeatherSkySpec() => live is WeatherSkySource,
      FmatSkySpec(:final asset) =>
        live is PreprocessedSky && fmatSourcePathOf(live) == asset.key,
    };

// Mutates [live]'s parameters from [spec] without replacing the source object,
// so a bound SkyEnvironment keeps its baked state and only needs invalidation.
// A type mismatch is a no-op (the reusability checks above gate this).
void _applySkySourceInPlace(SkySource live, SkySourceSpec spec) {
  switch (spec) {
    case EnvironmentSkySpec(:final blurriness):
      if (live is EnvironmentSkySource) live.blurriness = blurriness;
    case GradientSkySpec s:
      if (live is GradientSkySource) {
        live.zenithColor.setFrom(s.zenithColor);
        live.horizonColor.setFrom(s.horizonColor);
        live.groundColor.setFrom(s.groundColor);
        live.sunDirection.setFrom(s.sunDirection);
        live.sunColor.setFrom(s.sunColor);
        live.sunSharpness = s.sunSharpness;
      }
    case PhysicalSkySpec s:
      if (live is PhysicalSkySource) {
        live.sunDirection.setFrom(s.sunDirection);
        live.sunAngularRadius = s.sunAngularRadius;
        live.rayleighCoefficient = s.rayleighCoefficient;
        live.rayleighColor.setFrom(s.rayleighColor);
        live.mieCoefficient = s.mieCoefficient;
        live.mieEccentricity = s.mieEccentricity;
        live.mieColor.setFrom(s.mieColor);
        live.turbidity = s.turbidity;
        live.groundColor.setFrom(s.groundColor);
        live.energy = s.energy;
      }
    case WeatherSkySpec s:
      if (live is WeatherSkySource) {
        live.sunDirection.setFrom(s.sunDirection);
        live.sunAngularRadius = s.sunAngularRadius;
        live.rayleighCoefficient = s.rayleighCoefficient;
        live.rayleighColor.setFrom(s.rayleighColor);
        live.mieCoefficient = s.mieCoefficient;
        live.mieEccentricity = s.mieEccentricity;
        live.mieColor.setFrom(s.mieColor);
        live.turbidity = s.turbidity;
        live.groundColor.setFrom(s.groundColor);
        live.energy = s.energy;
        live.coverage = s.coverage;
        live.density = s.density;
        live.altitude = s.altitude;
        live.detail = s.detail;
        live.softness = s.softness;
        live.seed = s.seed;
        live.wind.setFrom(s.wind);
        live.cloudColor.setFrom(s.cloudColor);
        live.cloudShading = s.cloudShading;
        // The flash and the drift are runtime state a driver owns, not
        // authored values: reapplying the spec must not blank a strike or
        // rewind the sky mid-storm.
        live.stormDarkening = s.stormDarkening;
      }
    case FmatSkySpec s:
      if (live is PreprocessedSky) {
        applyFmatParameterOverrides(live.parameters, s.properties);
      }
  }
}

/// Runs [build] with [EnvironmentMap.radianceCubeSize] set to [size],
/// restoring it afterward. A null [size] keeps the current default.
//
// TODO(radiance-size-instance): radianceCubeSize is a static, so per-environment
// sizing relies on setting it around each (sequential) build. Promote it to a
// constructor argument on EnvironmentMap so it is genuinely per-instance.
Future<void> _withRadianceCubeSize(
  int? size,
  Future<void> Function() build,
) async {
  if (size == null) {
    await build();
    return;
  }
  final previous = EnvironmentMap.radianceCubeSize;
  EnvironmentMap.radianceCubeSize = size;
  try {
    await build();
  } finally {
    EnvironmentMap.radianceCubeSize = previous;
  }
}

/// Reads [scene]'s stage render settings back into [document], writing the look
/// into the stage's environment resource (creating and linking one when the
/// stage has none).
///
/// The reverse of [realizeStage]. An environment the realizer produced
/// recovers its source spec, and an fmat sky loaded through `loadFmatSky`
/// recovers its source path plus every parameter assigned through its typed
/// setters; a hand-built [EnvironmentMap] serializes as the studio default
/// and a custom [ShaderSkySource] is dropped, each with a warning.
void serializeStage(Scene scene, SceneDocument document) {
  final stage = document.stage;
  stage.antiAliasingMode = scene.antiAliasingMode.name;
  stage.renderScale = scene.renderScale;
  stage.filterQuality = scene.filterQuality.name;

  final resource = _ensureStageEnvironment(document);
  resource.environmentIntensity = scene.environmentIntensity;
  resource.exposure = scene.exposure;
  resource.toneMapping = scene.toneMapping.name;
  resource.agxWhite = scene.agxWhite;
  resource.agxContrast = scene.agxContrast;
  final transform = scene.environmentTransform.storage;
  // TODO(environment-transform): store a full orientation in the document so
  // serialization does not discard rotations outside world Y.
  resource.environmentRotationY = math.atan2(transform[6], transform[0]);
  resource.effects = _effectSpecFromSettings(
    EnvironmentSettings.fromScene(scene),
  );
  resource.overridesEffects = true;

  final skyEnvironment = scene.skyEnvironment;
  if (skyEnvironment == null) {
    resource.skyEnvironment = null;
    final environment = scene.environment;
    var spec = environment == null ? null : _environmentSpec[environment];
    if (spec == null && environment != null) {
      // An environment the app loaded itself still recovers when it carries
      // its asset-path stamp (EnvironmentMap.fromEquirectImageAsset).
      final assetPath = environmentAssetPathOf(environment);
      if (assetPath != null) spec = AssetEnvironment(AssetRef(assetPath));
    }
    if (spec != null) {
      resource.environment = spec;
    } else {
      if (environment != null) {
        debugPrint(
          'fscene: the scene environment was not produced by realizeStage '
          'or EnvironmentMap.fromEquirectImageAsset and cannot be recovered; '
          'serializing the studio default',
        );
      }
      resource.environment = const StudioEnvironment();
    }
  } else {
    final source = _serializeSkySource(skyEnvironment.source);
    // Only serialize a sun driven by this sky source.
    final skySun = identical(scene.sunLight?.source, skyEnvironment.source)
        ? scene.sunLight
        : null;
    resource.skyEnvironment = source == null
        ? null
        : SkyEnvironmentSpec(
            source,
            refresh: skyEnvironment.refresh.name,
            intervalSeconds: skyEnvironment.interval.inMicroseconds / 1e6,
            faceResolution: skyEnvironment.faceResolution,
            equirectWidth: skyEnvironment.equirectWidth,
            sunLight: skySun == null ? null : _serializeSunLight(skySun),
          );
  }

  final skybox = scene.skybox;
  if (skybox == null) {
    resource.skybox = null;
  } else {
    final source = _serializeSkySource(skybox.source);
    resource.skybox = source == null
        ? null
        : SkyboxSpec(source, intensity: skybox.intensity);
  }
}

EnvironmentEffectsSpec _effectSpecFromSettings(
  EnvironmentSettings s,
) => EnvironmentEffectsSpec(
  colorGradingEnabled: s.colorGradingEnabled,
  brightness: s.brightness,
  contrast: s.contrast,
  saturation: s.saturation,
  temperature: s.temperature,
  tint: s.tint,
  lift: s.lift.clone(),
  gamma: s.gamma.clone(),
  gain: s.gain.clone(),
  // A LUT built from a string has no asset to reference; the look stays
  // live but does not persist.
  colorGradingLut: s.colorGradingLut?.sourceAsset == null
      ? null
      : AssetRef(s.colorGradingLut!.sourceAsset!),
  colorGradingLutBlend: s.colorGradingLutBlend,
  bloomEnabled: s.bloomEnabled,
  bloomThreshold: s.bloomThreshold,
  bloomIntensity: s.bloomIntensity,
  bloomScatter: s.bloomScatter,
  lensFlareEnabled: s.lensFlareEnabled,
  lensFlareIntensity: s.lensFlareIntensity,
  lensFlareGhostCount: s.lensFlareGhostCount,
  lensFlareGhostSpacing: s.lensFlareGhostSpacing,
  lensFlareHaloRadius: s.lensFlareHaloRadius,
  lensFlareHaloIntensity: s.lensFlareHaloIntensity,
  lensFlareChromaticAberration: s.lensFlareChromaticAberration,
  vignetteEnabled: s.vignetteEnabled,
  vignetteIntensity: s.vignetteIntensity,
  vignetteRadius: s.vignetteRadius,
  vignetteSmoothness: s.vignetteSmoothness,
  chromaticAberrationEnabled: s.chromaticAberrationEnabled,
  chromaticAberrationIntensity: s.chromaticAberrationIntensity,
  filmGrainEnabled: s.filmGrainEnabled,
  filmGrainIntensity: s.filmGrainIntensity,
  ambientOcclusionEnabled: s.ambientOcclusionEnabled,
  ambientOcclusionMethod: s.ambientOcclusionMethod.name,
  ambientOcclusionRadius: s.ambientOcclusionRadius,
  ambientOcclusionIntensity: s.ambientOcclusionIntensity,
  ambientOcclusionBias: s.ambientOcclusionBias,
  ambientOcclusionPower: s.ambientOcclusionPower,
  ambientOcclusionDetail: s.ambientOcclusionDetail,
  ambientOcclusionHorizonAngle: s.ambientOcclusionHorizonAngle,
  ambientOcclusionDirectLightAffect: s.ambientOcclusionDirectLightAffect,
  ambientOcclusionMultiBounce: s.ambientOcclusionMultiBounce,
  ambientOcclusionSampleCount: s.ambientOcclusionSampleCount,
  ambientOcclusionSliceCount: s.ambientOcclusionSliceCount,
  ambientOcclusionStepsPerSlice: s.ambientOcclusionStepsPerSlice,
  ambientOcclusionVisibilityBitmask: s.ambientOcclusionVisibilityBitmask,
  ambientOcclusionThickness: s.ambientOcclusionThickness,
  ambientOcclusionThicknessHeuristic: s.ambientOcclusionThicknessHeuristic,
  ambientOcclusionBentNormals: s.ambientOcclusionBentNormals,
  ambientOcclusionIndirectLight: s.ambientOcclusionIndirectLight,
  ambientOcclusionHalfResolution: s.ambientOcclusionHalfResolution,
  ambientOcclusionDepthMipChain: s.ambientOcclusionDepthMipChain,
  ambientOcclusionSpecularMode: s.ambientOcclusionSpecularMode.name,
  screenSpaceReflectionsEnabled: s.screenSpaceReflectionsEnabled,
  screenSpaceReflectionsIntensity: s.screenSpaceReflectionsIntensity,
  screenSpaceReflectionsMaxDistance: s.screenSpaceReflectionsMaxDistance,
  screenSpaceReflectionsThickness: s.screenSpaceReflectionsThickness,
  screenSpaceReflectionsStride: s.screenSpaceReflectionsStride,
  screenSpaceReflectionsMaxSteps: s.screenSpaceReflectionsMaxSteps,
  screenSpaceReflectionsBlur: s.screenSpaceReflectionsBlur,
  screenSpaceReflectionsDistanceFadeStart:
      s.screenSpaceReflectionsDistanceFadeStart,
  screenSpaceReflectionsResolutionScale:
      s.screenSpaceReflectionsResolutionScale,
  globalIlluminationEnabled: s.globalIlluminationEnabled,
  globalIlluminationVolumeMode: s.globalIlluminationVolumeMode.name,
  globalIlluminationResolution: s.globalIlluminationResolution.clone(),
  globalIlluminationExtents: s.globalIlluminationExtents.clone(),
  globalIlluminationIntensity: s.globalIlluminationIntensity,
  globalIlluminationHysteresis: s.globalIlluminationHysteresis,
  globalIlluminationShadowBias: s.globalIlluminationShadowBias,
  globalIlluminationVisibility: s.globalIlluminationVisibility,
  globalIlluminationVisibilityBias: s.globalIlluminationVisibilityBias,
  globalIlluminationProbeUpdateBudget: s.globalIlluminationProbeUpdateBudget,
  globalIlluminationInjectionResolution:
      s.globalIlluminationInjectionResolution.name,
  globalIlluminationFireflyClamp: s.globalIlluminationFireflyClamp,
  globalIlluminationEmissiveBoost: s.globalIlluminationEmissiveBoost,
  globalIlluminationUpdateWhenIdleOnly: s.globalIlluminationUpdateWhenIdleOnly,
  globalIlluminationBakeOnly: s.globalIlluminationBakeOnly,
  fogEnabled: s.fogEnabled,
  fogMode: s.fogMode.name,
  fogColor: s.fogColor.clone(),
  fogSkyColorInfluence: s.fogSkyColorInfluence,
  fogDensity: s.fogDensity,
  fogStart: s.fogStart,
  fogEnd: s.fogEnd,
  fogMaxOpacity: s.fogMaxOpacity,
  fogCutoffDistance: s.fogCutoffDistance,
  fogHeight: s.fogHeight,
  fogHeightFalloff: s.fogHeightFalloff,
  fogSunInScatter: s.fogSunInScatter,
  fogSunInScatterExponent: s.fogSunInScatterExponent,
  godRaysEnabled: s.godRaysEnabled,
  godRaysIntensity: s.godRaysIntensity,
  godRaysDensity: s.godRaysDensity,
  godRaysAnisotropy: s.godRaysAnisotropy,
  godRaysStepCount: s.godRaysStepCount,
  godRaysMaxDistance: s.godRaysMaxDistance,
  godRaysJitter: s.godRaysJitter,
  godRaysColor: s.godRaysColor.clone(),
  depthOfFieldEnabled: s.depthOfFieldEnabled,
  depthOfFieldFocusDistance: s.depthOfFieldFocusDistance,
  depthOfFieldFStop: s.depthOfFieldFStop,
  depthOfFieldFocalLength: s.depthOfFieldFocalLength,
  depthOfFieldSensorHeight: s.depthOfFieldSensorHeight,
  depthOfFieldBlurScale: s.depthOfFieldBlurScale,
  depthOfFieldMaxForegroundBlur: s.depthOfFieldMaxForegroundBlur,
  depthOfFieldMaxBackgroundBlur: s.depthOfFieldMaxBackgroundBlur,
  depthOfFieldBladeCount: s.depthOfFieldBladeCount,
  depthOfFieldBladeRotation: s.depthOfFieldBladeRotation,
  depthOfFieldBladeCurvature: s.depthOfFieldBladeCurvature,
  depthOfFieldQuality: s.depthOfFieldQuality.name,
  autoExposureEnabled: s.autoExposureEnabled,
  autoExposureStrength: s.autoExposureStrength,
  autoExposureCompensation: s.autoExposureCompensation,
  autoExposureMinEv: s.autoExposureMinEv,
  autoExposureMaxEv: s.autoExposureMaxEv,
  autoExposureSpeedUp: s.autoExposureSpeedUp,
  autoExposureSpeedDown: s.autoExposureSpeedDown,
);

/// The stage's global environment resource, creating and linking a studio
/// default when the stage references none, so the look always has a resource
/// home (the format carries no inline stage look).
EnvironmentResource _ensureStageEnvironment(SceneDocument document) {
  final ref = document.stage.environmentRef;
  final existing = ref == null ? null : document.resource(ref);
  if (existing is EnvironmentResource) return existing;
  final resource = document.addResource(
    EnvironmentResource(document.newId(), name: 'Environment'),
  );
  document.stage.environmentRef = resource.id;
  return resource;
}

/// Builds the [EnvironmentMap] for [spec], stamping it so [serializeStage] can
/// recover the spec, or null when an asset fails to load. Honors the current
/// [EnvironmentMap.radianceCubeSize].
///
/// An [AssetEnvironment] is built through [environmentLoader] first (the editor
/// loads a user-picked file from disk and prefilters it), falling back to the
/// asset bundle when there is no loader or it declines. This keeps the disk
/// environment's whole lifecycle (decode plus prefilter cube) inside the
/// environment's own realization.
Future<EnvironmentMap?> _buildEnvironment(
  EnvironmentSpec spec,
  AssetBundle? bundle,
  EnvironmentAssetLoader? environmentLoader,
  EnvironmentPayloadLookup? payloadLookup,
) async {
  final EnvironmentMap environment;
  switch (spec) {
    case StudioEnvironment():
      environment = EnvironmentMap.studio();
    case EmptyEnvironment():
      environment = EnvironmentMap.empty();
    case ConstantEnvironment(:final color):
      environment = EnvironmentMap.constantDiffuse(color);
    case PayloadEnvironment(:final payload):
      final chunk = payloadLookup?.call(payload);
      final bytes = chunk?.bytes;
      if (bytes == null) {
        debugPrint(
          'fscene: environment payload $payload has no bytes; load the '
          'document from a .fsceneb container so its chunks are attached',
        );
        return null;
      }
      try {
        // The bytes are self-describing (magic-number detection), so the
        // payload's format tag is informational only. Decodes HDR and EXR off
        // the platform thread.
        environment = await EnvironmentMap.fromEquirectImageBytes(
          bytes: bytes,
          maxWidth: _maxEnvironmentWidth,
        );
      } catch (e) {
        debugPrint('fscene: failed to decode environment payload $payload: $e');
        return null;
      }
    case AssetEnvironment(:final asset):
      final loaded = environmentLoader == null
          ? null
          : await environmentLoader(asset);
      if (loaded != null) {
        environment = loaded;
      } else {
        try {
          // Detects Radiance HDR, OpenEXR, or a standard sRGB image from the
          // asset bytes, so a document referencing a `.hdr`/`.exr` asset keeps
          // its dynamic range without build-hook inlining.
          environment = await EnvironmentMap.fromEquirectImageAsset(
            assetPath: asset.key,
            maxWidth: _maxEnvironmentWidth,
            bundle: bundle,
          );
        } catch (e) {
          debugPrint(
            'fscene: failed to load environment asset "${asset.key}": $e',
          );
          return null;
        }
      }
  }
  _environmentSpec[environment] = spec;
  return environment;
}

// EnvironmentSpec has no public encoder; mirror the stage codec's shape just
// for equality checks.
Map<String, Object> _encodeEnvironment(EnvironmentSpec spec) => switch (spec) {
  StudioEnvironment() => {'type': 'studio'},
  AssetEnvironment(:final asset) => {'type': 'asset', 'ref': asset.key},
  PayloadEnvironment(:final payload) => {
    'type': 'payload',
    'payload': payload.toToken(),
  },
  ConstantEnvironment(:final color) => {
    'type': 'constant',
    'color': [color.x, color.y, color.z],
  },
  EmptyEnvironment() => {'type': 'empty'},
};

Future<SkySource?> _realizeSkySource(
  SkySourceSpec spec,
  AssetBundle? bundle,
  FmatSkyLoader? fmatSkyLoader,
) async {
  switch (spec) {
    case EnvironmentSkySpec(:final blurriness):
      return EnvironmentSkySource(blurriness: blurriness);
    case GradientSkySpec s:
      return GradientSkySource(
        zenithColor: s.zenithColor.clone(),
        horizonColor: s.horizonColor.clone(),
        groundColor: s.groundColor.clone(),
        sunDirection: s.sunDirection.clone(),
        sunColor: s.sunColor.clone(),
        sunSharpness: s.sunSharpness,
      );
    case PhysicalSkySpec s:
      return PhysicalSkySource(
        sunDirection: s.sunDirection.clone(),
        sunAngularRadius: s.sunAngularRadius,
        rayleighCoefficient: s.rayleighCoefficient,
        rayleighColor: s.rayleighColor.clone(),
        mieCoefficient: s.mieCoefficient,
        mieEccentricity: s.mieEccentricity,
        mieColor: s.mieColor.clone(),
        turbidity: s.turbidity,
        groundColor: s.groundColor.clone(),
        energy: s.energy,
      );
    case WeatherSkySpec s:
      return WeatherSkySource(
        sunDirection: s.sunDirection.clone(),
        sunAngularRadius: s.sunAngularRadius,
        rayleighCoefficient: s.rayleighCoefficient,
        rayleighColor: s.rayleighColor.clone(),
        mieCoefficient: s.mieCoefficient,
        mieEccentricity: s.mieEccentricity,
        mieColor: s.mieColor.clone(),
        turbidity: s.turbidity,
        groundColor: s.groundColor.clone(),
        energy: s.energy,
        coverage: s.coverage,
        density: s.density,
        altitude: s.altitude,
        detail: s.detail,
        softness: s.softness,
        seed: s.seed,
        wind: s.wind.clone(),
        cloudColor: s.cloudColor.clone(),
        cloudShading: s.cloudShading,
        stormDarkening: s.stormDarkening,
      );
    case FmatSkySpec s:
      try {
        // Prefer the disk loader (the editor compiles the source on demand);
        // fall back to the DataAssets registry for in-bundle skies.
        final sky =
            await fmatSkyLoader?.call(s.asset) ??
            await loadFmatSky(s.asset.key, bundle: bundle);
        applyFmatParameterOverrides(sky.parameters, s.properties);
        return sky;
      } catch (e) {
        debugPrint('fscene: failed to load sky fmat "${s.asset.key}": $e');
        return null;
      }
  }
}

SkySourceSpec? _serializeSkySource(SkySource source) {
  // PreprocessedSky and the built-in sources all extend ShaderSkySource;
  // match the concrete types before the generic fallthrough.
  if (source is PreprocessedSky) {
    final sourcePath = fmatSourcePathOf(source);
    if (sourcePath == null) {
      debugPrint(
        'fscene: a sky fmat with no known source path cannot be serialized; '
        'load skies with loadFmatSky',
      );
      return null;
    }
    // Assigned parameter values (overrides applied at realization plus any
    // the app set since) round-trip; texture parameters have no stage-level
    // resource pool to reference and are skipped with a warning.
    return FmatSkySpec(
      AssetRef(sourcePath),
      properties: serializeFmatParameterOverrides(
        source.parameters.assignedValues,
      ),
    );
  }
  if (source is GradientSkySource) {
    return GradientSkySpec(
      zenithColor: source.zenithColor.clone(),
      horizonColor: source.horizonColor.clone(),
      groundColor: source.groundColor.clone(),
      sunDirection: source.sunDirection.clone(),
      sunColor: source.sunColor.clone(),
      sunSharpness: source.sunSharpness,
    );
  }
  // Checked before PhysicalSkySource only in the sense that neither extends
  // the other; both are ShaderSkySource siblings.
  if (source is WeatherSkySource) {
    return WeatherSkySpec(
      sunDirection: source.sunDirection.clone(),
      sunAngularRadius: source.sunAngularRadius,
      rayleighCoefficient: source.rayleighCoefficient,
      rayleighColor: source.rayleighColor.clone(),
      mieCoefficient: source.mieCoefficient,
      mieEccentricity: source.mieEccentricity,
      mieColor: source.mieColor.clone(),
      turbidity: source.turbidity,
      groundColor: source.groundColor.clone(),
      energy: source.energy,
      coverage: source.coverage,
      density: source.density,
      altitude: source.altitude,
      detail: source.detail,
      softness: source.softness,
      seed: source.seed,
      wind: source.wind.clone(),
      cloudColor: source.cloudColor.clone(),
      cloudShading: source.cloudShading,
      // The flash is transient: a scene saved mid-strike must not reopen
      // with a white sky frozen on it.
      stormDarkening: source.stormDarkening,
    );
  }
  if (source is PhysicalSkySource) {
    return PhysicalSkySpec(
      sunDirection: source.sunDirection.clone(),
      sunAngularRadius: source.sunAngularRadius,
      rayleighCoefficient: source.rayleighCoefficient,
      rayleighColor: source.rayleighColor.clone(),
      mieCoefficient: source.mieCoefficient,
      mieEccentricity: source.mieEccentricity,
      mieColor: source.mieColor.clone(),
      turbidity: source.turbidity,
      groundColor: source.groundColor.clone(),
      energy: source.energy,
    );
  }
  if (source is EnvironmentSkySource) {
    return EnvironmentSkySpec(blurriness: source.blurriness);
  }
  debugPrint(
    'fscene: a custom ShaderSkySource is not serializable; use a .fmat sky '
    '(loadFmatSky) or a built-in source',
  );
  return null;
}

SunLight _realizeSunLight(SunSky source, SunLightSpec spec) {
  final sun = SunLight(source);
  _applySunLightSpec(sun, spec);
  return sun;
}

void _applySunLightSpec(SunLight sun, SunLightSpec spec) {
  sun
    ..castsShadow = spec.castsShadow
    ..intensityScale = spec.intensityScale
    ..priority = spec.priority
    ..cacheStaticShadows = spec.cacheStaticShadows
    ..shadowSoftness = spec.shadowSoftness
    ..shadowMaxDistance = spec.shadowMaxDistance
    ..shadowCascadeCount = spec.shadowCascadeCount
    ..shadowMapResolution = spec.shadowMapResolution
    ..shadowDepthBias = spec.shadowDepthBias
    ..shadowNormalBias = spec.shadowNormalBias
    ..shadowFadeRange = spec.shadowFadeRange
    ..shadowCascadeSplitLambda = spec.shadowCascadeSplitLambda
    ..shadowAmbientStrength = spec.shadowAmbientStrength
    ..contactShadows = spec.contactShadows
    ..contactShadowDistance = spec.contactShadowDistance
    ..angularRadius = spec.angularRadius
    ..shadowFilter = _byName(
      DirectionalShadowFilter.values,
      spec.shadowFilter,
      DirectionalShadowFilter.rotatedPoisson,
    )
    ..shadowCasterFaces = _byName(
      ShadowCasterFaces.values,
      spec.shadowCasterFaces,
      ShadowCasterFaces.front,
    );
}

SunLightSpec _serializeSunLight(SunLight sun) => SunLightSpec(
  castsShadow: sun.castsShadow,
  intensityScale: sun.intensityScale,
  priority: sun.priority,
  cacheStaticShadows: sun.cacheStaticShadows,
  shadowSoftness: sun.shadowSoftness,
  shadowMaxDistance: sun.shadowMaxDistance,
  shadowCascadeCount: sun.shadowCascadeCount,
  shadowMapResolution: sun.shadowMapResolution,
  shadowDepthBias: sun.shadowDepthBias,
  shadowNormalBias: sun.shadowNormalBias,
  shadowFadeRange: sun.shadowFadeRange,
  shadowCascadeSplitLambda: sun.shadowCascadeSplitLambda,
  shadowAmbientStrength: sun.shadowAmbientStrength,
  shadowFilter: sun.shadowFilter.name,
  contactShadows: sun.contactShadows,
  contactShadowDistance: sun.contactShadowDistance,
  angularRadius: sun.angularRadius,
  shadowCasterFaces: sun.shadowCasterFaces.name,
);

ToneMappingMode _toneMapping(String name) {
  try {
    return ToneMappingMode.values.byName(name);
  } catch (_) {
    debugPrint('fscene: unknown tone mapping "$name"; using pbrNeutral');
    return ToneMappingMode.pbrNeutral;
  }
}

T _byName<T extends Enum>(List<T> values, String name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  debugPrint('fscene: unknown $T "$name"; using ${fallback.name}');
  return fallback;
}

SkyEnvironmentRefresh _refresh(String name) {
  try {
    return SkyEnvironmentRefresh.values.byName(name);
  } catch (_) {
    debugPrint('fscene: unknown sky refresh policy "$name"; using manual');
    return SkyEnvironmentRefresh.manual;
  }
}
