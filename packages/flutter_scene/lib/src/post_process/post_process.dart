import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/post_process/post_effect.dart';

/// Built-in post-processing settings for a [Scene].
///
/// Reachable through `Scene.postProcess`. Every effect is off by default,
/// so a fresh scene does no extra post-processing work. Turn an effect on
/// and adjust its fields to change the final image.
/// {@category Rendering}
class PostProcessSettings {
  /// Color grading applied to the linear HDR scene color before tone
  /// mapping.
  final ColorGradingSettings colorGrading = ColorGradingSettings();

  /// Channel separation toward the edges, sampled before grading.
  final ChromaticAberrationSettings chromaticAberration =
      ChromaticAberrationSettings();

  /// Edge darkening applied after tone mapping.
  final VignetteSettings vignette = VignetteSettings();

  /// Animated noise applied after tone mapping.
  final FilmGrainSettings filmGrain = FilmGrainSettings();

  /// Bright areas blooming into their surroundings, added in HDR before
  /// tone mapping.
  final BloomSettings bloom = BloomSettings();

  /// User-authored custom effects, run in list order at their chosen
  /// insertion point (see [PostEffect]).
  final List<PostEffect> customEffects = [];
}

/// Color grading applied to the linear HDR scene color, before exposure
/// and tone mapping.
///
/// The defaults are neutral: with [enabled] off, or every field left at
/// its default, the image is unchanged.
/// {@category Rendering}
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

/// Splits the red and blue channels toward the edges, like a simple lens.
/// Sampled from the scene color before grading and tone mapping.
/// {@category Rendering}
class ChromaticAberrationSettings {
  /// Whether the effect runs. Off by default.
  bool enabled = false;

  /// How far the channels separate at the edges. `0` is none.
  double intensity = 0.5;
}

/// Darkens the image toward the edges, after tone mapping.
/// {@category Rendering}
class VignetteSettings {
  /// Whether the vignette runs. Off by default.
  bool enabled = false;

  /// How dark the edges become. `0` is none, `1` is fully dark.
  double intensity = 0.5;

  /// Where the darkening begins, measured from the center. Smaller values
  /// darken more of the image.
  double radius = 0.75;

  /// Softness of the falloff from clear to dark.
  double smoothness = 0.5;
}

/// Adds animated noise over the final image, after tone mapping.
/// {@category Rendering}
class FilmGrainSettings {
  /// Whether the grain runs. Off by default.
  bool enabled = false;

  /// Strength of the noise. `0` is none.
  double intensity = 0.3;
}

/// Makes bright areas bleed light into their surroundings. Computed in a
/// chain of HDR passes and added back to the scene before tone mapping.
/// {@category Rendering}
class BloomSettings {
  /// Whether bloom runs. Off by default.
  bool enabled = false;

  /// HDR brightness above which a pixel starts to bloom.
  double threshold = 1.0;

  /// How strongly the bloom is added back to the scene. `0` is none.
  double intensity = 0.5;

  /// Spread of the blur, from `0` to `1`. Higher values bloom wider.
  double scatter = 0.7;
}
