// Axis locks, gravity scale, CCD flag, and sleep API round-trip
// through the native FFI.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _boot({Vector3? gravity}) {
  final root = Node();
  final world = PhysicsWorld(RapierWorld(gravity: gravity));
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('locking the Y translation axis stops a falling body', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
    final body = RigidBody(
      type: BodyType.dynamic_,
      mass: 1.0,
      linearAxisLocks: Vector3(1, 0, 1),
    );
    node.addComponent(body);
    root.add(node);
    body.mount();

    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(body.readSimulationPose().$1.y, closeTo(5.0, 1e-3));
  });

  test('locking rotation axes stops a torque from spinning the body', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node();
    final body = RigidBody(
      type: BodyType.dynamic_,
      angularAxisLocks: Vector3(0, 0, 0),
    );
    node.addComponent(body);
    node.addComponent(Collider(shape: SphereShape(radius: 1)));
    root.add(node);
    body.mount();
    node.getComponents<Collider>().first.mount();

    body.applyAngularImpulse(Vector3(10, 10, 10));
    world.step(1.0 / 60.0);
    final w = body.angularVelocity;
    expect(w.length, closeTo(0.0, 1e-3));
  });

  test('useGravity=false suspends a dynamic body', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
    final body = RigidBody(
      type: BodyType.dynamic_,
      mass: 1.0,
      useGravity: false,
    );
    node.addComponent(body);
    root.add(node);
    body.mount();

    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(body.readSimulationPose().$1.y, closeTo(5.0, 1e-3));
  });

  test('useGravity setter at runtime re-enables gravity', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
    final body = RigidBody(
      type: BodyType.dynamic_,
      mass: 1.0,
      useGravity: false,
    );
    node.addComponent(body);
    root.add(node);
    body.mount();

    body.useGravity = true;
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(body.readSimulationPose().$1.y, lessThan(5.0));
  });

  test('putToSleep / wakeUp round-trip through the native side', () {
    final root = _boot();

    final node = Node();
    final body = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    node.addComponent(body);
    root.add(node);
    body.mount();

    expect(body.isSleeping, isFalse);
    body.putToSleep();
    expect(body.isSleeping, isTrue);
    body.wakeUp();
    expect(body.isSleeping, isFalse);
  });

  test('ccdEnabled flips without crashing', () {
    final root = _boot();

    final node = Node();
    final body = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    node.addComponent(body);
    root.add(node);
    body.mount();

    body.ccdEnabled = true;
    expect(body.ccdEnabled, isTrue);
    body.ccdEnabled = false;
    expect(body.ccdEnabled, isFalse);
  });
}
