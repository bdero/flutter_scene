import 'dart:math';

import 'package:vector_math/vector_math.dart';

/// Per-component arithmetic helpers on [Vector3].
/// {@category Scene graph}
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
/// {@category Scene graph}
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
    Quaternion target = to;
    // q and -q are the same rotation; pick the nearer one to take the short arc.
    if (cosine < 0.0) {
      target = to.scaled(-1.0);
      cosine = -cosine;
    }
    if (cosine < 1.0 - 1e-3 /* epsilon */ ) {
      // Spherical interpolation.
      double sine = sqrt(1.0 - cosine * cosine);
      double angle = atan2(sine, cosine);
      double sineInverse = 1.0 / sine;
      double c0 = sin((1.0 - weight) * angle) * sineInverse;
      double c1 = sin(weight * angle) * sineInverse;
      return scaled(c0) + target.scaled(c1);
    } else {
      // Linear interpolation.
      return (scaled(1.0 - weight) + target.scaled(weight)).normalized();
    }
  }
}

/// Rotating a vector by a quaternion, in the convention the scene graph uses.
///
/// **Not `Quaternion.rotate`.** vector_math's `rotate` and `rotated` compute
/// `conjugate(q) * v * q`, which is the *inverse* of the rotation
/// [Matrix4.compose] and [Quaternion.fromRotation] build from the same
/// quaternion. Everything in this engine — node transforms, camera poses,
/// animation output — is on the matrix side of that disagreement, so code that
/// reaches for `rotated` gets a vector pointing backwards. It gets it silently,
/// too: the two agree for the identity and for anything on a single axis, and
/// only diverge once the rotation is compound enough to notice.
/// {@category Scene graph}
extension QuaternionRotate on Quaternion {
  /// Returns [v] rotated by this quaternion.
  Vector3 rotateVector(Vector3 v) {
    final out = Vector3.zero();
    rotateVectorInto(v, out);
    return out;
  }

  /// Writes [v] rotated by this quaternion into [out], allocating nothing.
  ///
  /// For the per-frame paths — camera solving, constraint solving — where a
  /// fresh vector sixty times a second per caller is worth not allocating.
  /// [out] may be [v].
  void rotateVectorInto(Vector3 v, Vector3 out) {
    // v + 2w(a x v) + 2(a x (a x v)), for the axis part `a` of this quaternion.
    final vx = v.x, vy = v.y, vz = v.z;
    final cx = y * vz - z * vy;
    final cy = z * vx - x * vz;
    final cz = x * vy - y * vx;
    final dx = y * cz - z * cy;
    final dy = z * cx - x * cz;
    final dz = x * cy - y * cx;
    out
      ..x = vx + 2.0 * (w * cx + dx)
      ..y = vy + 2.0 * (w * cy + dy)
      ..z = vz + 2.0 * (w * cz + dz);
  }
}
