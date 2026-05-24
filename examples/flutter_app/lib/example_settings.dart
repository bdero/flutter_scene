import 'package:flutter_scene/scene.dart';

/// Post-processing settings shared by every example.
///
/// The settings sidebar edits the single [exampleSettings] instance, and
/// each example copies it onto its own scene with [applyTo] right before
/// rendering, so one set of controls drives every scene.
class ExampleSettings {
  /// Color grading shared across the examples.
  final ColorGradingSettings colorGrading = ColorGradingSettings();

  /// Copies the shared settings onto [scene] so its next frame uses them.
  void applyTo(Scene scene) {
    final target = scene.postProcess.colorGrading;
    target.enabled = colorGrading.enabled;
    target.brightness = colorGrading.brightness;
    target.contrast = colorGrading.contrast;
    target.saturation = colorGrading.saturation;
    target.temperature = colorGrading.temperature;
    target.tint = colorGrading.tint;
    target.lift.setFrom(colorGrading.lift);
    target.gamma.setFrom(colorGrading.gamma);
    target.gain.setFrom(colorGrading.gain);
  }
}

/// The single shared settings instance used across the example app.
final ExampleSettings exampleSettings = ExampleSettings();
