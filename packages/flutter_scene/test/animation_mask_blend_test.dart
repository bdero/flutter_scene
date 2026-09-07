/// What a mask is for: two clips playing at once, each moving its own half of
/// a rig. The state machine decides weights; this covers the part that puts
/// them on the skeleton, which is where a mask either works or quietly does
/// nothing.
library;

import 'package:flutter_scene/scene.dart';
// The channel/resolver data model is internal; tests reach it directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, BindKey, PropertyResolver;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A rig with an upper half under `spine` and a lower half under `leg`.
Node rig() {
  final hips = Node(name: 'hips');
  final spine = Node(name: 'spine');
  final hand = Node(name: 'hand');
  final leg = Node(name: 'leg');
  spine.add(hand);
  hips
    ..add(spine)
    ..add(leg);
  return hips;
}

/// An animation that moves every named node to [to] over a second.
Animation moveAll(String name, List<String> nodes, Vector3 to) => Animation(
  name: name,
  channels: [
    for (final node in nodes)
      AnimationChannel(
        bindTarget: BindKey(nodeName: node),
        resolver: PropertyResolver.makeTranslationTimeline(
          [0.0, 1.0],
          [Vector3.zero(), to],
        ),
      ),
  ],
);

const _bones = ['hips', 'spine', 'hand', 'leg'];

void main() {
  test('a masked clip moves only what the mask covers', () {
    final root = rig();
    final clip =
        root.createAnimationClip(moveAll('aim', _bones, Vector3(0, 10, 0)))
          ..mask = AnimationMask(const ['spine'])
          ..weight = 1
          ..seek(1)
          ..play();
    root.scenePrePass(0);

    expect(root.getChildByName('spine')!.position.y, closeTo(10, 1e-5));
    expect(root.getChildByName('hand')!.position.y, closeTo(10, 1e-5));
    expect(root.getChildByName('leg')!.position.y, closeTo(0, 1e-5));
    expect(clip.mask, isNotNull);
  });

  test('two masked clips each keep their own half', () {
    // The whole point: an aim on the spine over a run on the legs, both at
    // full weight, neither halving the other.
    final root = rig();
    root.createAnimationClip(moveAll('run', _bones, Vector3(0, 4, 0)))
      ..mask = AnimationMask(const ['leg'])
      ..weight = 1
      ..seek(1)
      ..play();
    root.createAnimationClip(moveAll('aim', _bones, Vector3(0, 9, 0)))
      ..mask = AnimationMask(const ['spine'])
      ..weight = 1
      ..seek(1)
      ..play();
    root.scenePrePass(0);

    expect(root.getChildByName('leg')!.position.y, closeTo(4, 1e-5));
    expect(root.getChildByName('spine')!.position.y, closeTo(9, 1e-5));
    expect(
      root.getChildByName('hand')!.position.y,
      closeTo(9, 1e-5),
      reason: 'the mask covers the subtree, so the hand follows the spine',
    );
  });

  test('normalization is per node, so a mask does not dilute a neighbour', () {
    // Both clips drive the spine, so it is over-driven and normalizes; the
    // leg is driven by one clip only and must reach its keyframe exactly.
    final root = rig();
    root.createAnimationClip(moveAll('run', _bones, Vector3(0, 4, 0)))
      ..weight = 1
      ..seek(1)
      ..play();
    root.createAnimationClip(moveAll('aim', _bones, Vector3(0, 8, 0)))
      ..mask = AnimationMask(const ['spine'])
      ..weight = 1
      ..seek(1)
      ..play();
    root.scenePrePass(0);

    expect(
      root.getChildByName('leg')!.position.y,
      closeTo(4, 1e-5),
      reason: 'only the run touches the leg, so it is not scaled down',
    );
    expect(
      root.getChildByName('spine')!.position.y,
      closeTo(6, 1e-5),
      reason: 'two clips at full weight on one node average',
    );
  });

  test('a partial mask blends rather than cutting', () {
    final root = rig();
    root.createAnimationClip(moveAll('aim', _bones, Vector3(0, 10, 0)))
      ..mask = AnimationMask(const ['spine'], outsideWeight: 0.25)
      ..weight = 1
      ..seek(1)
      ..play();
    root.scenePrePass(0);

    expect(root.getChildByName('spine')!.position.y, closeTo(10, 1e-5));
    expect(root.getChildByName('leg')!.position.y, closeTo(2.5, 1e-5));
  });

  test('clearing the mask lets the clip move everything again', () {
    final root = rig();
    final clip =
        root.createAnimationClip(moveAll('aim', _bones, Vector3(0, 10, 0)))
          ..mask = AnimationMask(const ['spine'])
          ..weight = 1
          ..seek(1)
          ..play();
    root.scenePrePass(0);
    expect(root.getChildByName('leg')!.position.y, closeTo(0, 1e-5));

    clip.mask = null;
    root.scenePrePass(0);
    expect(root.getChildByName('leg')!.position.y, closeTo(10, 1e-5));
  });

  test('an unmasked clip is unchanged by all of this', () {
    // A node driven by one clip through three channels must not read as
    // three times over-driven and normalize itself down to a third.
    final root = rig();
    root.createAnimationClip(moveAll('run', _bones, Vector3(0, 6, 0)))
      ..weight = 1
      ..seek(1)
      ..play();
    root.scenePrePass(0);

    for (final bone in _bones) {
      final node = bone == 'hips' ? root : root.getChildByName(bone)!;
      expect(node.position.y, closeTo(6, 1e-5), reason: bone);
    }
  });

  test('two clips of one animation can coexist under different keys', () {
    // What a layered animator needs: the same animation on two layers, each
    // with its own mask and weight.
    final root = rig();
    final animation = moveAll('aim', _bones, Vector3(0, 8, 0));
    root.createAnimationClip(animation, key: 'base:aim')
      ..mask = AnimationMask(const ['leg'])
      ..weight = 1
      ..seek(1)
      ..play();
    root.createAnimationClip(animation, key: 'upper:aim')
      ..mask = AnimationMask(const ['spine'])
      ..weight = 1
      ..seek(1)
      ..play();
    root.scenePrePass(0);

    expect(root.getChildByName('leg')!.position.y, closeTo(8, 1e-5));
    expect(root.getChildByName('spine')!.position.y, closeTo(8, 1e-5));
    expect(
      root.getChildByName('hips')?.position.y ?? root.position.y,
      closeTo(0, 1e-5),
      reason: 'neither mask covers the hips',
    );
  });

  test('registering the same animation twice still replaces by default', () {
    // Two registrations under the same key are one clip, so the pose is the
    // keyframe rather than twice it normalized back down.
    final root = rig();
    final animation = moveAll('aim', _bones, Vector3(0, 8, 0));
    root.createAnimationClip(animation)
      ..weight = 1
      ..seek(1)
      ..play();
    root.createAnimationClip(animation)
      ..weight = 1
      ..seek(1)
      ..play();
    root.scenePrePass(0);
    expect(root.getChildByName('leg')!.position.y, closeTo(8, 1e-5));
  });
}
