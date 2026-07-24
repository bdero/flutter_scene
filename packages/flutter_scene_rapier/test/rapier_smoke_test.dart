// Smoke tests: RapierWorld satisfies the scene physics contract behind
// flutter_scene's generic components, the world can be driven through
// the fixed-step substepping loop without error, and a query against an
// empty world returns cleanly.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('RapierWorld exposes its backend name and a collisions stream', () {
    final world = PhysicsWorld(RapierWorld());
    expect(world.backendName, 'rapier3d');
    expect(world.collisions, isA<Stream<CollisionEvent>>());
  });

  test('substepping driver advances RapierWorld without error', () {
    final world = PhysicsWorld(RapierWorld(gravity: Vector3(0, -9.81, 0)));
    final residual = Scene.advancePhysics(
      world: world,
      fixedUpdateWalk: (_) {},
      accumulator: 0,
      frameDt: 1.0 / 30.0,
    );
    expect(residual, closeTo(0.0, 1e-9));
  });

  test('RigidBody round-trips properties through the component API', () {
    final body = RigidBody(
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

  test('Collider stores its shape, material, and pose', () {
    final shape = SphereShape(radius: 2);
    final collider = Collider(shape: shape, isTrigger: true);
    expect(identical(collider.shape, shape), isTrue);
    expect(collider.isTrigger, isTrue);
    expect(collider.localPose, isA<Matrix4>());
  });

  test('a raycast against an empty world returns null', () {
    final world = RapierWorld();
    final hit = world.raycast(
      Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1)),
    );
    expect(hit, isNull);
  });
}
