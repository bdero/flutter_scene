import 'package:vector_math/vector_math.dart';

/// A rigid transform reported by an XR runtime, a [position] and an
/// [orientation] in the session's reference space.
///
/// Runtimes describe poses in a right-handed, `+Y` up space where a tracked
/// thing (a viewer, a controller, a hand joint) looks along its local `-Z`.
/// The fields are mutable so a frame producer can refill one pose per frame
/// instead of allocating.
/// {@category Sessions}
class XrPose {
  /// A pose at [position] with [orientation], the identity when omitted.
  XrPose({Vector3? position, Quaternion? orientation})
    : position = position ?? Vector3.zero(),
      orientation = orientation ?? Quaternion.identity();

  /// The identity pose, at the reference space origin facing `-Z`.
  factory XrPose.identity() => XrPose();

  /// The translation, in meters.
  final Vector3 position;

  /// The rotation. Unit length.
  final Quaternion orientation;

  /// Whether the runtime guessed [position] (a three degree of freedom
  /// device, or a tracked thing that left its sensors' view).
  bool emulatedPosition = false;

  /// Copies [other] into this pose.
  void setFrom(XrPose other) {
    position.setFrom(other.position);
    orientation.setFrom(other.orientation);
    emulatedPosition = other.emulatedPosition;
  }

  /// Sets the pose from raw components, [qx]..[qw] being the orientation's
  /// `x, y, z, w`.
  void setValues(
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
  ) {
    position.setValues(px, py, pz);
    orientation.setValues(qx, qy, qz, qw);
  }

  /// The pose as a matrix (rotation then translation, unit scale).
  Matrix4 toMatrix() =>
      Matrix4.zero()
        ..setFromTranslationRotationScale(position, orientation, _unitScale);

  /// Writes [toMatrix] into [out] without allocating.
  void copyIntoMatrix(Matrix4 out) =>
      out.setFromTranslationRotationScale(position, orientation, _unitScale);

  /// Rotates [direction] by [orientation] into [out] (or a new vector), the
  /// active rotation the matrix form applies.
  Vector3 rotateDirection(Vector3 direction, [Vector3? out]) {
    final q = orientation.storage;
    final qx = q[0], qy = q[1], qz = q[2], qw = q[3];
    final vx = direction.x, vy = direction.y, vz = direction.z;
    // t = 2 * cross(q.xyz, v); v' = v + w * t + cross(q.xyz, t).
    final tx = 2.0 * (qy * vz - qz * vy);
    final ty = 2.0 * (qz * vx - qx * vz);
    final tz = 2.0 * (qx * vy - qy * vx);
    final result = out ?? Vector3.zero();
    result.setValues(
      vx + qw * tx + (qy * tz - qz * ty),
      vy + qw * ty + (qz * tx - qx * tz),
      vz + qw * tz + (qx * ty - qy * tx),
    );
    return result;
  }

  /// The direction this pose looks along, its local `-Z` in the reference
  /// space.
  Vector3 get forward => rotateDirection(_negativeZ);

  /// The pose's local `+Y` in the reference space.
  Vector3 get up => rotateDirection(_positiveY);

  @override
  String toString() => 'XrPose($position, $orientation)';

  static final Vector3 _unitScale = Vector3(1.0, 1.0, 1.0);
  static final Vector3 _negativeZ = Vector3(0.0, 0.0, -1.0);
  static final Vector3 _positiveY = Vector3(0.0, 1.0, 0.0);
}
