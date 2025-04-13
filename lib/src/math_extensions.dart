import 'dart:math';

import 'package:vector_math/vector_math.dart';

extension Vector3Lerp on Vector3 {
  Vector3 lerp(Vector3 to, double weight) {
    return Vector3(
      x + (to.x - x) * weight,
      y + (to.y - y) * weight,
      z + (to.z - z) * weight,
    );
  }

  Vector3 divided(Vector3 other) {
    return Vector3(x / other.x, y / other.y, z / other.z);
  }
}

extension QuaternionSlerp on Quaternion {
  double dot(Quaternion other) {
    return x * other.x + y * other.y + z * other.z + w * other.w;
  }

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
