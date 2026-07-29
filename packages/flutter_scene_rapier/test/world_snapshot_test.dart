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
    final snapshot = world.snapshot();
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

  test('restore rejects malformed bytes', () async {
    await RapierWorld.ensureInitialized();
    final world = RapierWorld();
    expect(world.restore(Uint8List.fromList([1, 2, 3])), isFalse);
    world.dispose();
  });
}
