import 'package:flutter_scene/scene.dart';

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

  /// Copies the shared settings onto [scene] so its next frame uses them.
  void applyTo(Scene scene) {
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
  }
}

/// The single shared settings instance used across the example app.
final ExampleSettings exampleSettings = ExampleSettings();
