// Covers realizing skins and animations onto a live graph. GPU-free: the
// nodes carry no meshes, so no geometry/material is built, but skins bind to
// their joint nodes and animations parse onto the root.

import 'dart:typed_data';

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

  group('channel interpolation', () {
    /// Realizes a one-second translation channel from the origin to x = 10
    /// under [interpolation], and returns the node's x at [time].
    double xAt({
      required double time,
      AnimationInterpolation? interpolation,
      List<double>? inTangents,
      List<double>? outTangents,
    }) {
      final doc = SceneDocument();
      final bone = doc.createNode(name: 'Bone', root: true);
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
          name: 'Slide',
          channels: [
            AnimationChannelSpec(
              target: bone.id,
              targetName: 'Bone',
              property: AnimationProperty.translation,
              timeline: floats([0.0, 1.0]),
              keyframes: floats([0, 0, 0, 10, 0, 0]),
              interpolation: interpolation,
              inTangents: inTangents == null ? null : floats(inTangents),
              outTangents: outTangents == null ? null : floats(outTangents),
            ),
          ],
        ),
      );

      final root = realizeScene(doc);
      root.createAnimationClip(root.findAnimationByName('Slide')!)
        ..weight = 1
        ..seek(time)
        ..play();
      root.scenePrePass(0);
      return root.getChildByName('Bone')!.position.x;
    }

    test('a linear channel interpolates between its keys', () {
      expect(xAt(time: 0.5), closeTo(5.0, 1e-5));
    });

    test('a step channel holds the previous key', () {
      expect(
        xAt(time: 0.5, interpolation: AnimationInterpolation.step),
        closeTo(0.0, 1e-5),
      );
    });

    test('a cubic channel eases along its tangents', () {
      // Flat tangents give smoothstep, which agrees with linear at the
      // midpoint and differs everywhere else.
      expect(
        xAt(
          time: 0.25,
          interpolation: AnimationInterpolation.cubic,
          inTangents: [0, 0, 0, 0, 0, 0],
          outTangents: [0, 0, 0, 0, 0, 0],
        ),
        closeTo(1.5625, 1e-5),
      );
    });

    test('a cubic channel missing its tangents falls back to linear', () {
      // A hand-edited or partially merged document can name cubic without
      // carrying the chunks. Realizing must still produce a usable timeline
      // rather than throwing part-way through building the scene.
      expect(
        xAt(time: 0.5, interpolation: AnimationInterpolation.cubic),
        closeTo(5.0, 1e-5),
      );
    });
  });
}
