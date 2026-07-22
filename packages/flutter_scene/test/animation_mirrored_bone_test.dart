/// Regression coverage for animation blending on rigs with mirrored bones
/// (issue #249). A bind pose recovered with `Matrix4.decompose` puts a
/// mirror's negative scale on X no matter which axis the source mirrored,
/// so weighted blends faded mirrored bones through zero scale (the model
/// collapsed flat mid-blend). Importers now record the authored TRS
/// decomposition on the node and blending anchors to it.
library;

import 'package:flutter_scene/scene.dart';
// The channel/resolver data model and TRS plumbing are internal; tests
// reach them directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, BindKey, DecomposedTransform, PropertyResolver;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A root node with a single child bone whose authored rest pose mirrors
/// the Y axis, the way a rig mirrors one side's bones onto the other.
(Node, Node) _rigWithMirroredBone() {
  final rig = Node(name: 'rig');
  final bone = Node(name: 'bone');
  bone.setLocalTransformTrs(
    DecomposedTransform(
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3(1, -1, 1),
    ),
  );
  rig.add(bone);
  return (rig, bone);
}

/// A 1-second animation with a single scale channel on 'bone' holding
/// [scale] for the whole timeline.
Animation _constantScaleAnimation(String name, Vector3 scale) {
  final resolver = PropertyResolver.makeScaleTimeline(
    [0.0, 1.0],
    [scale, scale],
  );
  final channel = AnimationChannel(
    bindTarget: BindKey(nodeName: 'bone'),
    resolver: resolver,
  );
  return Animation(name: name, channels: [channel]);
}

void main() {
  test('half-weight blend keeps a mirrored bone solid', () {
    final (rig, bone) = _rigWithMirroredBone();
    final clip = rig.createAnimationClip(
      _constantScaleAnimation('a', Vector3(1, -1, 1)),
    );
    clip.weight = 0.5;

    rig.scenePrePass(1 / 60);

    // Before the fix the bind pose decomposed to scale (-1, 1, 1), the
    // keyframe ratio came out (-1, -1, 1), and the half-weight lerp landed
    // on (0, 0, 1), flattening the bone.
    final scale = bone.localTransformTrs!.scale;
    expect(scale.x, closeTo(1, 1e-6));
    expect(scale.y, closeTo(-1, 1e-6));
    expect(scale.z, closeTo(1, 1e-6));
    expect(bone.localTransform.determinant(), closeTo(-1, 1e-6));
  });

  test('full-weight scale reaches the keyframe exactly', () {
    final (rig, bone) = _rigWithMirroredBone();
    rig.createAnimationClip(_constantScaleAnimation('a', Vector3(2, -2, 2)));

    rig.scenePrePass(1 / 60);

    final scale = bone.localTransformTrs!.scale;
    expect(scale.x, closeTo(2, 1e-6));
    expect(scale.y, closeTo(-2, 1e-6));
    expect(scale.z, closeTo(2, 1e-6));
  });

  test('crossfading two clips never collapses a mirrored bone', () {
    final (rig, bone) = _rigWithMirroredBone();
    final a = rig.createAnimationClip(
      _constantScaleAnimation('a', Vector3(1, -1, 1)),
    );
    final b = rig.createAnimationClip(
      _constantScaleAnimation('b', Vector3(2, -2, 2)),
    );

    for (var t = 0.0; t <= 1.0; t += 0.1) {
      a.weight = 1.0 - t;
      b.weight = t;
      rig.scenePrePass(1 / 60);
      expect(
        bone.localTransform.determinant(),
        lessThan(-0.5),
        reason: 'bone flattened at crossfade t=$t',
      );
    }
  });

  test('cloned nodes keep the authored decomposition', () {
    final (rig, _) = _rigWithMirroredBone();
    final clonedBone = rig.clone().getChildByName('bone')!;
    final scale = clonedBone.localTransformTrs!.scale;
    expect(scale.y, closeTo(-1, 1e-6));
  });

  test('assigning a raw matrix clears the authored decomposition', () {
    final (_, bone) = _rigWithMirroredBone();
    bone.localTransform = Matrix4.identity();
    expect(bone.localTransformTrs, isNull);
  });
}
