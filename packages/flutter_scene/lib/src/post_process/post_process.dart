import 'package:vector_math/vector_math.dart';

/// Built-in post-processing settings for a [Scene].
///
/// Reachable through `Scene.postProcess`. Every effect is off by default,
/// so a fresh scene does no extra post-processing work. Turn an effect on
/// and adjust its fields to change the final image.
class PostProcessSettings {
  /// Color grading applied to the linear HDR scene color before tone
  /// mapping.
  final ColorGradingSettings colorGrading = ColorGradingSettings();
}

/// Color grading applied to the linear HDR scene color, before exposure
/// and tone mapping.
///
/// The defaults are neutral: with [enabled] off, or every field left at
/// its default, the image is unchanged.
class ColorGradingSettings {
  /// Whether color grading runs. Off by default.
  bool enabled = false;

  /// Overall color multiplier. `1.0` is neutral.
  double brightness = 1.0;

  /// Contrast around mid-gray. `1.0` is neutral. Higher values raise
  /// contrast, lower values flatten it.
  double contrast = 1.0;

  /// Color saturation. `1.0` is neutral, `0.0` is grayscale, higher
  /// values are more saturated.
  double saturation = 1.0;

  /// White-balance temperature, from `-1` to `1`. Positive is warmer
  /// (more red, less blue), negative is cooler.
  double temperature = 0.0;

  /// White-balance tint, from `-1` to `1`. Positive adds green, negative
  /// adds magenta.
  double tint = 0.0;

  /// Per-channel shadow offset (lift). `(0, 0, 0)` is neutral.
  Vector3 lift = Vector3.zero();

  /// Per-channel midtone power (gamma). `(1, 1, 1)` is neutral.
  Vector3 gamma = Vector3.all(1.0);

  /// Per-channel highlight scale (gain). `(1, 1, 1)` is neutral.
  Vector3 gain = Vector3.all(1.0);
}
