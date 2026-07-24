import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:scene/scene.dart' show ContactPoint;

export 'package:scene/scene.dart' show ContactPoint;

/// Collision lifecycle events for a [PhysicsWorld]'s bodies, resolved to
/// scene nodes and collider components.
/// {@category Physics}
sealed class CollisionEvent {
  CollisionEvent({
    required this.nodeA,
    required this.nodeB,
    required this.colliderA,
    required this.colliderB,
  });

  final Node nodeA;
  final Node nodeB;
  final Component colliderA;
  final Component colliderB;
}

/// Two solid colliders began touching.
/// {@category Physics}
class CollisionBegan extends CollisionEvent {
  CollisionBegan({
    required super.nodeA,
    required super.nodeB,
    required super.colliderA,
    required super.colliderB,
    this.contacts = const [],
  });

  /// The contact manifold at the moment contact began. May be empty when
  /// the backend does not report contact details.
  final List<ContactPoint> contacts;
}

/// Two solid colliders stopped touching.
/// {@category Physics}
class CollisionEnded extends CollisionEvent {
  CollisionEnded({
    required super.nodeA,
    required super.nodeB,
    required super.colliderA,
    required super.colliderB,
  });
}

/// A collider entered a trigger volume.
/// {@category Physics}
class TriggerEntered extends CollisionEvent {
  TriggerEntered({
    required super.nodeA,
    required super.nodeB,
    required super.colliderA,
    required super.colliderB,
  });
}

/// A collider left a trigger volume.
/// {@category Physics}
class TriggerExited extends CollisionEvent {
  TriggerExited({
    required super.nodeA,
    required super.nodeB,
    required super.colliderA,
    required super.colliderB,
  });
}
