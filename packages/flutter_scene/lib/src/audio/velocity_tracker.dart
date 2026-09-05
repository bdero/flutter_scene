import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:scene/physics.dart' show BodyType;
import 'package:vector_math/vector_math.dart';

/// Finite-differences a world position across frames into a velocity.
class PositionVelocityTracker {
  /// Creates a tracker that treats a frame implying more than
  /// [teleportSpeed] as a teleport rather than as motion.
  PositionVelocityTracker({this.teleportSpeed = defaultTeleportSpeed});

  /// The speed of sound in air at 20 degrees C, in metres per second, and so
  /// in the engine's world units under the glTF metre convention.
  ///
  /// The default cutoff, because doppler is the only consumer of this
  /// velocity and it stops describing anything real at that speed: the shift
  /// goes to a singularity and then inverts.
  static const double defaultTeleportSpeed = 343.0;

  /// Above this implied speed a frame's displacement is read as a
  /// discontinuity and reported as zero velocity. Set it to
  /// [double.infinity] to report every finite difference as-is.
  final double teleportSpeed;

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
      // A respawn, a camera cut, or a level load moves the tracked node
      // discontinuously. The finite difference across that jump is not a
      // velocity, and feeding it to doppler pitch-bends every source for a
      // frame, which is far more audible than the frame of motion lost by
      // suppressing it. The new position is still recorded, so the next
      // frame derives normally from where the node landed.
      if (teleportSpeed.isFinite &&
          _velocity.length2 > teleportSpeed * teleportSpeed) {
        _velocity.setZero();
      }
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
  /// Creates a tracker with the given teleport cutoff. See
  /// [PositionVelocityTracker.teleportSpeed].
  VelocityTracker({super.teleportSpeed});

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
