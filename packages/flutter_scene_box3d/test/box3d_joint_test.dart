// Joint behaviour through the flutter_scene contract against box3d.
//
// ignore_for_file: invalid_use_of_internal_member

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_box3d/flutter_scene_box3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Node _bootWorld({Vector3? gravity}) {
  final root = Node();
  final world = Box3dPhysicsWorld(gravity: gravity);
  root.addComponent(world);
  world.mount();
  return root;
}

// Mounts a node with a body and a box collider under [root].
(Node, Box3dRigidBody) _addBox(
  Node root, {
  required BodyType type,
  required Vector3 position,
  Vector3? halfExtents,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  final body = Box3dRigidBody(type: type);
  node.addComponent(body);
  root.add(node);
  body.mount();
  final collider = Box3dCollider(
    shape: BoxShape(halfExtents: halfExtents ?? Vector3.all(0.5)),
  );
  node.addComponent(collider);
  collider.mount();
  return (node, body);
}

void main() {
  setUpAll(Box3dPhysicsWorld.ensureInitialized);

  void run(Box3dPhysicsWorld world, {int steps = 180}) {
    for (var i = 0; i < steps; i++) {
      world.step(1 / 60);
    }
    world.interpolateTransforms(1);
  }

  test('a fixed joint holds a body welded to the world', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    final (node, _) = _addBox(
      root,
      type: BodyType.dynamic_,
      position: Vector3(2, 3, 0),
    );

    final joint = Box3dFixedJoint();
    node.addComponent(joint);
    joint.mount();

    run(world);
    // Welded to the world at its start pose, it barely moves under gravity.
    final p = node.globalTransform.getTranslation();
    expect(p.x, closeTo(2, 0.05));
    expect(p.y, closeTo(3, 0.05));
  });

  test('a spherical joint hangs a body like a pendulum', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    final (node, _) = _addBox(
      root,
      type: BodyType.dynamic_,
      position: Vector3(0, -2, 0),
    );

    // Socket 2 units above the body (in world space via the world anchor).
    final joint = Box3dSphericalJoint(
      localAnchorA: Vector3(0, 2, 0),
      localAnchorB: Vector3(0, 0, 0),
    );
    node.addComponent(joint);
    joint.mount();

    run(world, steps: 300);
    // Stays roughly 2 units from the anchor point at the origin.
    expect(node.globalTransform.getTranslation().length, closeTo(2, 0.2));
  });

  test('a revolute joint with limits stops the swing', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    // Arm offset along +X so gravity torques the hinge at the origin.
    final (node, _) = _addBox(
      root,
      type: BodyType.dynamic_,
      position: Vector3(1, 0, 0),
      halfExtents: Vector3(1, 0.1, 0.1),
    );

    final joint = Box3dRevoluteJoint(
      axis: Vector3(0, 0, 1),
      localAnchorA: Vector3(-1, 0, 0), // hinge at the arm's inner end
      localAnchorB: Vector3(0, 0, 0), // world origin
      lowerLimit: -math.pi / 4,
      upperLimit: 0,
    );
    node.addComponent(joint);
    joint.mount();

    run(world, steps: 300);
    // The arm swings down but the -45 degree lower limit keeps its end from
    // hanging fully vertical.
    final y = node.globalTransform.getTranslation().y;
    expect(y, lessThan(0));
    expect(y, greaterThan(-0.85));
  });

  test('a prismatic joint confines motion to its axis', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    final (node, _) = _addBox(
      root,
      type: BodyType.dynamic_,
      position: Vector3(0, 0, 0),
    );

    // Slide axis is Y, limited to [-2, 0], anchored to the world.
    final joint = Box3dPrismaticJoint(
      axis: Vector3(0, 1, 0),
      lowerLimit: -2,
      upperLimit: 0,
    );
    node.addComponent(joint);
    joint.mount();

    run(world, steps: 300);
    final p = node.globalTransform.getTranslation();
    // Falls along Y to the lower limit; X and Z stay pinned.
    expect(p.x, closeTo(0, 0.05));
    expect(p.z, closeTo(0, 0.05));
    expect(p.y, closeTo(-2, 0.15));
  });
}
