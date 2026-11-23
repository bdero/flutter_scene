import 'dart:math' as math;
import 'dart:ui' show Color, ColorSpace;

import 'package:vector_math/vector_math.dart';

// TODO(color-inputs): only the material base/emissive colors, the lights in
// light.dart and Fog have Color setters. Sky sources, god rays, environment
// settings, SunLight, sprites, instance colors and debug draw still take linear
// vectors only; callers convert with toLinearRgb/toLinearRgba. Add setters where
// users reach for them.

/// Converts a Flutter [Color], which is sRGB-encoded, into the linear color
/// the renderer's vector color fields take.
///
/// Material and light colors are linear (as in glTF), so assigning a widget's
/// color directly washes out its midtones. Convert it first, or use the
/// [Color] setters such as `UnlitMaterial.setBaseColor`.
/// {@category Materials}
extension ColorToLinear on Color {
  /// This color as linear RGBA. Alpha passes through unchanged.
  ///
  /// Colors in another color space are converted to sRGB primaries first.
  /// Channels above 1 (extended sRGB) stay above 1, and the negative channels a
  /// wide-gamut color can produce clip to 0.
  Vector4 toLinearRgba() {
    final c = _inSrgbPrimaries(this);
    return Vector4(_decode(c.r), _decode(c.g), _decode(c.b), c.a);
  }

  /// This color as linear RGB, ignoring alpha. See [toLinearRgba].
  Vector3 toLinearRgb() {
    final c = _inSrgbPrimaries(this);
    return Vector3(_decode(c.r), _decode(c.g), _decode(c.b));
  }
}

Color _inSrgbPrimaries(Color color) => color.colorSpace == ColorSpace.sRGB
    ? color
    : color.withValues(colorSpace: ColorSpace.extendedSRGB);

/// The sRGB EOTF (IEC 61966-2-1), clipping negatives and extending past 1.
double _decode(double v) {
  if (v <= 0.0) return 0.0;
  if (v <= 0.04045) return v / 12.92;
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}
