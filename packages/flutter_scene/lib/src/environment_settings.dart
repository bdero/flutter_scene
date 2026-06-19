/// A snapshot of a scene's blendable look (image-based lighting, exposure,
/// tone mapping, and post-processing), captured as a copyable value that can be
/// interpolated. Drives scripted environment transitions.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/material/environment.dart';
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
  /// Creates a settings snapshot. Most callers use `Scene.environmentSettings`
  /// or [EnvironmentSettings.lerp] instead of this directly.
  EnvironmentSettings({
    this.environment,
    this.skybox,
    this.skyEnvironment,
    this.sunLight,
    this.toneMapping = ToneMappingMode.pbrNeutral,
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
    this.bloomEnabled = false,
    this.bloomThreshold = 1.0,
    this.bloomIntensity = 0.5,
    this.bloomScatter = 0.7,
    this.vignetteEnabled = false,
    this.vignetteIntensity = 0.5,
    this.vignetteRadius = 0.75,
    this.vignetteSmoothness = 0.5,
    this.chromaticAberrationEnabled = false,
    this.chromaticAberrationIntensity = 0.5,
    this.filmGrainEnabled = false,
    this.filmGrainIntensity = 0.3,
    this.ambientOcclusionEnabled = false,
    this.ambientOcclusionRadius = 0.33,
    this.ambientOcclusionIntensity = 1.22,
    this.ambientOcclusionBias = 0.07,
  }) : lift = lift ?? Vector3.zero(),
       gamma = gamma ?? Vector3.all(1.0),
       gain = gain ?? Vector3.all(1.0);

  // Image-based lighting and sky (discrete: switched, not blended).
  EnvironmentMap? environment;
  Skybox? skybox;
  SkyEnvironment? skyEnvironment;
  SunLight? sunLight;
  ToneMappingMode toneMapping;

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

  // Bloom.
  bool bloomEnabled;
  double bloomThreshold;
  double bloomIntensity;
  double bloomScatter;

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
  double ambientOcclusionRadius;
  double ambientOcclusionIntensity;
  double ambientOcclusionBias;

  /// Reads the current look of [scene] into a snapshot. The IBL/sky references
  /// are shared (not deep-copied); the scalar look is captured by value.
  factory EnvironmentSettings.fromScene(Scene scene) {
    final cg = scene.postProcess.colorGrading;
    final bloom = scene.postProcess.bloom;
    final vignette = scene.postProcess.vignette;
    final ca = scene.postProcess.chromaticAberration;
    final grain = scene.postProcess.filmGrain;
    final ao = scene.ambientOcclusion;
    return EnvironmentSettings(
      environment: scene.environment,
      skybox: scene.skybox,
      skyEnvironment: scene.skyEnvironment,
      sunLight: scene.sunLight,
      toneMapping: scene.toneMapping,
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
      bloomEnabled: bloom.enabled,
      bloomThreshold: bloom.threshold,
      bloomIntensity: bloom.intensity,
      bloomScatter: bloom.scatter,
      vignetteEnabled: vignette.enabled,
      vignetteIntensity: vignette.intensity,
      vignetteRadius: vignette.radius,
      vignetteSmoothness: vignette.smoothness,
      chromaticAberrationEnabled: ca.enabled,
      chromaticAberrationIntensity: ca.intensity,
      filmGrainEnabled: grain.enabled,
      filmGrainIntensity: grain.intensity,
      ambientOcclusionEnabled: ao.enabled,
      ambientOcclusionRadius: ao.radius,
      ambientOcclusionIntensity: ao.intensity,
      ambientOcclusionBias: ao.bias,
    );
  }

  /// Applies this snapshot to [scene], mutating its live look fields.
  void applyTo(Scene scene) {
    scene.environment = environment;
    scene.skybox = skybox;
    scene.skyEnvironment = skyEnvironment;
    scene.sunLight = sunLight;
    scene.toneMapping = toneMapping;
    scene.environmentIntensity = environmentIntensity;
    scene.exposure = exposure;

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
      ..gain.setFrom(gain);

    final bloom = scene.postProcess.bloom;
    bloom
      ..enabled = bloomEnabled
      ..threshold = bloomThreshold
      ..intensity = bloomIntensity
      ..scatter = bloomScatter;

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
      ..radius = ambientOcclusionRadius
      ..intensity = ambientOcclusionIntensity
      ..bias = ambientOcclusionBias;
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
      skybox: d.skybox,
      skyEnvironment: d.skyEnvironment,
      sunLight: d.sunLight,
      toneMapping: d.toneMapping,
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
      bloomEnabled: d.bloomEnabled,
      bloomThreshold: _lerp(a.bloomThreshold, b.bloomThreshold, t),
      bloomIntensity: _lerp(a.bloomIntensity, b.bloomIntensity, t),
      bloomScatter: _lerp(a.bloomScatter, b.bloomScatter, t),
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
    );
  }
}
