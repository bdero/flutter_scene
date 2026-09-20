// The CPU side of the split-sum "environment BRDF" (DFG) table: pure Dart with
// no Flutter or GPU dependency, so the same code computes the shipped
// `assets/dfg.bin` offline (tool/generate_dfg_lut.dart), runs inside a worker
// isolate as the runtime fallback, and is checked for parity by a unit test.

import 'dart:math' as math;
import 'dart:typed_data';

/// Edge length of the square DFG table (and of each LTC tile beside it).
const int kDfgLutSize = 64;

/// Monte-Carlo samples per texel the shipped table was integrated with.
const int kDfgLutSampleCount = 1024;

/// The half-float bytes one [kDfgLutSize] tile occupies (RGBA16F).
const int kDfgLutTileBytes = kDfgLutSize * kDfgLutSize * 4 * 2;

/// Integrates the DFG tile: `size * size` RGBA half-float texels, laid out
/// row-major, holding `(scale, bias, 0, 1)` per `(n·v, roughness)`.
///
/// Row `y` is roughness `(y + 0.5) / size`, column `x` is `n·v =
/// (x + 0.5) / size`, both sampled at texel centers. This is the data
/// `assets/dfg.bin` stores verbatim.
Uint16List buildDfgLutHalfData({
  int size = kDfgLutSize,
  int sampleCount = kDfgLutSampleCount,
}) {
  final halfData = Uint16List(size * size * 4);
  for (var y = 0; y < size; y++) {
    // Row 0 is roughness 0 (smooth); sample at texel centers.
    final roughness = (y + 0.5) / size;
    for (var x = 0; x < size; x++) {
      final nDotV = (x + 0.5) / size;
      final ab = integrateBrdf(nDotV, roughness, sampleCount);
      final o = (y * size + x) * 4;
      halfData[o] = dfgFloatToHalf(ab.$1); // scale
      halfData[o + 1] = dfgFloatToHalf(ab.$2); // bias
      halfData[o + 2] = 0; // half 0.0
      halfData[o + 3] = 0x3C00; // half 1.0
    }
  }
  return halfData;
}

/// Integrates the split-sum BRDF for a given `nDotV` and perceptual
/// `roughness` (Karis 2013 `IntegrateBRDF`), returning `(scale, bias)`.
(double, double) integrateBrdf(double nDotV, double roughness, int samples) {
  // View vector in the tangent frame where the normal is +Z.
  final vx = math.sqrt((1.0 - nDotV * nDotV).clamp(0.0, 1.0));
  final vz = nDotV;

  final alpha = roughness * roughness; // GGX importance-sampling width
  final a2m1 = alpha * alpha - 1.0;
  final k = alpha / 2.0; // IBL geometry term k = roughness^2 / 2 (Karis)

  var scale = 0.0;
  var bias = 0.0;
  for (var i = 0; i < samples; i++) {
    final xi1 = i / samples;
    final xi2 = _radicalInverseVdC(i);

    // Importance-sample a GGX half-vector around +Z.
    final phi = 2.0 * math.pi * xi1;
    final cosTheta = math.sqrt(
      ((1.0 - xi2) / (1.0 + a2m1 * xi2)).clamp(0.0, 1.0),
    );
    final sinTheta = math.sqrt((1.0 - cosTheta * cosTheta).clamp(0.0, 1.0));
    // Only H's X and Z matter: the view lies in the X-Z plane (V.y == 0), so
    // the sample's Y component never enters n_dot_l, n_dot_h, or v_dot_h.
    final hx = math.cos(phi) * sinTheta;
    final hz = cosTheta;

    // Reflect the view about the half-vector to get the light direction.
    final vDotH = vx * hx + vz * hz; // V.y is 0
    final lz = 2.0 * vDotH * hz - vz;
    final nDotL = lz;
    if (nDotL <= 0.0) continue;

    final nDotH = hz;
    final vDotHc = vDotH < 0.0 ? 0.0 : vDotH;
    final g = _gSmith(nDotV, nDotL, k);
    final gVis = g * vDotHc / (nDotH * nDotV);
    final fc = _pow5(1.0 - vDotHc);
    scale += (1.0 - fc) * gVis;
    bias += fc * gVis;
  }
  return (scale / samples, bias / samples);
}

double _gSmith(double nDotV, double nDotL, double k) {
  double schlick(double n) => n / (n * (1.0 - k) + k);
  return schlick(nDotV) * schlick(nDotL);
}

double _pow5(double x) {
  final x2 = x * x;
  return x2 * x2 * x;
}

/// Van der Corput radical inverse (base 2), for the Hammersley sequence.
double _radicalInverseVdC(int i) {
  var bits = i & 0xFFFFFFFF;
  bits = ((bits << 16) | (bits >> 16)) & 0xFFFFFFFF;
  bits = (((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1)) & 0xFFFFFFFF;
  bits = (((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2)) & 0xFFFFFFFF;
  bits = (((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4)) & 0xFFFFFFFF;
  bits = (((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8)) & 0xFFFFFFFF;
  return bits * 2.3283064365386963e-10; // 1 / 2^32
}

final ByteData _f32 = ByteData(4);

/// Encodes a non-negative, well-behaved `double` (the DFG terms are in
/// `[0, 1]`) into an IEEE 754 half-float bit pattern, rounding to nearest.
///
/// Kept separate from `floatToHalfBits` (which truncates) so the shipped
/// asset stays bit-identical to what this integration produces.
int dfgFloatToHalf(double value) {
  _f32.setFloat32(0, value, Endian.little);
  final bits = _f32.getUint32(0, Endian.little);
  final sign = (bits >> 16) & 0x8000;
  final exponent = (bits >> 23) & 0xFF;
  var mantissa = bits & 0x7FFFFF;

  if (exponent == 0xFF) {
    // Inf or NaN.
    return sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0);
  }
  final e = exponent - 127 + 15;
  if (e >= 0x1F) {
    return sign | 0x7C00; // overflow to infinity
  }
  if (e <= 0) {
    if (e < -10) return sign; // underflow to zero
    mantissa |= 0x800000;
    final shift = 14 - e;
    var half = mantissa >> shift;
    if ((mantissa >> (shift - 1)) & 1 != 0) half += 1; // round to nearest
    return sign | half;
  }
  var half = (e << 10) | (mantissa >> 13);
  if ((mantissa & 0x1000) != 0) half += 1; // round to nearest
  return sign | half;
}
