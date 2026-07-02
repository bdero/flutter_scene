// Drives the flutter_scene physics contract against box3d end to end:
// bodies and colliders are mounted, stepped, and the interpolated node
// transform is read back.
//
// ignore_for_file: invalid_use_of_internal_member
//
// Component.mount / step / interpolateTransforms are internal to
// flutter_scene; these tests call them directly because the test root is
// not part of a live RenderScene (which would need a Flutter GPU context).

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

// Mounts a node carrying a body and collider under [root].
(Node, Box3dRigidBody) _addBody(
  Node root, {
  required BodyType type,
  required Shape shape,
  required Vector3 position,
  bool isTrigger = false,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  final body = Box3dRigidBody(type: type);
  node.addComponent(body);
  root.add(node);
  body.mount();
  final collider = Box3dCollider(shape: shape, isTrigger: isTrigger);
  node.addComponent(collider);
  collider.mount();
  return (node, body);
}

void main() {
  setUpAll(Box3dPhysicsWorld.ensureInitialized);

  void run(Box3dPhysicsWorld world, {int steps = 240}) {
    for (var i = 0; i < steps; i++) {
      world.step(1 / 60);
    }
    world.interpolateTransforms(1);
  }

  test('a dynamic box falls and rests on a fixed floor', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;

    _addBody(
      root,
      type: BodyType.fixed,
      shape: BoxShape(halfExtents: Vector3(50, 0.5, 50)),
      position: Vector3(0, -0.5, 0),
    );
    final (box, _) = _addBody(
      root,
      type: BodyType.dynamic_,
      shape: BoxShape(halfExtents: Vector3.all(0.5)),
      position: Vector3(0, 5, 0),
    );

    run(world);

    // The interpolated node transform should show the box resting on the
    // floor, its center half its height above y = 0.
    final p = box.globalTransform.getTranslation();
    expect(p.y, closeTo(0.5, 0.1));
    expect(p.x, closeTo(0, 0.1));
  });

  test('a fixed body holds its position under gravity', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    final (node, _) = _addBody(
      root,
      type: BodyType.fixed,
      shape: SphereShape(radius: 0.5),
      position: Vector3(1, 2, 3),
    );

    run(world, steps: 60);

    final p = node.globalTransform.getTranslation();
    expect(p.x, closeTo(1, 1e-4));
    expect(p.y, closeTo(2, 1e-4));
    expect(p.z, closeTo(3, 1e-4));
  });

  test('a trigger reports enter and exit as a body falls through', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;

    final entered = <TriggerEntered>[];
    final exited = <TriggerExited>[];
    world.collisions.listen((e) {
      if (e is TriggerEntered) entered.add(e);
      if (e is TriggerExited) exited.add(e);
    });

    _addBody(
      root,
      type: BodyType.fixed,
      shape: BoxShape(halfExtents: Vector3(2, 0.5, 2)),
      position: Vector3(0, 0, 0),
      isTrigger: true,
    );
    _addBody(
      root,
      type: BodyType.dynamic_,
      shape: SphereShape(radius: 0.25),
      position: Vector3(0, 3, 0),
    );

    // Let microtasks deliver the broadcast-stream events between steps.
    for (var i = 0; i < 240; i++) {
      world.step(1 / 60);
    }
    return Future<void>.delayed(Duration.zero, () {
      expect(entered, hasLength(1));
      expect(exited, hasLength(1));
    });
  });

  test('raycast resolves to the hit collider and node', () {
    final root = _bootWorld(gravity: Vector3(0, 0, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    final (target, _) = _addBody(
      root,
      type: BodyType.fixed,
      shape: BoxShape(halfExtents: Vector3.all(0.5)),
      position: Vector3(5, 0, 0),
    );
    world.step(1 / 60); // build the broad phase

    final hit = world.raycast(
      Ray.originDirection(Vector3(0, 0, 0), Vector3(1, 0, 0)),
    );
    expect(hit, isNotNull);
    expect(hit!.node, same(target));
    expect(hit.worldPoint.x, closeTo(4.5, 0.05));
  });

  test('unmounting a body and collider does not crash (double-free guard)', () {
    // box3d cascades body destruction to its shapes, and a node's components
    // unmount in an order that can destroy the body before the collider.
    // Repeat enough to mirror the example app's body-cap churn.
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    for (var i = 0; i < 30; i++) {
      final node = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
      final body = Box3dRigidBody(type: BodyType.dynamic_);
      node.addComponent(body);
      root.add(node);
      body.mount();
      final collider = Box3dCollider(
        shape: BoxShape(halfExtents: Vector3.all(0.5)),
      );
      node.addComponent(collider);
      collider.mount();
      world.step(1 / 60);
      root.remove(node); // unmounts body + collider
    }
    world.step(1 / 60);
  });

  test('a compound collider rests on its lower box', () {
    final root = _bootWorld(gravity: Vector3(0, -10, 0));
    final world = root.getComponent<Box3dPhysicsWorld>()!;
    _addBody(
      root,
      type: BodyType.fixed,
      shape: BoxShape(halfExtents: Vector3(50, 0.5, 50)),
      position: Vector3(0, -0.5, 0),
    );
    final (node, _) = _addBody(
      root,
      type: BodyType.dynamic_,
      shape: CompoundShape(
        children: [
          CompoundChild(
            shape: BoxShape(halfExtents: Vector3.all(0.5)),
            localPose: Matrix4.translation(Vector3(0, 0.5, 0)),
          ),
          CompoundChild(
            shape: SphereShape(radius: 0.5),
            localPose: Matrix4.translation(Vector3(0, -0.5, 0)),
          ),
        ],
      ),
      position: Vector3(0, 5, 0),
    );

    run(world);
    // The sphere child sits at local y = -0.5 with radius 0.5, so its lowest
    // point is 1.0 below the body origin. Resting on the floor puts the body
    // origin near y = 1.0.
    expect(node.globalTransform.getTranslation().y, closeTo(1.0, 0.15));
  });
}
