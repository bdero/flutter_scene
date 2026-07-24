// Property setters that push to native after mount, reads that
// round-trip back through the FFI.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _bootZeroGravity() {
  final root = Node();
  final world = PhysicsWorld(RapierWorld(gravity: Vector3.zero()));
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('initial linearVelocity from constructor reaches the native body', () {
    final root = _bootZeroGravity();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node();
    final body = RigidBody(
      type: BodyType.dynamic_,
      mass: 1.0,
      linearVelocity: Vector3(3, 0, 0),
    );
    node.addComponent(body);
    root.add(node);
    body.mount();

    world.step(1.0 / 60.0);
    expect(body.readSimulationPose().$1.x, closeTo(3.0 / 60.0, 1e-3));
  });

  test('linearVelocity setter pushes through the FFI', () {
    final root = _bootZeroGravity();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node();
    final body = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    node.addComponent(body);
    root.add(node);
    body.mount();

    body.linearVelocity = Vector3(0, 2, 0);
    // Getter reads back from native.
    expect(body.linearVelocity.y, closeTo(2.0, 1e-5));

    world.step(1.0 / 60.0);
    expect(body.readSimulationPose().$1.y, closeTo(2.0 / 60.0, 1e-3));
  });

  test('angularVelocity setter round-trips', () {
    final root = _bootZeroGravity();

    final node = Node();
    final body = RigidBody(type: BodyType.dynamic_);
    node.addComponent(body);
    node.addComponent(Collider(shape: SphereShape(radius: 1.0)));
    root.add(node);
    body.mount();
    node.getComponents<Collider>().first.mount();

    body.angularVelocity = Vector3(0, 3.0, 0);
    expect(body.angularVelocity.y, closeTo(3.0, 1e-5));
  });

  test('linearDamping decays a moving body', () {
    final root = _bootZeroGravity();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node();
    final body = RigidBody(
      type: BodyType.dynamic_,
      mass: 1.0,
      linearVelocity: Vector3(10, 0, 0),
      linearDamping: 5.0,
    );
    node.addComponent(body);
    root.add(node);
    body.mount();

    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    // Heavy damping should slow the body well below its initial 10 m/s.
    expect(body.linearVelocity.x, lessThan(2.0));
  });

  test('changing mass at runtime affects impulse response', () {
    final root = _bootZeroGravity();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node();
    final body = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    node.addComponent(body);
    root.add(node);
    body.mount();

    body.mass = 10.0;
    body.applyImpulse(Vector3(0, 10, 0));
    world.step(1.0 / 60.0);
    // Impulse 10 / mass 10 = 1 m/s.
    expect(body.linearVelocity.y, closeTo(1.0, 1e-3));
  });
}
