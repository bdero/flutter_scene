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

  test('restore rejects a snapshot after a body is created', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();

    world.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );
    final snapshot = world.snapshot();
    final createdAfterSnapshot = world.createBody(
      target: SimplePoseTarget(translation: Vector3(1, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );

    expect(world.restore(snapshot), isFalse);

    // The native world was not rewound, so the newly-created Dart body
    // remains valid for subsequent simulation.
    world.step(1 / 60);
    expect(world.readBodyPose(createdAfterSnapshot).$1.y, lessThan(10));
    world.dispose();
  });

  test('restore rejects a snapshot after a body is destroyed', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();

    final body = world.createBody(
      target: SimplePoseTarget(translation: Vector3(0, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );
    final snapshot = world.snapshot();
    world.destroyBody(body);

    expect(world.restore(snapshot), isFalse);

    // The destroyed body is not silently resurrected in native state.
    final replacement = world.createBody(
      target: SimplePoseTarget(translation: Vector3(1, 10, 0)),
      type: BodyType.dynamic_,
      additionalMass: 1,
    );
    world.step(1 / 60);
    expect(world.readBodyPose(replacement).$1.y, lessThan(10));
    world.dispose();
  });
}
