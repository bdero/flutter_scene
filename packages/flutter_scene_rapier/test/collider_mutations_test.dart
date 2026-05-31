// Stage 4 commit L: collider runtime mutations. Material, layer, mask,
// trigger flag, local pose, and shape changes all propagate to the
// live Rapier collider.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _boot({Vector3? gravity}) {
  final root = Node();
  final world = RapierWorld(gravity: gravity);
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('changing collision groups stops two colliders from interacting', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    // Static floor.
    final floorNode = Node(
      localTransform: Matrix4.translation(Vector3(0, -0.5, 0)),
    );
    floorNode.addComponent(RapierRigidBody(type: BodyType.fixed));
    floorNode.addComponent(
      RapierCollider(shape: BoxShape(halfExtents: Vector3(10, 0.5, 10))),
    );
    root.add(floorNode);
    floorNode.getComponents<RapierRigidBody>().first.mount();
    floorNode.getComponents<RapierCollider>().first.mount();

    // Dynamic sphere starting just above the floor. With matching
    // groups it should settle; with disjoint groups it falls through.
    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 2, 0)),
    );
    final ballBody = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    final ballCollider = RapierCollider(shape: SphereShape(radius: 0.5));
    ballNode.addComponent(ballCollider);
    root.add(ballNode);
    ballBody.mount();
    ballCollider.mount();

    // Disjoint groups: ball is in group 0x2, floor accepts only 0x1.
    ballCollider.collisionLayer = 0x2;
    ballCollider.collisionMask = 0x1;
    floorNode.getComponents<RapierCollider>().first.collisionLayer = 0x1;
    floorNode.getComponents<RapierCollider>().first.collisionMask = 0x2;

    // Actually our setup makes them MATCH (ball's layer 0x2 is in
    // floor's mask 0x2; floor's layer 0x1 is in ball's mask 0x1). So
    // they should still collide. Flip the ball mask to 0x4 to make
    // them disjoint.
    ballCollider.collisionMask = 0x4;

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(
      ballBody.readNativeTranslation().y,
      lessThan(-1.0),
      reason: 'ball with non-matching groups should pass through the floor',
    );
  });

  test('switching a collider to a sensor lets a ball pass through', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final floorNode = Node(
      localTransform: Matrix4.translation(Vector3(0, -0.5, 0)),
    );
    floorNode.addComponent(RapierRigidBody(type: BodyType.fixed));
    final floorCollider = RapierCollider(
      shape: BoxShape(halfExtents: Vector3(10, 0.5, 10)),
    );
    floorNode.addComponent(floorCollider);
    root.add(floorNode);
    floorNode.getComponents<RapierRigidBody>().first.mount();
    floorCollider.mount();

    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 2, 0)),
    );
    final ballBody = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    final ballCollider = RapierCollider(shape: SphereShape(radius: 0.5));
    ballNode.addComponent(ballCollider);
    root.add(ballNode);
    ballBody.mount();
    ballCollider.mount();

    floorCollider.isTrigger = true;

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(ballBody.readNativeTranslation().y, lessThan(-1.0));
  });

  test('localPose setter is a safe runtime no-op when not mounted', () {
    final collider = RapierCollider(shape: SphereShape(radius: 1));
    expect(
      () => collider.localPose = Matrix4.translation(Vector3(0, 5, 0)),
      returnsNormally,
    );
    expect(collider.localPose.getTranslation().y, closeTo(5.0, 1e-9));
  });

  test('localPose setter on a mounted collider does not crash', () {
    final root = _boot(gravity: Vector3.zero());

    final node = Node();
    final body = RapierRigidBody(type: BodyType.fixed);
    node.addComponent(body);
    final collider = RapierCollider(shape: SphereShape(radius: 0.5));
    node.addComponent(collider);
    root.add(node);
    body.mount();
    collider.mount();

    expect(
      () => collider.localPose = Matrix4.translation(Vector3(1, 2, 3)),
      returnsNormally,
    );
  });

  test('changing the shape rebuilds the collider', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final node = Node();
    final body = RapierRigidBody(type: BodyType.fixed);
    node.addComponent(body);
    final collider = RapierCollider(shape: SphereShape(radius: 0.5));
    node.addComponent(collider);
    root.add(node);
    body.mount();
    collider.mount();
    final initialHandle = collider.nativeHandle;
    expect(initialHandle, isNotNull);

    collider.shape = BoxShape(halfExtents: Vector3(1, 1, 1));
    expect(collider.nativeHandle, isNot(initialHandle));
  });
}
