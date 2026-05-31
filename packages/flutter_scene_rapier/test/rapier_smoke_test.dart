// Stage 3 smoke test: verifies that the Rapier-backed types satisfy
// the flutter_scene abstract physics contract and that the scaffold
// can be driven through the fixed-step substepping loop without error.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('RapierWorld exposes its backend name and a collisions stream', () {
    final world = RapierWorld();
    expect(world.backendName, 'rapier3d');
    expect(world.collisions, isA<Stream<CollisionEvent>>());
  });

  test('substepping driver advances RapierWorld without error', () {
    final world = RapierWorld(gravity: Vector3(0, -9.81, 0));
    final residual = Scene.advancePhysics(
      world: world,
      fixedUpdateWalk: (_) {},
      accumulator: 0,
      frameDt: 1.0 / 30.0,
    );
    expect(residual, closeTo(0.0, 1e-9));
  });

  test('RapierRigidBody round-trips properties through the abstract API', () {
    final body = RapierRigidBody(
      type: BodyType.dynamic_,
      mass: 2.5,
      linearVelocity: Vector3(1, 2, 3),
    );
    expect(body.type, BodyType.dynamic_);
    expect(body.mass, 2.5);
    expect(body.linearVelocity.x, 1);

    body.linearDamping = 0.5;
    expect(body.linearDamping, 0.5);
  });

  test('RapierCollider stores its shape, material, and pose', () {
    final shape = SphereShape(radius: 2);
    final collider = RapierCollider(shape: shape, isTrigger: true);
    expect(identical(collider.shape, shape), isTrue);
    expect(collider.isTrigger, isTrue);
    expect(collider.localPose, isA<Matrix4>());
  });

  test('query methods throw UnimplementedError until Stage 5', () {
    final world = RapierWorld();
    expect(
      () =>
          world.raycast(Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1))),
      throwsUnimplementedError,
    );
  });
}
