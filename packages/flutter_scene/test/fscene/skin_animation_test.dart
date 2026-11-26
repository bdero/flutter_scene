// Covers realizing skins and animations onto a live graph. GPU-free: the
// nodes carry no meshes, so no geometry/material is built, but skins bind to
// their joint nodes and animations parse onto the root.

import 'dart:typed_data';

import 'package:flutter_scene/src/animation.dart'
    as engine
    show MorphWeightsTimelineResolver;
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _floatBytes(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

const _identity = [
  1.0, 0.0, 0.0, 0.0, //
  0.0, 1.0, 0.0, 0.0, //
  0.0, 0.0, 1.0, 0.0, //
  0.0, 0.0, 0.0, 1.0, //
];

void main() {
  test('realizes a skin and binds its joint nodes', () {
    final doc = SceneDocument();
    final jointA = doc.createNode(name: 'jointA');
    final jointB = doc.createNode(name: 'jointB');
    final ibm = doc.addPayload(
      PayloadSpec(
        doc.newId(),
        encoding: PayloadEncoding.matrices,
        bytes: _floatBytes([..._identity, ..._identity]),
      ),
    );
    final skin = doc.addSkin(
      SkinSpec(
        doc.newId(),
        joints: [jointA.id, jointB.id],
        inverseBindMatrices: ibm.id,
      ),
    );
    final mesh = doc.createNode(name: 'skinnedMesh', root: true);
    mesh.skin = skin.id;
    mesh.children.addAll([jointA.id, jointB.id]);

    final root = realizeScene(doc);
    final skinnedNode = root.getChildByName('skinnedMesh')!;

    expect(skinnedNode.skin, isNotNull);
    expect(skinnedNode.skin!.joints, hasLength(2));
    expect(skinnedNode.skin!.joints.map((j) => j?.name), ['jointA', 'jointB']);
    expect(skinnedNode.skin!.inverseBindMatrices, hasLength(2));
    expect(root.getChildByName('jointA')!.isJoint, isTrue);
  });

  test('realizes an animation onto the root', () {
    final doc = SceneDocument();
    final bone = doc.createNode(name: 'Bone', root: true);
    final timeline = doc.addPayload(
      PayloadSpec(
        doc.newId(),
        encoding: PayloadEncoding.floats,
        bytes: _floatBytes([0.0, 1.0]),
      ),
    );
    final keyframes = doc.addPayload(
      PayloadSpec(
        doc.newId(),
        encoding: PayloadEncoding.floats,
        // Two vec3 translation keyframes.
        bytes: _floatBytes([0, 0, 0, 1, 2, 3]),
      ),
    );
    doc.addAnimation(
      AnimationSpec(
        doc.newId(),
        name: 'Wiggle',
        channels: [
          AnimationChannelSpec(
            target: bone.id,
            targetName: 'Bone',
            property: AnimationProperty.translation,
            timeline: timeline.id,
            keyframes: keyframes.id,
          ),
        ],
      ),
    );

    final root = realizeScene(doc);
    expect(root.parsedAnimations, hasLength(1));
    final animation = root.findAnimationByName('Wiggle');
    expect(animation, isNotNull);
    // A clip can be instantiated and bound without error.
    expect(root.createAnimationClip(animation!), isNotNull);
  });

  SceneDocument blinkDocument({required bool withTangents}) {
    final doc = SceneDocument();
    final face = doc.createNode(name: 'Face', root: true);
    LocalId floats(List<double> values) => doc
        .addPayload(
          PayloadSpec(
            doc.newId(),
            encoding: PayloadEncoding.floats,
            bytes: _floatBytes(values),
          ),
        )
        .id;
    doc.addAnimation(
      AnimationSpec(
        doc.newId(),
        name: 'Blink',
        channels: [
          AnimationChannelSpec(
            target: face.id,
            targetName: 'Face',
            property: AnimationProperty.weights,
            timeline: floats([0.0, 1.0]),
            // Two keyframes of two morph target weights.
            keyframes: floats([0, 1, 1, 0]),
            interpolation: AnimationInterpolation.cubicSpline,
            inTangents: withTangents ? floats([0, 0, 4, 5]) : null,
            outTangents: withTangents ? floats([2, 3, 0, 0]) : null,
          ),
        ],
      ),
    );
    return doc;
  }

  engine.MorphWeightsTimelineResolver blink(SceneDocument doc) =>
      realizeScene(doc).parsedAnimations.single.channels.single.resolver
          as engine.MorphWeightsTimelineResolver;

  test('reads a cubic spline channel\'s tangents from their payloads', () {
    final resolver = blink(blinkDocument(withTangents: true));
    expect(resolver.targetCount, 2);
    expect(resolver.interpolation, AnimationInterpolation.cubicSpline);
    expect(resolver.values, [0, 1, 1, 0]);
    expect(resolver.inTangents, [0, 0, 4, 5]);
    expect(resolver.outTangents, [2, 3, 0, 0]);
  });

  test('plays a cubic spline channel without tangents as linear', () {
    final resolver = blink(blinkDocument(withTangents: false));
    expect(resolver.interpolation, AnimationInterpolation.linear);
    expect(resolver.values, [0, 1, 1, 0]);
    expect(resolver.inTangents, isNull);
  });
}
