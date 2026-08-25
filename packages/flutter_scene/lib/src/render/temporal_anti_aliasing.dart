import 'package:vector_math/vector_math.dart';

/// Temporal anti-aliasing settings for a [Scene]. Active when
/// [Scene.antiAliasingMode] is [AntiAliasingMode.taa].
/// {@category Rendering}
class TemporalAntiAliasingSettings {
  TemporalAntiAliasingSettings({
    this.jitterSequenceLength = 11,
    this.jitterScale = 0.46,
    this.minimumCurrentWeight = 0.15,
    this.varianceGamma = 1.2,
    this.sharpness = 0.15,
    this.objectMotion = false,
    this.skinnedMotion = false,
  });

  /// Length of the Halton (2, 3) jitter sequence. Longer sequences resolve
  /// more subpixel detail and take longer to converge. The industry band is
  /// 8 to 16.
  int jitterSequenceLength;

  /// Scales the jitter offset, `1.0` covering the full pixel.
  double jitterScale;

  /// Minimum weight the current frame keeps, so the history can never fully
  /// take over. Raising it cuts ghosting and adds shimmer. Shipping engines
  /// sit between 0.04 and 0.1.
  double minimumCurrentWeight;

  /// Width of the neighborhood variance band the history is clipped into, in
  /// standard deviations. Lower clips harder, cutting ghosting and adding
  /// flicker. The useful band is roughly 0.75 to 1.25.
  double varianceGamma;

  /// Sharpening applied after the resolve, countering the resolve's
  /// inherent softening. `0` disables it.
  double sharpness;

  /// Whether moving objects render a velocity buffer. With this false only
  /// the camera's motion is reprojected, which is correct for a static scene
  /// and leaves trails behind moving geometry.
  bool objectMotion;

  /// Whether skinned meshes contribute deformation velocity, which needs the
  /// previous frame's joint matrices kept alive.
  bool skinnedMotion;
}

/// Computes the [index]-th term of the Halton sequence for [base].
double halton(int index, int base) {
  var f = 1.0;
  var r = 0.0;
  var current = index;
  while (current > 0) {
    f /= base;
    r += f * (current % base);
    current ~/= base;
  }
  return r;
}

/// Computes the 2D Halton (2, 3) sample at [index] (1-indexed).
Vector2 halton23(int index) => Vector2(halton(index, 2), halton(index, 3));
