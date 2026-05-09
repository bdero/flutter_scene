import 'dart:math';

import 'package:vector_math/vector_math.dart';

/// Per-component arithmetic helpers on [Vector3].
extension Vector3Lerp on Vector3 {
  /// Linearly interpolates each component of this vector toward [to].
  ///
  /// `weight` of `0` returns this vector unchanged; `1` returns [to].
  /// Values outside `[0, 1]` extrapolate.
  Vector3 lerp(Vector3 to, double weight) {
    return Vector3(
      x + (to.x - x) * weight,
      y + (to.y - y) * weight,
      z + (to.z - z) * weight,
    );
  }

  /// Returns the per-component quotient of this vector and [other].
  ///
  /// Equivalent to `Vector3(x / other.x, y / other.y, z / other.z)`.
  Vector3 divided(Vector3 other) {
    return Vector3(x / other.x, y / other.y, z / other.z);
  }
}

/// Spherical interpolation helpers on [Quaternion].
extension QuaternionSlerp on Quaternion {
  /// Returns the 4D dot product of this quaternion and [other].
  ///
  /// The sign of the result indicates whether the two rotations point in
  /// the same hemisphere; values near `1` (or `-1`) mean the rotations
  /// are nearly identical.
  double dot(Quaternion other) {
    return x * other.x + y * other.y + z * other.z + w * other.w;
  }

  /// Spherical linear interpolation from this quaternion toward [to].
  ///
  /// `weight` of `0` returns this rotation; `1` returns [to]. The
  /// implementation falls back to normalized linear interpolation when
  /// the two rotations are very close, which is both faster and
  /// numerically more stable.
  Quaternion slerp(Quaternion to, double weight) {
    double cosine = dot(to);
    if (cosine.abs() < 1.0 - 1e-3 /* epsilon */ ) {
      // Spherical interpolation.
      double sine = sqrt(1.0 - cosine * cosine);
      double angle = atan2(sine, cosine);
      double sineInverse = 1.0 / sine;
      double c0 = sin((1.0 - weight) * angle) * sineInverse;
      double c1 = sin(weight * angle) * sineInverse;
      return scaled(c0) + to.scaled(c1);
    } else {
      // Linear interpolation.
      return (scaled(1.0 - weight) + to.scaled(weight)).normalized();
    }
  }
}
