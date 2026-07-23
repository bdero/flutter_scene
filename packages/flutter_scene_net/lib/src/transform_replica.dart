import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// vector_math adapters over [TransformReplica]'s record-typed pose.
extension TransformReplicaVectors on TransformReplica {
  Vector3 get positionVector =>
      Vector3(position.value.$1, position.value.$2, position.value.$3);

  Quaternion get rotationQuaternion => Quaternion(
    rotation.value.$1,
    rotation.value.$2,
    rotation.value.$3,
    rotation.value.$4,
  );

  /// Writes a pose into the replicated fields (authority side).
  void setPose(Vector3 translation, [Quaternion? orientation]) {
    position.value = (translation.x, translation.y, translation.z);
    if (orientation != null) {
      rotation.value = (
        orientation.x,
        orientation.y,
        orientation.z,
        orientation.w,
      );
    }
  }
}
