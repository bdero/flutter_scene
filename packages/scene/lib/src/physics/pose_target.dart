import 'package:vector_math/vector_math.dart';

/// Where a simulated body reads and writes its world pose.
///
/// The seam between a [PhysicsSimulation] and whatever owns spatial state,
/// a renderer adapts its scene-graph nodes, a headless server uses
/// [SimplePoseTarget] or adapts its own state.
abstract interface class PoseTarget {
  Vector3 get worldTranslation;
  Quaternion get worldRotation;

  /// Writes a simulated pose back. Backends call this from their
  /// interpolate step for dynamic bodies.
  void setWorldPose(Vector3 translation, Quaternion rotation);
}

/// A plain mutable pose.
final class SimplePoseTarget implements PoseTarget {
  SimplePoseTarget({Vector3? translation, Quaternion? rotation})
    : translation = translation ?? Vector3.zero(),
      rotation = rotation ?? Quaternion.identity();

  Vector3 translation;
  Quaternion rotation;

  @override
  Vector3 get worldTranslation => translation;

  @override
  Quaternion get worldRotation => rotation;

  @override
  void setWorldPose(Vector3 translation, Quaternion rotation) {
    this.translation.setFrom(translation);
    this.rotation.setFrom(rotation);
  }
}
