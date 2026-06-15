import 'dart:math';

import 'package:vector_math/vector_math.dart';

/// Euler-angle conversion for the inspector's rotation field.
///
/// The editor shows rotations as XYZ Euler angles in degrees (the most legible
/// form), but stores them as quaternions. These convert between the two using a
/// consistent extrinsic XYZ convention (the quaternion is `qz * qy * qx`), so a
/// value round-trips. Gimbal lock collapses the X and Z terms, as expected.

/// Builds a quaternion from XYZ Euler angles in [degrees].
Quaternion eulerXyzDegreesToQuaternion(Vector3 degrees) {
  final qx = Quaternion.axisAngle(
    Vector3(1, 0, 0),
    degrees.x * degrees2Radians,
  );
  final qy = Quaternion.axisAngle(
    Vector3(0, 1, 0),
    degrees.y * degrees2Radians,
  );
  final qz = Quaternion.axisAngle(
    Vector3(0, 0, 1),
    degrees.z * degrees2Radians,
  );
  return (qz * qy * qx)..normalize();
}

/// Extracts XYZ Euler angles in degrees from [q].
Vector3 quaternionToEulerXyzDegrees(Quaternion q) {
  final n = q.normalized();
  final x = n.x, y = n.y, z = n.z, w = n.w;
  // Rotation matrix terms (for R = Rz * Ry * Rx) that the extraction needs.
  final r00 = 1 - 2 * (y * y + z * z);
  final r10 = 2 * (x * y + w * z);
  final r20 = 2 * (x * z - w * y);
  final r21 = 2 * (y * z + w * x);
  final r22 = 1 - 2 * (x * x + y * y);
  final r11 = 1 - 2 * (x * x + z * z);
  final r12 = 2 * (y * z - w * x);

  final cy = sqrt(r00 * r00 + r10 * r10);
  double ex, ey, ez;
  ey = atan2(-r20, cy);
  if (cy > 1e-6) {
    ex = atan2(r21, r22);
    ez = atan2(r10, r00);
  } else {
    // Gimbal lock: fold Z into X.
    ex = atan2(-r12, r11);
    ez = 0;
  }
  return Vector3(
    ex * radians2Degrees,
    ey * radians2Degrees,
    ez * radians2Degrees,
  );
}
