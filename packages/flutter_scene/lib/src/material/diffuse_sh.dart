// The diffuse spherical-harmonic contract: the basis the shader evaluates, the
// sidecar/metadata encoding imported environments carry their coefficients in,
// and a self-check integrators can run against their own bake.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// Number of L2 spherical-harmonic coefficients used for diffuse
/// irradiance (bands 0..2).
/// {@category Lighting and environment}
const int kDiffuseShCoefficientCount = 9;

/// Bytes of a diffuse spherical-harmonic sidecar: 9 RGB coefficients of
/// 32-bit float.
/// {@category Lighting and environment}
const int kDiffuseShSidecarByteLength = kDiffuseShCoefficientCount * 3 * 4;

/// The KTX2 key/value key an environment file's diffuse spherical harmonics
/// are read from, holding exactly the [kDiffuseShSidecarByteLength] bytes
/// [encodeDiffuseShSidecar] produces.
///
/// A file carrying this key needs no sidecar; an explicitly passed coefficient
/// list still wins over it.
/// {@category Lighting and environment}
const String kDiffuseShKtx2Key = 'fsDiffuseSh';

/// The value of the L0 basis function, `sqrt(1 / (4 pi))`. Evaluating a
/// coefficient list holding only `radiance / kShBand0Basis` at band 0 returns
/// `radiance` in every direction.
/// {@category Lighting and environment}
const double kShBand0Basis = 0.28209479177387814;

/// Evaluates the real L2 spherical-harmonic basis for [direction] into [out]
/// (length [kDiffuseShCoefficientCount]). Must match the polynomial the
/// standard fragment shader evaluates.
void _evaluateShBasis(Vector3 direction, Float64List out) {
  final x = direction.x;
  final y = direction.y;
  final z = direction.z;
  out[0] = 0.282095;
  out[1] = 0.488603 * y;
  out[2] = 0.488603 * z;
  out[3] = 0.488603 * x;
  out[4] = 1.092548 * x * y;
  out[5] = 1.092548 * y * z;
  out[6] = 0.315392 * (3.0 * z * z - 1.0);
  out[7] = 1.092548 * x * z;
  out[8] = 0.546274 * (x * x - y * y);
}

/// Evaluates diffuse spherical harmonics [sh] for a surface normal
/// [direction], returning the linear RGB radiance a white Lambertian surface
/// reflects.
///
/// This is exactly the polynomial the standard shader evaluates, so it is the
/// reference for checking coefficients produced elsewhere. Coefficients must
/// already fold in the Lambertian cosine convolution (`A_l`) and the `1/pi`
/// BRDF term; see [describeDiffuseSphericalHarmonics].
/// {@category Lighting and environment}
Vector3 evaluateDiffuseSphericalHarmonics(List<Vector3> sh, Vector3 direction) {
  if (sh.length != kDiffuseShCoefficientCount) {
    throw ArgumentError.value(
      sh.length,
      'sh',
      'Expected $kDiffuseShCoefficientCount coefficients',
    );
  }
  final normal = direction.normalized();
  final basis = Float64List(kDiffuseShCoefficientCount);
  _evaluateShBasis(normal, basis);
  final result = Vector3.zero();
  for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
    result.x += sh[i].x * basis[i];
    result.y += sh[i].y * basis[i];
    result.z += sh[i].z * basis[i];
  }
  return result;
}

/// What [describeDiffuseSphericalHarmonics] measured about a coefficient set.
/// {@category Lighting and environment}
class ShDiffuseSummary {
  ShDiffuseSummary({
    required this.mean,
    required this.minimum,
    required this.maximum,
    required this.negativeFraction,
  });

  /// Mean reflected radiance over the sphere. For coefficients projected from
  /// an environment this equals the environment's average radiance, so a
  /// constant environment of radiance `L` round-trips to `mean == L`.
  final Vector3 mean;

  /// Lowest per-channel radiance any direction evaluates to. Meaningfully
  /// negative values mean ringing (or a bad bake).
  final Vector3 minimum;

  /// Highest per-channel radiance any direction evaluates to.
  final Vector3 maximum;

  /// Fraction of sampled directions where any channel evaluates negative.
  final double negativeFraction;

  /// How far the field strays from constant, as
  /// `max(|value - mean|) / max(mean)` over every sampled direction and
  /// channel. Zero for a perfectly uniform environment.
  double get constantDeviation {
    final scale = math.max(math.max(mean.x, mean.y), mean.z);
    if (scale <= 0.0) return 0.0;
    var worst = 0.0;
    for (final (value, m) in <(double, double)>[
      (minimum.x, mean.x),
      (minimum.y, mean.y),
      (minimum.z, mean.z),
      (maximum.x, mean.x),
      (maximum.y, mean.y),
      (maximum.z, mean.z),
    ]) {
      worst = math.max(worst, (value - m).abs());
    }
    return worst / scale;
  }

  @override
  String toString() =>
      'ShDiffuseSummary(mean: $mean, minimum: $minimum, maximum: $maximum, '
      'negativeFraction: ${negativeFraction.toStringAsFixed(3)})';
}

/// Evaluates [sh] over a Fibonacci-distributed sphere of directions and
/// summarizes the field, for checking coefficients baked outside the engine.
///
/// The engine's contract is that coefficients are irradiance-domain, with the
/// Lambertian `A_l` band factors and the `1/pi` BRDF term already folded in at
/// projection time. Under that contract [ShDiffuseSummary.mean] equals the
/// source environment's average linear radiance. Two self-checks follow:
///
///  * Feed a constant environment of radiance `L` (coefficient 0 set to
///    `L / kShBand0Basis`, the rest zero, which is what
///    `EnvironmentMap.constantDiffuse` builds). `mean` must come back `L` and
///    [ShDiffuseSummary.constantDeviation] must be ~0.
///  * A chain that left out the `1/pi` reads back `pi` times too bright; one
///    that folded it twice reads back `pi` times too dim. Compare `mean`
///    against the average radiance of the environment that was baked.
///
/// [directionCount] trades accuracy for speed; the default is plenty for a
/// smooth L2 field. Cheap enough for a debug assertion, not for a hot loop.
/// {@category Lighting and environment}
ShDiffuseSummary describeDiffuseSphericalHarmonics(
  List<Vector3> sh, {
  int directionCount = 512,
}) {
  if (directionCount < 1) {
    throw ArgumentError.value(directionCount, 'directionCount', 'Must be >= 1');
  }
  final total = Vector3.zero();
  var minimum = Vector3.all(double.infinity);
  var maximum = Vector3.all(double.negativeInfinity);
  var negative = 0;
  // Golden-angle spiral: near-uniform sphere coverage without a quadrature
  // grid's pole clustering.
  const goldenAngle = 2.399963229728653;
  for (var i = 0; i < directionCount; i++) {
    final y = 1.0 - 2.0 * (i + 0.5) / directionCount;
    final radius = math.sqrt(math.max(0.0, 1.0 - y * y));
    final theta = goldenAngle * i;
    final direction = Vector3(
      radius * math.cos(theta),
      y,
      radius * math.sin(theta),
    );
    final value = evaluateDiffuseSphericalHarmonics(sh, direction);
    total.add(value);
    minimum = Vector3(
      math.min(minimum.x, value.x),
      math.min(minimum.y, value.y),
      math.min(minimum.z, value.z),
    );
    maximum = Vector3(
      math.max(maximum.x, value.x),
      math.max(maximum.y, value.y),
      math.max(maximum.z, value.z),
    );
    if (value.x < 0.0 || value.y < 0.0 || value.z < 0.0) negative++;
  }
  return ShDiffuseSummary(
    mean: total / directionCount.toDouble(),
    minimum: minimum,
    maximum: maximum,
    negativeFraction: negative / directionCount,
  );
}

/// Encodes [sh] as the engine's diffuse spherical-harmonic sidecar:
/// [kDiffuseShCoefficientCount] RGB triples of little-endian 32-bit float,
/// coefficient-major (`c0.r, c0.g, c0.b, c1.r, ...`), for
/// [kDiffuseShSidecarByteLength] bytes total and no header.
///
/// The same bytes go in a KTX2 file's [kDiffuseShKtx2Key] key/value entry.
/// {@category Lighting and environment}
Uint8List encodeDiffuseShSidecar(List<Vector3> sh) {
  if (sh.length != kDiffuseShCoefficientCount) {
    throw ArgumentError.value(
      sh.length,
      'sh',
      'Expected $kDiffuseShCoefficientCount coefficients',
    );
  }
  final out = ByteData(kDiffuseShSidecarByteLength);
  for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
    out.setFloat32(i * 12, sh[i].x, Endian.little);
    out.setFloat32(i * 12 + 4, sh[i].y, Endian.little);
    out.setFloat32(i * 12 + 8, sh[i].z, Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Decodes a diffuse spherical-harmonic sidecar written by
/// [encodeDiffuseShSidecar]. Throws [FormatException] on a wrong-sized or
/// non-finite payload.
/// {@category Lighting and environment}
List<Vector3> parseDiffuseShSidecar(Uint8List bytes) {
  if (bytes.length != kDiffuseShSidecarByteLength) {
    throw FormatException(
      'Diffuse SH sidecar must be exactly $kDiffuseShSidecarByteLength bytes '
      '($kDiffuseShCoefficientCount RGB float32 coefficients), got '
      '${bytes.length}',
    );
  }
  final data = ByteData.sublistView(bytes);
  final sh = <Vector3>[];
  for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
    final coefficient = Vector3(
      data.getFloat32(i * 12, Endian.little),
      data.getFloat32(i * 12 + 4, Endian.little),
      data.getFloat32(i * 12 + 8, Endian.little),
    );
    if (!coefficient.x.isFinite ||
        !coefficient.y.isFinite ||
        !coefficient.z.isFinite) {
      throw FormatException('Diffuse SH coefficient $i is not finite');
    }
    sh.add(coefficient);
  }
  return sh;
}
