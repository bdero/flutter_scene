// Stage 4 commit G tests: box / capsule / cylinder collider cooking.
// The headline test is the doc's acceptance criterion: a static box
// floor stops a dynamic sphere falling under gravity.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _bootWorld() {
  final root = Node();
  final world = RapierWorld();
  root.addComponent(world);
  world.mount();
  return root;
}

Node _addBody(
  Node root,
  Vector3 position,
  BodyType type,
  Shape shape, {
  PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  final body = RapierRigidBody(type: type);
  node.addComponent(body);
  final collider = RapierCollider(shape: shape, material: material);
  node.addComponent(collider);
  root.add(node);
  body.mount();
  collider.mount();
  return node;
}

void main() {
  test('sphere falls onto a fixed box floor and comes to rest', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    _addBody(
      root,
      Vector3(0, -0.5, 0),
      BodyType.fixed,
      BoxShape(halfExtents: Vector3(50, 0.5, 50)),
    );
    final ball = _addBody(
      root,
      Vector3(0, 5, 0),
      BodyType.dynamic_,
      SphereShape(radius: 0.5),
    );

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(0);

    final pos = ball.localTransform.getTranslation();
    expect(pos.y, greaterThan(0.4));
    expect(pos.y, lessThan(0.7));
  });

  test('capsule body settles upright on the floor', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    _addBody(
      root,
      Vector3(0, -0.5, 0),
      BodyType.fixed,
      BoxShape(halfExtents: Vector3(10, 0.5, 10)),
    );
    final capsule = _addBody(
      root,
      Vector3(0, 5, 0),
      BodyType.dynamic_,
      CapsuleShape(halfHeight: 0.5, radius: 0.5),
    );

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(0);

    final pos = capsule.localTransform.getTranslation();
    // Bottom hemisphere center sits one radius above the floor; the
    // node origin is the capsule center, so y ≈ halfHeight + radius = 1.
    expect(pos.y, greaterThan(0.8));
    expect(pos.y, lessThan(1.3));
  });

  test('cylinder body settles on the floor', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    _addBody(
      root,
      Vector3(0, -0.5, 0),
      BodyType.fixed,
      BoxShape(halfExtents: Vector3(10, 0.5, 10)),
    );
    final cylinder = _addBody(
      root,
      Vector3(0, 5, 0),
      BodyType.dynamic_,
      CylinderShape(halfHeight: 1.0, radius: 0.5),
    );

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(0);

    final pos = cylinder.localTransform.getTranslation();
    // Cylinder of halfHeight 1.0 sits with center at y ≈ 1.0.
    expect(pos.y, greaterThan(0.8));
    expect(pos.y, lessThan(1.3));
  });
}
