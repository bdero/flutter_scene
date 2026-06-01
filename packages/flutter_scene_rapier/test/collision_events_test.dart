// Collision and trigger lifecycle events fire on the collisions
// stream as colliders start and stop touching.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _boot({Vector3? gravity}) {
  final root = Node();
  final world = RapierWorld(gravity: gravity ?? Vector3(0, -9.81, 0));
  root.addComponent(world);
  world.mount();
  return root;
}

(Node, RapierRigidBody, RapierCollider) _add(
  Node root,
  Shape shape,
  Vector3 position,
  BodyType type, {
  bool isTrigger = false,
  double? mass,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  final body = RapierRigidBody(type: type, mass: mass);
  node.addComponent(body);
  final collider = RapierCollider(shape: shape, isTrigger: isTrigger);
  node.addComponent(collider);
  root.add(node);
  body.mount();
  collider.mount();
  return (node, body, collider);
}

void main() {
  test('a dynamic body landing on a floor emits CollisionBegan', () async {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final events = <CollisionEvent>[];
    final sub = world.collisions.listen(events.add);

    _add(
      root,
      BoxShape(halfExtents: Vector3(10, 0.5, 10)),
      Vector3(0, -0.5, 0),
      BodyType.fixed,
    );
    _add(
      root,
      SphereShape(radius: 0.5),
      Vector3(0, 3, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    // Step long enough for the sphere to fall and land.
    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<CollisionBegan>(), isNotEmpty);
    final began = events.whereType<CollisionBegan>().first;
    // The pair should be the two nodes we added (order is unspecified).
    final nodes = {began.nodeA, began.nodeB};
    expect(nodes.length, 2);

    await sub.cancel();
  });

  test('CollisionBegan carries solved contact-manifold points', () async {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final events = <CollisionEvent>[];
    final sub = world.collisions.listen(events.add);

    _add(
      root,
      BoxShape(halfExtents: Vector3(10, 0.5, 10)),
      Vector3(0, -0.5, 0),
      BodyType.fixed,
    );
    _add(
      root,
      SphereShape(radius: 0.5),
      Vector3(0, 3, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }
    await Future<void>.delayed(Duration.zero);

    final began = events.whereType<CollisionBegan>().first;
    expect(began.contacts, isNotEmpty);
    final contact = began.contacts.first;
    // The floor contact is essentially flat: a near-vertical unit normal,
    // a point near the floor's top surface (y == 0), and touching shapes.
    expect(contact.worldNormal.y.abs(), greaterThan(0.9));
    expect(contact.worldPosition.y.abs(), lessThan(0.2));
    expect(contact.separation.abs(), lessThan(0.2));
    // The solver applied a non-zero normal impulse to arrest the fall.
    expect(contact.impulse, greaterThan(0));

    await sub.cancel();
  });

  test('a body entering and leaving a trigger emits enter then exit', () async {
    final root = _boot(gravity: Vector3.zero());
    final world = root.getComponent<RapierWorld>()!;

    final events = <CollisionEvent>[];
    final sub = world.collisions.listen(events.add);

    // Stationary trigger volume at the origin.
    _add(
      root,
      SphereShape(radius: 1),
      Vector3.zero(),
      BodyType.fixed,
      isTrigger: true,
    );
    // Kinematic body that we sweep through the trigger.
    final (moverNode, mover, _) = _add(
      root,
      SphereShape(radius: 0.5),
      Vector3(-5, 0, 0),
      BodyType.kinematic,
    );

    // Sweep continuously from one side, through the trigger, and out
    // the far side.
    for (var i = 0; i < 120; i++) {
      moverNode.localTransform = Matrix4.translation(
        Vector3(-5 + i * 0.1, 0, 0),
      );
      root.sceneFixedPass(1.0 / 60.0);
      world.step(1.0 / 60.0);
      await Future<void>.delayed(Duration.zero);
    }

    expect(events.whereType<TriggerEntered>(), isNotEmpty);
    expect(events.whereType<TriggerExited>(), isNotEmpty);
    // Should see no solid-contact events for a sensor pair.
    expect(events.whereType<CollisionBegan>(), isEmpty);

    await sub.cancel();
  });

  test('no events fire when bodies never touch', () async {
    final root = _boot(gravity: Vector3.zero());
    final world = root.getComponent<RapierWorld>()!;

    final events = <CollisionEvent>[];
    final sub = world.collisions.listen(events.add);

    _add(root, SphereShape(radius: 0.5), Vector3(0, 0, 0), BodyType.fixed);
    _add(root, SphereShape(radius: 0.5), Vector3(50, 0, 0), BodyType.fixed);

    for (var i = 0; i < 30; i++) {
      world.step(1.0 / 60.0);
    }
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
    await sub.cancel();
  });
}
