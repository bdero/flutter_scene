// IEEE 754 binary16 conversion, for the `r16g16b16a16Float` textures the
// engine uploads radiance into. Pure integer math so it is dart2js-safe
// (every intermediate stays inside 32 bits).

import 'dart:typed_data';

// Scratch storage for reinterpreting a 32-bit float as its raw bits.
final Float32List _floatBits = Float32List(1);
final Uint32List _floatBitsView = Uint32List.view(_floatBits.buffer);

/// Converts one 32-bit float to a 16-bit half-float bit pattern.
/// Subnormals flush to zero; values past the half range clamp to the
/// largest finite half.
int floatToHalfBits(double value) {
  _floatBits[0] = value;
  final bits = _floatBitsView[0];
  final sign = (bits >>> 16) & 0x8000;
  final exponent = ((bits >>> 23) & 0xff) - 112; // rebias 127 -> 15
  final mantissa = bits & 0x7fffff;
  if (exponent >= 0x1f) {
    return sign | 0x7bff; // overflow / inf / nan -> largest finite half
  }
  if (exponent <= 0) {
    return sign; // underflow -> signed zero
  }
  return sign | (exponent << 10) | (mantissa >>> 13);
}

/// Converts a 16-bit half-float bit pattern back to a double. Handles
/// subnormals, infinities, and NaN.
double halfBitsToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (bits >>> 10) & 0x1f;
  final mantissa = bits & 0x3ff;
  if (exponent == 0) {
    return sign * mantissa * 5.960464477539063e-8; // 2^-24
  }
  if (exponent == 0x1f) {
    return mantissa == 0 ? sign * double.infinity : double.nan;
  }
  return sign * (1024 + mantissa) * _halfExponentScale[exponent];
}

// 2^(e - 15) / 1024 for each normal half exponent, so the decode is a single
// multiply instead of a pow.
final Float64List _halfExponentScale = () {
  final scale = Float64List(0x1f);
  var value = 5.960464477539063e-8; // 2^-24, exponent 1
  for (var e = 1; e < 0x1f; e++) {
    scale[e] = value;
    value *= 2.0;
  }
  return scale;
}();

/// Converts linear RGBA float [pixels] to half-float bit patterns for upload to
/// an `r16g16b16a16Float` texture.
Uint16List floatPixelsToHalf(Float32List pixels) {
  final half = Uint16List(pixels.length);
  for (var i = 0; i < pixels.length; i++) {
    half[i] = floatToHalfBits(pixels[i]);
  }
  return half;
}
