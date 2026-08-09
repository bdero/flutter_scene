// World snapshot/restore round-trip through the native FFI. Bodies run
// without colliders, so an explicit additional mass gives gravity something
// to act on.

import 'dart:typed_data';

import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene/physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('snapshot restores a body and resimulates identically', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();
    expect(world.supportsSnapshot, isTrue);

    final body = world.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );

    // Capture the world at rest, then let the body fall for a second.
    // Snapshot membership metadata travels with the bytes, not a Dart object
    // identity, so rollback callers may copy or serialize the snapshot.
    final snapshot = Uint8List.fromList(world.snapshot());
    expect(snapshot, isNotEmpty);

    for (var i = 0; i < 60; i++) {
      world.step(1 / 60);
    }
    final fallenY = world.readBodyPose(body).$1.y;
    expect(fallenY, lessThan(9)); // it dropped

    // Restore rewinds the body to the snapshot pose, handle still valid.
    expect(world.restore(snapshot), isTrue);
    expect(world.readBodyPose(body).$1.y, closeTo(10, 0.001));

    // And the restored world integrates forward to the same place (rollback
    // resim, the reconciliation property).
    for (var i = 0; i < 60; i++) {
      world.step(1 / 60);
    }
    expect(world.readBodyPose(body).$1.y, closeTo(fallenY, 0.001));

    world.dispose();
  });

  test('rollback correction replays deterministically', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();

    final body = world.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );

    // Teleport adopts a pose immediately.
    world.setBodyPose(body, Vector3(1, 10, 0), Quaternion.identity());
    expect(world.readBodyPose(body).$1.x, closeTo(1, 1e-6));

    // Predict ten ticks under a constant push, snapshotting each tick.
    const dt = 1 / 30.0;
    final snapshots = <int, Uint8List>{};
    for (var tick = 1; tick <= 10; tick++) {
      world.applyImpulse(body, Vector3(0.5, 0, 0));
      world.step(dt);
      snapshots[tick] = world.snapshot();
    }
    final predicted = world.readBodyPose(body).$1.clone();

    // The authority disagrees about tick 5. Correct by restoring the tick-5
    // snapshot, adopting the authoritative pose and velocity, and replaying
    // the same pending inputs, the client misprediction-rollback loop.
    Vector3 correctAndReplay() {
      expect(world.restore(snapshots[5]!), isTrue);
      final (position, rotation) = world.readBodyPose(body);
      world.setBodyPose(body, position + Vector3(0, 0, 2), rotation);
      world.setBodyLinearVelocity(body, world.readBodyLinearVelocity(body));
      for (var tick = 6; tick <= 10; tick++) {
        world.applyImpulse(body, Vector3(0.5, 0, 0));
        world.step(dt);
      }
      return world.readBodyPose(body).$1.clone();
    }

    final first = correctAndReplay();
    final second = correctAndReplay();

    // The correction shifted the outcome, and the replay is repeatable.
    expect(first.z - predicted.z, closeTo(2, 0.05));
    expect(first.x, closeTo(predicted.x, 0.05));
    expect((first - second).length, lessThan(1e-9));

    world.dispose();
  });

  test('restore rejects malformed bytes', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();
    expect(world.restore(Uint8List.fromList([1, 2, 3])), isFalse);
    world.dispose();
  });

  test('restore rejects a bare native snapshot', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();
    // Snapshots carry a membership envelope, so payloads written before it
    // existed are not restorable.
    final envelope = world.snapshot();
    expect(world.restore(Uint8List.sublistView(envelope, 12)), isFalse);
    world.dispose();
  });

  test('restore drops bodies created after the snapshot', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();

    final kept = SimplePoseTarget(translation: Vector3(0, 10, 0));
    world.createBody(target: kept, type: BodyType.dynamic_, additionalMass: 1);
    final snapshot = world.snapshot();

    final rewound = SimplePoseTarget(translation: Vector3(1, 10, 0));
    world.createBody(
      target: rewound,
      type: BodyType.dynamic_,
      additionalMass: 1,
    );

    expect(world.restore(snapshot), isTrue);

    // The restore rewound the world past the second body, so only the body
    // the snapshot captured is still driven.
    world.step(1 / 60);
    world.interpolatePoses(1);
    expect(kept.worldTranslation.y, lessThan(10));
    expect(rewound.worldTranslation.y, closeTo(10, 1e-9));
    world.dispose();
  });

  test('restore removes bodies destroyed after the snapshot', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();

    final body = world.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.fixed,
      additionalMass: 0,
    );
    world.createColliders(body, const SphereShape(radius: 1));
    world.step(1 / 60);
    expect(world.overlapSphere(Vector3(0, 10, 0), 0.5), isNotEmpty);

    final snapshot = world.snapshot();
    world.destroyBody(body);
    world.step(1 / 60);
    expect(world.overlapSphere(Vector3(0, 10, 0), 0.5), isEmpty);

    // Restoring brings the body back natively, but nothing owns its pose
    // any more, so it does not survive the reconcile as a ghost.
    expect(world.restore(snapshot), isTrue);
    world.step(1 / 60);
    expect(world.overlapSphere(Vector3(0, 10, 0), 0.5), isEmpty);
    world.dispose();
  });

  test('handles survive the envelope past the 32-bit lane', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();

    // Recycling an arena slot bumps its generation, which lives in the
    // handle's high 32 bits.
    final first = world.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );
    world.destroyBody(first);
    final recycled = world.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );
    expect(recycled, greaterThan(0xFFFFFFFF));

    // A membership-preserving restore round-trips that handle.
    final snapshot = world.snapshot();
    for (var i = 0; i < 60; i++) {
      world.step(1 / 60);
    }
    expect(world.restore(snapshot), isTrue);
    world.step(1 / 60);
    world.interpolatePoses(1);
    expect(world.readBodyPose(recycled).$1.y, closeTo(10, 0.01));
    world.dispose();
  });
}
