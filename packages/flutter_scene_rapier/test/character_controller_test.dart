// The kinematic character controller resolves move-and-slide motion
// against the world: grounding, blocking on walls, and reporting the
// corrected translation.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _boot() {
  final root = Node();
  final world = RapierWorld(gravity: Vector3(0, -9.81, 0));
  root.addComponent(world);
  world.mount();
  return root;
}

// Adds a fixed box collider (a floor or wall) and mounts it.
void _addBox(Node root, Vector3 position, Vector3 halfExtents) {
  final node = Node(localTransform: Matrix4.translation(position));
  node.addComponent(RapierRigidBody(type: BodyType.fixed));
  node.addComponent(RapierCollider(shape: BoxShape(halfExtents: halfExtents)));
  root.add(node);
  node.getComponents<RapierRigidBody>().first.mount();
  node.getComponents<RapierCollider>().first.mount();
}

// Adds a fixed *sensor* box (a trigger volume) and mounts it.
void _addSensorBox(Node root, Vector3 position, Vector3 halfExtents) {
  final node = Node(localTransform: Matrix4.translation(position));
  node.addComponent(RapierRigidBody(type: BodyType.fixed));
  node.addComponent(
    RapierCollider(shape: BoxShape(halfExtents: halfExtents), isTrigger: true),
  );
  root.add(node);
  node.getComponents<RapierRigidBody>().first.mount();
  node.getComponents<RapierCollider>().first.mount();
}

// Adds a dynamic box and mounts it, returning its node.
Node _addDynamicBox(
  Node root,
  Vector3 position,
  Vector3 halfExtents, {
  double mass = 1.0,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  node.addComponent(RapierRigidBody(type: BodyType.dynamic_, mass: mass));
  node.addComponent(RapierCollider(shape: BoxShape(halfExtents: halfExtents)));
  root.add(node);
  node.getComponents<RapierRigidBody>().first.mount();
  node.getComponents<RapierCollider>().first.mount();
  return node;
}

// Adds a kinematic capsule character with a controller and mounts it.
(Node, RapierKinematicCharacterController) _addCharacter(
  Node root,
  Vector3 position, {
  bool withCollider = true,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  node.addComponent(RapierRigidBody(type: BodyType.kinematic));
  if (withCollider) {
    node.addComponent(
      RapierCollider(shape: CapsuleShape(radius: 0.3, halfHeight: 0.5)),
    );
  }
  final controller = RapierKinematicCharacterController();
  node.addComponent(controller);
  root.add(node);
  node.getComponents<RapierRigidBody>().first.mount();
  if (withCollider) {
    node.getComponents<RapierCollider>().first.mount();
  }
  controller.mount();
  return (node, controller);
}

void main() {
  test('a grounded character moves horizontally without sinking', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addBox(root, Vector3(0, -0.5, 0), Vector3(10, 0.5, 10)); // floor, top y=0
    // Capsule (half-extent 0.8 along Y) resting with its base on the floor.
    final (node, controller) = _addCharacter(root, Vector3(0, 0.8, 0));
    // Build the broad-phase over the initial collider poses.
    world.step(1.0 / 60.0);

    final r = controller.move(Vector3(0.2, 0, 0));
    expect(r.grounded, isTrue);
    expect(r.translation.x, closeTo(0.2, 0.05));
    expect(r.translation.y.abs(), lessThan(0.05));
    expect(node.globalTransform.getTranslation().x, closeTo(0.2, 0.05));
  });

  test('the floor blocks a downward move', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addBox(root, Vector3(0, -0.5, 0), Vector3(10, 0.5, 10));
    final (_, controller) = _addCharacter(root, Vector3(0, 0.8, 0));
    world.step(1.0 / 60.0);

    // Trying to drive straight down into the floor is absorbed.
    final r = controller.move(Vector3(0, -0.5, 0));
    expect(r.translation.y, greaterThan(-0.1));
    expect(r.grounded, isTrue);
  });

  test('a wall blocks forward motion instead of tunneling', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addBox(root, Vector3(0, -0.5, 0), Vector3(10, 0.5, 10)); // floor
    // A thin tall wall whose near face is at x = 0.9.
    _addBox(root, Vector3(1.0, 1.0, 0), Vector3(0.1, 2.0, 5.0));
    final (_, controller) = _addCharacter(root, Vector3(0, 0.8, 0));
    world.step(1.0 / 60.0);

    // Request a full unit of +X travel; the capsule (radius 0.3) should
    // stop against the wall well short of it rather than passing through.
    final r = controller.move(Vector3(1.0, 0, 0));
    expect(r.translation.x, lessThan(0.8));
    expect(r.translation.x, greaterThan(0.0));
  });

  test('a sensor volume does not block the character', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addBox(root, Vector3(0, -0.5, 0), Vector3(10, 0.5, 10)); // floor
    // Same layout as the wall test, but the obstacle is a trigger: the
    // character passes through it instead of stopping against it.
    _addSensorBox(root, Vector3(1.0, 1.0, 0), Vector3(0.1, 2.0, 5.0));
    final (_, controller) = _addCharacter(root, Vector3(0, 0.8, 0));
    world.step(1.0 / 60.0);

    final r = controller.move(Vector3(1.0, 0, 0));
    expect(r.translation.x, closeTo(1.0, 0.05));
  });

  test('a heavy character pushes a dynamic body it runs into', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addBox(root, Vector3(0, -0.5, 0), Vector3(10, 0.5, 10)); // floor
    // A 1 kg box just in front of the capsule's right edge (x = 0.3).
    final box = _addDynamicBox(root, Vector3(0.6, 0.8, 0), Vector3.all(0.2));
    final (_, controller) = _addCharacter(root, Vector3(0, 0.8, 0));
    controller.mass = 5.0;
    world.step(1.0 / 60.0);

    final startX = box.globalTransform.getTranslation().x;
    // Run into the box; the move transfers momentum to it, then a few
    // steps integrate the imparted velocity into a displacement.
    controller.move(Vector3(1.0, 0, 0));
    for (var i = 0; i < 10; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(1.0);
    expect(box.globalTransform.getTranslation().x, greaterThan(startX + 0.05));
  });

  test('a zero-mass character leaves a dynamic body in place', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addBox(root, Vector3(0, -0.5, 0), Vector3(10, 0.5, 10)); // floor
    final box = _addDynamicBox(root, Vector3(0.6, 0.8, 0), Vector3.all(0.2));
    // Default mass is 0: the character slides against the box like a wall.
    final (_, controller) = _addCharacter(root, Vector3(0, 0.8, 0));
    world.step(1.0 / 60.0);

    final startX = box.globalTransform.getTranslation().x;
    controller.move(Vector3(1.0, 0, 0));
    for (var i = 0; i < 10; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(1.0);
    // No horizontal shove; the box only settles under gravity.
    expect(box.globalTransform.getTranslation().x, closeTo(startX, 0.02));
  });

  test('parking a kinematic platform as fixed frees a stuck rider', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    // A wide kinematic platform (like the lift), parked (zero velocity).
    final platformNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 0, 0)),
    );
    final platformBody = RapierRigidBody(type: BodyType.kinematic);
    platformNode.addComponent(platformBody);
    platformNode.addComponent(
      RapierCollider(shape: BoxShape(halfExtents: Vector3(5, 0.5, 5))),
    );
    root.add(platformNode);
    platformBody.mount();
    platformNode.getComponents<RapierCollider>().first.mount();

    // Character standing on the platform (top y == 0.5).
    final (_, controller) = _addCharacter(root, Vector3(0, 1.3, 0));
    world.step(1.0 / 60.0);

    // On a stopped kinematic platform the controller's kinematic-platform
    // friction cancels the rider's horizontal input.
    final stuck = controller.move(Vector3(0.2, 0, 0));

    // Parking the platform as a fixed body removes that friction path, so
    // the same move now goes through.
    platformBody.type = BodyType.fixed;
    world.step(1.0 / 60.0);
    final freed = controller.move(Vector3(0.2, 0, 0));

    expect(stuck.translation.x, lessThan(0.05));
    expect(freed.translation.x, greaterThan(0.15));
  });

  test('move throws without a collider on the node', () {
    final root = _boot();
    final (_, controller) = _addCharacter(
      root,
      Vector3(0, 1, 0),
      withCollider: false,
    );
    expect(() => controller.move(Vector3(0.1, 0, 0)), throwsStateError);
  });
}
