import 'dart:math' as math;

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Post-processing settings shared by every example.
///
/// The settings sidebar edits the single [exampleSettings] instance, and
/// each example copies it onto its own scene with [applyTo] right before
/// rendering, so one set of controls drives every scene.
class ExampleSettings {
  /// Color grading shared across the examples.
  final ColorGradingSettings colorGrading = ColorGradingSettings();

  /// Chromatic aberration shared across the examples.
  final ChromaticAberrationSettings chromaticAberration =
      ChromaticAberrationSettings();

  /// Vignette shared across the examples.
  final VignetteSettings vignette = VignetteSettings();

  /// Film grain shared across the examples.
  final FilmGrainSettings filmGrain = FilmGrainSettings();

  /// Bloom shared across the examples.
  final BloomSettings bloom = BloomSettings();

  /// Screen-space ambient occlusion shared across the examples.
  final AmbientOcclusionSettings ambientOcclusion = AmbientOcclusionSettings();

  /// Anti-aliasing mode shared across the examples.
  AntiAliasingMode antiAliasingMode = AntiAliasingMode.auto;

  /// Whether the shared directional light is attached to the scene.
  bool directionalLightEnabled = true;

  /// Compass angle of the directional light, in degrees, around the up axis.
  double lightAzimuthDegrees = 35.0;

  /// Height of the directional light above the horizon, in degrees. `90`
  /// points straight down.
  double lightElevationDegrees = 55.0;

  /// Directional light intensity.
  double lightIntensity = 3.0;

  /// Whether the directional light casts (cascaded) shadows.
  bool lightCastsShadow = true;

  /// World-space radius of the shadow penumbra. `0` is a hard edge.
  double shadowSoftness = 0.08;

  /// A custom, user-authored effect, built by [loadExampleEffects]. Null
  /// until the example shader bundle finishes loading.
  PostEffect? waveEffect;

  /// Amplitude of the custom wave effect.
  double waveAmplitude = 0.008;

  /// Copies the shared settings onto [scene] so its next frame uses them.
  void applyTo(Scene scene) {
    if (scene.antiAliasingMode != antiAliasingMode) {
      scene.antiAliasingMode = antiAliasingMode;
    }

    final grading = scene.postProcess.colorGrading;
    grading.enabled = colorGrading.enabled;
    grading.brightness = colorGrading.brightness;
    grading.contrast = colorGrading.contrast;
    grading.saturation = colorGrading.saturation;
    grading.temperature = colorGrading.temperature;
    grading.tint = colorGrading.tint;
    grading.lift.setFrom(colorGrading.lift);
    grading.gamma.setFrom(colorGrading.gamma);
    grading.gain.setFrom(colorGrading.gain);

    final aberration = scene.postProcess.chromaticAberration;
    aberration.enabled = chromaticAberration.enabled;
    aberration.intensity = chromaticAberration.intensity;

    final vig = scene.postProcess.vignette;
    vig.enabled = vignette.enabled;
    vig.intensity = vignette.intensity;
    vig.radius = vignette.radius;
    vig.smoothness = vignette.smoothness;

    final grain = scene.postProcess.filmGrain;
    grain.enabled = filmGrain.enabled;
    grain.intensity = filmGrain.intensity;

    final sceneBloom = scene.postProcess.bloom;
    sceneBloom.enabled = bloom.enabled;
    sceneBloom.threshold = bloom.threshold;
    sceneBloom.intensity = bloom.intensity;
    sceneBloom.scatter = bloom.scatter;

    final ao = scene.ambientOcclusion;
    ao.enabled = ambientOcclusion.enabled;
    ao.radius = ambientOcclusion.radius;
    ao.intensity = ambientOcclusion.intensity;
    ao.bias = ambientOcclusion.bias;
    ao.sampleCount = ambientOcclusion.sampleCount;
    ao.halfResolution = ambientOcclusion.halfResolution;
    ao.specularMode = ambientOcclusion.specularMode;

    if (directionalLightEnabled) {
      // Derive the travel direction from azimuth/elevation: elevation lifts
      // the light above the horizon (90 degrees points straight down).
      final azimuth = lightAzimuthDegrees * math.pi / 180.0;
      final elevation = lightElevationDegrees * math.pi / 180.0;
      final horizontal = math.cos(elevation);
      final direction = Vector3(
        horizontal * math.cos(azimuth),
        -math.sin(elevation),
        horizontal * math.sin(azimuth),
      );
      // Reuse the scene's directional light component, or attach one. The
      // light's node has no transform, so its world direction is the
      // direction set here.
      final existing = scene.root.getComponents<DirectionalLightComponent>();
      final DirectionalLightComponent component;
      if (existing.isEmpty) {
        component = DirectionalLightComponent(DirectionalLight());
        scene.root.addComponent(component);
      } else {
        component = existing.first;
      }
      final light = component.light;
      light.direction = direction;
      light.intensity = lightIntensity;
      light.castsShadow = lightCastsShadow;
      light.shadowSoftness = shadowSoftness;
    } else {
      for (final component
          in scene.root.getComponents<DirectionalLightComponent>().toList()) {
        scene.root.removeComponent(component);
      }
    }

    final wave = waveEffect;
    if (wave != null) {
      wave.setUniformBlockFromFloats('WaveInfo', [
        waveAmplitude,
        24.0,
        3.0,
        0.0,
      ]);
      if (!scene.postProcess.customEffects.contains(wave)) {
        scene.postProcess.customEffects.add(wave);
      }
    }
  }
}

/// The single shared settings instance used across the example app.
final ExampleSettings exampleSettings = ExampleSettings();

/// Loads the example shader bundle and builds the custom post-processing
/// effects. Awaited at startup alongside [Scene.initializeStaticResources].
Future<void> loadExampleEffects() async {
  final library = await gpu.loadShaderLibraryAsync(
    'build/shaderbundles/example.shaderbundle',
  );
  final waveShader = library?['WaveFragment'];
  if (waveShader != null) {
    exampleSettings.waveEffect = PostEffect(
      fragmentShader: waveShader,
      insertion: PostInsertion.beforeTonemap,
      enabled: false,
      useFrameInfo: true,
    );
  }
}
