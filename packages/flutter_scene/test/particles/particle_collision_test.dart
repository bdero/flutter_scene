// Particles hitting things. Pure arithmetic over the storage columns, so all
// of it runs without a GPU: what is covered is where a particle ends up and
// how fast it is going when it gets there.

import 'package:flutter_scene/scene.dart';
// The module codec is internal; the round trip is what a saved effect does.
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/particle_emitter_codec.dart'
    show decodeParticleCollider, decodeParticleModule, encodeParticleModule;
import 'package:scene/scene.dart' show MapValue, StringValue;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A system with one particle placed at [at] moving at [velocity], and no
/// gravity, so a test measures the collision and nothing else.
ParticleSystem oneParticle({
  required Vector3 at,
  required Vector3 velocity,
  required CollisionModule collision,
  double lifetime = 10,
}) {
  final system = ParticleSystem(
    maxParticles: 4,
    spawner: Spawner(bursts: [ParticleBurst(time: 0, count: 1)]),
    shape: PointEmitterShape(),
    modules: [collision],
    gravity: Vector3.zero(),
    lifetime: ConstantFloat(lifetime),
    startSpeed: const ConstantFloat(0),
  );
  system.step(1 / 60);
  expect(system.storage.aliveCount, 1);
  system.storage
    ..posX[0] = at.x
    ..posY[0] = at.y
    ..posZ[0] = at.z
    ..velX[0] = velocity.x
    ..velY[0] = velocity.y
    ..velZ[0] = velocity.z;
  return system;
}

Vector3 positionOf(ParticleSystem system) => Vector3(
  system.storage.posX[0],
  system.storage.posY[0],
  system.storage.posZ[0],
);

Vector3 velocityOf(ParticleSystem system) => Vector3(
  system.storage.velX[0],
  system.storage.velY[0],
  system.storage.velZ[0],
);

void main() {
  group('a ground plane', () {
    test('stops a particle falling through it', () {
      final system = oneParticle(
        at: Vector3(0, 0.05, 0),
        velocity: Vector3(0, -6, 0),
        collision: CollisionModule.ground(),
      );
      system.step(1 / 60);

      expect(
        positionOf(system).y,
        greaterThanOrEqualTo(-1e-6),
        reason: 'a particle must not end a step inside the floor',
      );
      expect(velocityOf(system).y, greaterThan(0), reason: 'it bounced');
    });

    test('a bounce keeps the restitution it was given', () {
      final system = oneParticle(
        at: Vector3(0, 0.01, 0),
        velocity: Vector3(0, -10, 0),
        collision: CollisionModule.ground(restitution: 0.5, friction: 0),
      );
      system.step(1 / 60);
      expect(velocityOf(system).y, closeTo(5, 1e-6));
    });

    test('friction bites the sideways speed, not the bounce', () {
      final system = oneParticle(
        at: Vector3(0, 0.01, 0),
        velocity: Vector3(4, -10, 0),
        collision: CollisionModule.ground(restitution: 0.5, friction: 0.25),
      );
      system.step(1 / 60);
      final velocity = velocityOf(system);
      expect(velocity.x, closeTo(3, 1e-6));
      expect(velocity.y, closeTo(5, 1e-6));
    });

    test('sliding drops the normal speed and keeps the rest', () {
      final system = oneParticle(
        at: Vector3(0, 0.01, 0),
        velocity: Vector3(4, -10, 0),
        collision: CollisionModule.ground(
          response: ParticleCollisionResponse.slide,
          friction: 0,
        ),
      );
      system.step(1 / 60);
      final velocity = velocityOf(system);
      expect(velocity.y, closeTo(0, 1e-6));
      expect(velocity.x, closeTo(4, 1e-6));
    });

    test('sticking stops it dead', () {
      final system = oneParticle(
        at: Vector3(0, 0.01, 0),
        velocity: Vector3(4, -10, 2),
        collision: CollisionModule.ground(
          response: ParticleCollisionResponse.stick,
        ),
      );
      system.step(1 / 60);
      expect(velocityOf(system).length, closeTo(0, 1e-9));
    });

    test('killing reaps it through the pool the system already has', () {
      final system = oneParticle(
        at: Vector3(0, 0.01, 0),
        velocity: Vector3(0, -10, 0),
        collision: CollisionModule.ground(
          response: ParticleCollisionResponse.kill,
        ),
      );
      system.step(1 / 60);
      expect(system.storage.aliveCount, 0);
    });

    test('a particle well clear of the floor is untouched', () {
      final system = oneParticle(
        at: Vector3(0, 20, 0),
        velocity: Vector3(1, -1, 0),
        collision: CollisionModule.ground(),
      );
      system.step(1 / 60);
      expect(velocityOf(system).x, closeTo(1, 1e-9));
      expect(velocityOf(system).y, closeTo(-1, 1e-9));
    });

    test('a radius stops it short rather than half inside', () {
      final system = oneParticle(
        at: Vector3(0, 0.05, 0),
        velocity: Vector3(0, -6, 0),
        collision: CollisionModule.ground(radius: 0.5),
      );
      system.step(1 / 60);
      expect(positionOf(system).y, greaterThanOrEqualTo(0.5 - 1e-6));
    });

    test('a hit can cost the particle part of its life', () {
      final system = oneParticle(
        at: Vector3(0, 0.01, 0),
        velocity: Vector3(0, -10, 0),
        collision: CollisionModule.ground(lifetimeLoss: 0.5),
        lifetime: 10,
      );
      final before = system.storage.age[0];
      system.step(1 / 60);
      expect(system.storage.age[0], greaterThan(before + 4));
    });
  });

  group('shapes', () {
    test('a sphere pushes a particle out along the radius', () {
      final system = oneParticle(
        at: Vector3(0.1, 0, 0),
        velocity: Vector3(-5, 0, 0),
        collision: CollisionModule(
          colliders: [ParticleSphere(centre: Vector3.zero(), radius: 1)],
          friction: 0,
          restitution: 1,
        ),
      );
      system.step(1 / 60);
      expect(positionOf(system).length, closeTo(1, 1e-5));
      expect(velocityOf(system).x, greaterThan(0));
    });

    test('a box ejects through its nearest face', () {
      // Just inside the top of a unit box: it should leave upward, not
      // sideways through a face it is nowhere near.
      final system = oneParticle(
        at: Vector3(0, 0.9, 0),
        velocity: Vector3(0, -3, 0),
        collision: CollisionModule(
          colliders: [
            ParticleBox(centre: Vector3.zero(), halfExtents: Vector3.all(1)),
          ],
        ),
      );
      system.step(1 / 60);
      final position = positionOf(system);
      expect(position.y, closeTo(1, 1e-5));
      expect(position.x, closeTo(0, 1e-9));
      expect(position.z, closeTo(0, 1e-9));
    });

    test('a point outside a box is left alone', () {
      final system = oneParticle(
        at: Vector3(5, 5, 5),
        velocity: Vector3(0, -1, 0),
        collision: CollisionModule(
          colliders: [
            ParticleBox(centre: Vector3.zero(), halfExtents: Vector3.all(1)),
          ],
        ),
      );
      system.step(1 / 60);
      expect(velocityOf(system).y, closeTo(-1, 1e-9));
    });

    test('a tilted plane bounces along its own normal', () {
      final system = oneParticle(
        at: Vector3(0, 0, 0),
        velocity: Vector3(0, -10, 0),
        collision: CollisionModule(
          colliders: [ParticlePlane(normal: Vector3(1, 1, 0), distance: 0.05)],
          restitution: 1,
          friction: 0,
        ),
      );
      system.step(1 / 60);
      // Reflecting straight down off a 45-degree wall sends it sideways.
      expect(velocityOf(system).x, greaterThan(1));
    });

    test('an empty collider list is a module that does nothing', () {
      final system = oneParticle(
        at: Vector3(0, -5, 0),
        velocity: Vector3(0, -1, 0),
        collision: CollisionModule(colliders: const []),
      );
      system.step(1 / 60);
      expect(velocityOf(system).y, closeTo(-1, 1e-9));
    });
  });

  test('collision runs after integration, not before it', () {
    // A particle one step above the floor moving fast enough to cross it must
    // be caught in the same step, not read as clear and corrected next time.
    final system = oneParticle(
      at: Vector3(0, 0.2, 0),
      velocity: Vector3(0, -30, 0),
      collision: CollisionModule.ground(restitution: 0),
    );
    system.step(1 / 60);
    expect(positionOf(system).y, greaterThanOrEqualTo(-1e-6));
  });

  test('a settled particle stays settled rather than jittering', () {
    final system = oneParticle(
      at: Vector3(0, 0.01, 0),
      velocity: Vector3(0, -1, 0),
      collision: CollisionModule.ground(
        response: ParticleCollisionResponse.stick,
      ),
    );
    for (var i = 0; i < 60; i++) {
      system.step(1 / 60);
    }
    expect(positionOf(system).y, closeTo(0, 1e-6));
    expect(velocityOf(system).length, closeTo(0, 1e-9));
  });

  group('through the document', () {
    test('a collision module round-trips with its colliders', () {
      final module = CollisionModule(
        colliders: [
          ParticlePlane(normal: Vector3(0, 1, 0), distance: -2),
          ParticleSphere(centre: Vector3(1, 2, 3), radius: 4),
          ParticleBox(centre: Vector3(-1, 0, 1), halfExtents: Vector3(2, 3, 4)),
        ],
        response: ParticleCollisionResponse.slide,
        restitution: 0.7,
        friction: 0.9,
        radius: 0.25,
        lifetimeLoss: 0.4,
      );

      final restored =
          decodeParticleModule(encodeParticleModule(module))!
              as CollisionModule;

      expect(restored.response, ParticleCollisionResponse.slide);
      expect(restored.restitution, closeTo(0.7, 1e-9));
      expect(restored.friction, closeTo(0.9, 1e-9));
      expect(restored.radius, closeTo(0.25, 1e-9));
      expect(restored.lifetimeLoss, closeTo(0.4, 1e-9));
      expect(restored.colliders, hasLength(3));

      final plane = restored.colliders[0] as ParticlePlane;
      expect(plane.normal.y, closeTo(1, 1e-9));
      expect(plane.distance, closeTo(-2, 1e-9));

      final sphere = restored.colliders[1] as ParticleSphere;
      expect(sphere.centre, Vector3(1, 2, 3));
      expect(sphere.radius, closeTo(4, 1e-9));

      final box = restored.colliders[2] as ParticleBox;
      expect(box.centre, Vector3(-1, 0, 1));
      expect(box.halfExtents, Vector3(2, 3, 4));
    });

    test('a collider naming no known shape is dropped, not guessed at', () {
      expect(
        decodeParticleCollider(MapValue({'kind': const StringValue('torus')})),
        isNull,
      );
    });
  });
}
