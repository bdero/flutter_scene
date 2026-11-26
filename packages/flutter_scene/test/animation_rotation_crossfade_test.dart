import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, AnimationProperty, BindKey, PropertyResolver;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Animation rotation(String name, String bone, double radians) => Animation(
  name: name,
  channels: [
    AnimationChannel(
      bindTarget: BindKey(nodeName: bone, property: AnimationProperty.rotation),
      resolver: PropertyResolver.makeRotationTimeline(
        [0, 1],
        List.generate(
          2,
          (_) => Quaternion.axisAngle(Vector3(0, 0, 1), radians),
        ),
      ),
    ),
  ],
);

void expectAngle(Node bone, double radians) {
  final expected = Quaternion.axisAngle(Vector3(0, 0, 1), radians);
  final actual = bone.localTransformTrs!.rotation;
  expect(actual.dot(expected).abs(), closeTo(1, 1e-6));
}

void main() {
  test('identical poses hold through a crossfade', () {
    final rig = Node(name: 'rig'), bone = Node(name: 'bone');
    rig.add(bone);
    final a = rig.createAnimationClip(rotation('a', 'bone', math.pi / 2));
    final b = rig.createAnimationClip(rotation('b', 'bone', math.pi / 2));
    for (var i = 0; i <= 20; i++) {
      a.weight = i / 20;
      b.weight = 1 - a.weight;
      rig.scenePrePass(0);
      expectAngle(bone, math.pi / 2);
    }
  });

  test('two poses blend by weight in either registration order', () {
    for (final reverse in [false, true]) {
      final rig = Node(name: 'rig'), bone = Node(name: 'bone');
      rig.add(bone);
      final angles = reverse ? [1.2, .4] : [.4, 1.2];
      final a = rig.createAnimationClip(rotation('a', 'bone', angles[0]));
      final b = rig.createAnimationClip(rotation('b', 'bone', angles[1]));
      a.weight = reverse ? .3 : .7;
      b.weight = 1 - a.weight;
      rig.scenePrePass(0);
      expectAngle(bone, .4 * .7 + 1.2 * .3);
      // Overweight clips are normalized by the player.
      a.weight = b.weight = 1;
      rig.scenePrePass(0);
      expectAngle(bone, .8);
    }
  });

  test('a partial weight keeps the rest of the bind pose', () {
    final rig = Node(name: 'rig'),
        bone = Node(name: 'bone'),
        other = Node(name: 'other');
    rig.add(bone);
    rig.add(other);
    final a = rig.createAnimationClip(rotation('a', 'bone', 1.2))..weight = .25;
    rig.createAnimationClip(rotation('b', 'other', 1.0)).weight = .75;
    rig.scenePrePass(0);
    expectAngle(bone, .3);
    expectAngle(other, .75);
    a.weight = 0;
    rig.scenePrePass(0);
    expectAngle(bone, 0);
  });
}
