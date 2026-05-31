// Stage 4 commit H: force / impulse application end to end through the
// FFI. Each test runs in zero gravity to isolate the effect.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('applyImpulse changes velocity in the impulse direction', () {
    final root = Node();
    final world = RapierWorld(gravity: Vector3.zero());
    root.addComponent(world);
    world.mount();

    final node = Node();
    final body = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    node.addComponent(body);
    root.add(node);
    body.mount();

    expect(body.readNativeLinearVelocity().y, closeTo(0.0, 1e-9));
    body.applyImpulse(Vector3(0, 5, 0));
    world.step(1.0 / 60.0);
    expect(body.readNativeLinearVelocity().y, closeTo(5.0, 1e-3));
  });

  test('applyForce accelerates the body', () {
    final root = Node();
    final world = RapierWorld(gravity: Vector3.zero());
    root.addComponent(world);
    world.mount();

    final node = Node();
    final body = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    node.addComponent(body);
    root.add(node);
    body.mount();

    // Apply 10 N upward for 60 steps at 1/60 s = 1 second. F=ma so
    // acceleration is 10 m/s^2, final velocity should be ~10 m/s.
    for (var i = 0; i < 60; i++) {
      body.applyForce(Vector3(0, 10, 0));
      world.step(1.0 / 60.0);
    }
    final v = body.readNativeLinearVelocity();
    expect(v.y, greaterThan(9.0));
    expect(v.y, lessThan(11.0));
  });

  test('applyAngularImpulse spins the body', () {
    final root = Node();
    final world = RapierWorld(gravity: Vector3.zero());
    root.addComponent(world);
    world.mount();

    final node = Node();
    // Body needs nonzero inertia for torque to spin it. Attach a
    // sphere collider with density so Rapier derives inertia.
    final body = RapierRigidBody(type: BodyType.dynamic_);
    node.addComponent(body);
    node.addComponent(RapierCollider(shape: SphereShape(radius: 1.0)));
    root.add(node);
    body.mount();
    node.getComponents<RapierCollider>().first.mount();

    expect(body.readNativeAngularVelocity().length, closeTo(0.0, 1e-9));
    body.applyAngularImpulse(Vector3(0, 5, 0));
    world.step(1.0 / 60.0);
    expect(body.readNativeAngularVelocity().y, greaterThan(0.1));
  });

  test('applying methods on an unmounted body is a safe no-op', () {
    final body = RapierRigidBody(type: BodyType.dynamic_);
    expect(() => body.applyImpulse(Vector3(1, 2, 3)), returnsNormally);
    expect(() => body.applyForce(Vector3(1, 2, 3)), returnsNormally);
    expect(() => body.applyTorque(Vector3(1, 2, 3)), returnsNormally);
    expect(() => body.applyAngularImpulse(Vector3(1, 2, 3)), returnsNormally);
  });
}
