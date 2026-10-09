// Covers the deferred joint upload: a skin computes its matrices into a ring
// slot on each tick, uploads only when the scene flushes it, and reuses an
// unflushed slot so the previous slot is always one the GPU was given.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

void main() {
  test('an unflushed slot is reused and a flushed one advances', () {
    if (!gpuAvailable()) return;
    final skin = Skin();
    skin.joints.add(Node());
    skin.inverseBindMatrices.add(Matrix4.identity());

    final first = skin.getJointsTexture();
    // A held frame flushes nothing, so the next tick writes the same slot.
    expect(skin.getJointsTexture(), same(first));

    skin.flushJointsUpload();
    final second = skin.getJointsTexture();
    expect(second, isNot(same(first)));
    expect(skin.getPreviousJointsTexture(), same(first));
  });
}
