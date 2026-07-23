import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:vector_math/vector_math.dart';

/// Finite-differences a world position across frames into a velocity.
// TODO(audio): suppress the one-frame velocity spike when the tracked
// position teleports (detect an implausible displacement and emit zero
// for that frame).
class PositionVelocityTracker {
  Vector3? _lastPosition;
  final Vector3 _velocity = Vector3.zero();

  /// Returns the velocity for this frame. The returned vector is reused
  /// across calls; copy it to retain it.
  Vector3 deriveFromPosition(Vector3 position, double deltaSeconds) {
    final last = _lastPosition;
    if (last == null || deltaSeconds <= 0) {
      _velocity.setZero();
    } else {
      _velocity
        ..setFrom(position)
        ..sub(last)
        ..scale(1.0 / deltaSeconds);
    }
    _lastPosition = (last ?? Vector3.zero())..setFrom(position);
    return _velocity;
  }

  /// Forgets the tracked position so the next derive reports zero.
  void reset() {
    _lastPosition = null;
    _velocity.setZero();
  }
}

/// Derives a world-space velocity for a node, for doppler.
///
/// Prefers the linear velocity of a dynamic [RigidBody] on the node
/// when one is present (exact and stable), otherwise falls back to
/// finite-differencing the world position.
class VelocityTracker extends PositionVelocityTracker {
  /// Returns the velocity for this frame given the node's current world
  /// [position]. The returned vector may be reused across calls; copy
  /// it to retain it.
  Vector3 derive(Node node, Vector3 position, double deltaSeconds) {
    final body = node.getComponent<RigidBody>();
    if (body != null && body.type == BodyType.dynamic_ && body.isMounted) {
      // Keep the position history warm so a body-type change does not
      // produce a stale-delta spike.
      deriveFromPosition(position, deltaSeconds);
      return body.linearVelocity;
    }
    return deriveFromPosition(position, deltaSeconds);
  }
}
