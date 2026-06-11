import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// One contact point in a [CollisionBegan] event.
///
/// [worldNormal] points from collider A into collider B. [impulse] is
/// the normal impulse applied to resolve the contact this step (zero
/// for trigger events). [separation] is positive when bodies are
/// separated and negative when they are interpenetrating.
/// {@category Physics}
class ContactPoint {
  final Vector3 worldPosition;
  final Vector3 worldNormal;
  final double impulse;
  final double separation;

  ContactPoint({
    required this.worldPosition,
    required this.worldNormal,
    required this.impulse,
    required this.separation,
  });
}

/// Base type for collision lifecycle events streamed by a physics world.
///
/// Subscribe via `PhysicsWorld.collisions`. The same pair fires
/// [CollisionBegan] / [CollisionEnded] for solid contacts and
/// [TriggerEntered] / [TriggerExited] for trigger volumes.
/// {@category Physics}
sealed class CollisionEvent {
  /// The node owning [colliderA]. [nodeA] and [nodeB] may be the same
  /// when a compound body's children touch each other.
  Node get nodeA;
  Node get nodeB;

  Component get colliderA;
  Component get colliderB;
}

/// Fired the first step a pair of solid colliders touch.
/// {@category Physics}
class CollisionBegan extends CollisionEvent {
  @override
  final Node nodeA;
  @override
  final Node nodeB;
  @override
  final Component colliderA;
  @override
  final Component colliderB;

  /// The contact manifold for this pair as seen by the solver.
  final List<ContactPoint> contacts;

  CollisionBegan({
    required this.nodeA,
    required this.nodeB,
    required this.colliderA,
    required this.colliderB,
    required this.contacts,
  });
}

/// Fired the step a previously-touching solid pair separates.
/// {@category Physics}
class CollisionEnded extends CollisionEvent {
  @override
  final Node nodeA;
  @override
  final Node nodeB;
  @override
  final Component colliderA;
  @override
  final Component colliderB;

  CollisionEnded({
    required this.nodeA,
    required this.nodeB,
    required this.colliderA,
    required this.colliderB,
  });
}

/// Fired the first step a non-trigger collider overlaps a trigger
/// volume.
/// {@category Physics}
class TriggerEntered extends CollisionEvent {
  @override
  final Node nodeA;
  @override
  final Node nodeB;
  @override
  final Component colliderA;
  @override
  final Component colliderB;

  TriggerEntered({
    required this.nodeA,
    required this.nodeB,
    required this.colliderA,
    required this.colliderB,
  });
}

/// Fired the step a previously-overlapping pair stops overlapping a
/// trigger volume.
/// {@category Physics}
class TriggerExited extends CollisionEvent {
  @override
  final Node nodeA;
  @override
  final Node nodeB;
  @override
  final Component colliderA;
  @override
  final Component colliderB;

  TriggerExited({
    required this.nodeA,
    required this.nodeB,
    required this.colliderA,
    required this.colliderB,
  });
}
