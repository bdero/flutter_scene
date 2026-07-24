import 'package:vector_math/vector_math.dart';

/// Simulation mode for a body.
///
/// * [BodyType.fixed]: immovable environment geometry. The backend reads
///   the pose once at creation; mutating it at runtime is not supported.
/// * [BodyType.kinematic]: user-driven motion. The owner pushes target
///   poses; the body pushes dynamic bodies it contacts but is not itself
///   pushed.
/// * [BodyType.dynamic_]: fully simulated. The backend writes the pose
///   target each step in response to forces, contacts, and gravity. The
///   trailing underscore avoids the Dart `dynamic` keyword.
enum BodyType { fixed, kinematic, dynamic_ }

/// One contact within a collision manifold.
class ContactPoint {
  ContactPoint({
    required this.worldPosition,
    required this.worldNormal,
    required this.impulse,
    required this.separation,
  });

  final Vector3 worldPosition;
  final Vector3 worldNormal;
  final double impulse;
  final double separation;
}

/// A raycast result at the simulation level, keyed by collider handle.
class SimRaycastHit {
  SimRaycastHit({
    required this.colliderHandle,
    required this.worldPoint,
    required this.worldNormal,
    required this.distance,
  });

  final int colliderHandle;
  final Vector3 worldPoint;
  final Vector3 worldNormal;
  final double distance;
}

/// An overlap result at the simulation level.
class SimOverlapHit {
  SimOverlapHit({required this.colliderHandle});

  final int colliderHandle;
}

/// A shape-cast result at the simulation level.
class SimShapeCastHit extends SimRaycastHit {
  SimShapeCastHit({
    required super.colliderHandle,
    required super.worldPoint,
    required super.worldNormal,
    required super.distance,
  });
}

/// Collision lifecycle events at the simulation level, keyed by collider
/// handles. Engine layers resolve handles to their own collider objects.
sealed class SimCollisionEvent {
  SimCollisionEvent({
    required this.colliderHandleA,
    required this.colliderHandleB,
  });

  final int colliderHandleA;
  final int colliderHandleB;
}

class SimCollisionBegan extends SimCollisionEvent {
  SimCollisionBegan({
    required super.colliderHandleA,
    required super.colliderHandleB,
    this.contacts = const [],
  });

  final List<ContactPoint> contacts;
}

class SimCollisionEnded extends SimCollisionEvent {
  SimCollisionEnded({
    required super.colliderHandleA,
    required super.colliderHandleB,
  });
}

class SimTriggerEntered extends SimCollisionEvent {
  SimTriggerEntered({
    required super.colliderHandleA,
    required super.colliderHandleB,
  });
}

class SimTriggerExited extends SimCollisionEvent {
  SimTriggerExited({
    required super.colliderHandleA,
    required super.colliderHandleB,
  });
}

/// Result of one kinematic character move-and-slide.
class CharacterMovement {
  CharacterMovement({
    required this.translation,
    required this.grounded,
    required this.slidingDownSlope,
  });

  /// The corrected translation actually applied.
  final Vector3 translation;

  final bool grounded;
  final bool slidingDownSlope;
}
