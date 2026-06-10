// Covers the scene-structure hot-reload patch: applying a diff to a live node
// graph in place. Uses component-less nodes and a directional light (both
// realize without the GPU), so the structural patching is exercised GPU-free.
// Skins and animations are also GPU-free.

import 'dart:typed_data';

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/reload/reload.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test(
    'patches added, removed, reparented, and transform-changed nodes',
    () async {
      const r = LocalId(1, 1);
      const a = LocalId(1, 2);
      const b = LocalId(1, 3);
      const c = LocalId(1, 4);
      const d = LocalId(1, 5);

      final oldDoc = SceneDocument();
      oldDoc.addNode(NodeSpec(id: r, name: 'r', children: [a, b]), root: true);
      oldDoc.addNode(NodeSpec(id: a, name: 'a'));
      oldDoc.addNode(NodeSpec(id: b, name: 'b', children: [c]));
      oldDoc.addNode(NodeSpec(id: c, name: 'c'));

      final liveRoot = realizeScene(oldDoc);
      final liveR = liveRoot.children.single;
      final liveC = liveR.getChildByName('c')!; // under b

      // Remove a; add d under r; move c from b to r; move b up.
      final newDoc = SceneDocument();
      newDoc.addNode(
        NodeSpec(id: r, name: 'r', children: [b, d, c]),
        root: true,
      );
      newDoc.addNode(
        NodeSpec(
          id: b,
          name: 'b',
          transform: TrsTransform(translation: Vector3(0, 5, 0)),
        ),
      );
      newDoc.addNode(NodeSpec(id: c, name: 'c'));
      newDoc.addNode(NodeSpec(id: d, name: 'd'));

      await reloadScene(liveRoot, oldDoc, newDoc);

      expect(liveRoot.getChildByName('a'), isNull); // removed
      expect(liveR.children.map((n) => n.name).toSet(), {'b', 'd', 'c'});

      final liveB = liveR.children.firstWhere((n) => n.name == 'b');
      expect(liveB.children, isEmpty); // c moved out
      expect(liveB.localTransform.getTranslation(), Vector3(0, 5, 0));

      // c kept its identity, now parented under r.
      expect(liveR.children.firstWhere((n) => n.name == 'c'), same(liveC));
      expect(liveC.parent, same(liveR));
    },
  );

  test('rebuilds a changed component, keeping node identity', () async {
    const sunId = LocalId(2, 1);
    ComponentSpec light(double intensity) => ComponentSpec(
      'directionalLight',
      properties: {'intensity': DoubleValue(intensity)},
    );

    final oldDoc = SceneDocument();
    oldDoc.addNode(
      NodeSpec(id: sunId, name: 'sun', components: [light(3.0)]),
      root: true,
    );
    final liveRoot = realizeScene(oldDoc);
    final sun = liveRoot.children.single;
    expect(sun.getComponent<DirectionalLightComponent>()!.light.intensity, 3.0);

    final newDoc = SceneDocument();
    newDoc.addNode(
      NodeSpec(id: sunId, name: 'sun', components: [light(7.0)]),
      root: true,
    );
    await reloadScene(liveRoot, oldDoc, newDoc);

    expect(liveRoot.children.single, same(sun)); // identity preserved
    expect(sun.getComponent<DirectionalLightComponent>()!.light.intensity, 7.0);
  });

  test('rebuilds a changed skin, keeping joint node identity', () async {
    final oldDoc = _skinned();
    final liveRoot = realizeScene(oldDoc);
    final skinned = liveRoot.getChildByName('skinned')!;
    final joint = liveRoot.getChildByName('joint')!;
    expect(skinned.skin, isNotNull);
    expect(
      skinned.skin!.inverseBindMatrices.single.getTranslation(),
      Vector3.zero(),
    );

    final newDoc = _skinned(ibmTranslation: Vector3(0, 2, 0));
    await reloadScene(liveRoot, oldDoc, newDoc);

    expect(liveRoot.getChildByName('joint'), same(joint));
    expect(skinned.skin!.joints.single, same(joint));
    expect(
      skinned.skin!.inverseBindMatrices.single.getTranslation(),
      Vector3(0, 2, 0),
    );
  });

  test('binds the skin of a node added by reload', () async {
    final oldDoc = SceneDocument();
    oldDoc.addNode(NodeSpec(id: _joint, name: 'joint'), root: true);

    final liveRoot = realizeScene(oldDoc);
    final joint = liveRoot.getChildByName('joint')!;

    final newDoc = _skinned();
    await reloadScene(liveRoot, oldDoc, newDoc);

    final skinned = liveRoot.getChildByName('skinned')!;
    expect(skinned.skin, isNotNull);
    expect(skinned.skin!.joints.single, same(joint));
    expect(joint.isJoint, isTrue);
  });

  test('removes the skin of a node no longer skinned', () async {
    final oldDoc = _skinned();
    final liveRoot = realizeScene(oldDoc);
    final skinned = liveRoot.getChildByName('skinned')!;
    expect(skinned.skin, isNotNull);

    final newDoc = _skinned();
    newDoc.node(_skinnedNode)!.skin = null;
    await reloadScene(liveRoot, oldDoc, newDoc);

    expect(skinned.skin, isNull);
  });

  test('re-binds a changed animation, keeping clip playback state', () async {
    final oldDoc = _skinned();
    final liveRoot = realizeScene(oldDoc);
    final joint = liveRoot.getChildByName('joint')!;

    final clip = liveRoot.createAnimationClip(
      liveRoot.findAnimationByName('move')!,
    );
    clip.play();
    clip.advance(0.5);
    expect(clip.playbackTime, 0.5);
    liveRoot.scenePrePass(0);
    expect(joint.localTransform.getTranslation().y, closeTo(0.5, 1e-6));

    // Double the keyframe amplitude; the clip keeps its name, head, and
    // playing state, and the next tick evaluates the new curve.
    final newDoc = _skinned(keyframeY: 2.0);
    await reloadScene(liveRoot, oldDoc, newDoc);

    expect(clip.playing, isTrue);
    expect(clip.playbackTime, 0.5);
    liveRoot.scenePrePass(0);
    expect(joint.localTransform.getTranslation().y, closeTo(1.0, 1e-6));
    expect(liveRoot.findAnimationByName('move'), isNotNull);
  });

  test('keeps animation identity when nothing changed', () async {
    final oldDoc = _skinned();
    final liveRoot = realizeScene(oldDoc);
    final animation = liveRoot.findAnimationByName('move')!;

    final newDoc = _skinned();
    newDoc.node(_skinnedNode)!.layers = 2;
    await reloadScene(liveRoot, oldDoc, newDoc);

    expect(liveRoot.findAnimationByName('move'), same(animation));
  });
}

const _skinnedNode = LocalId(7, 1);
const _joint = LocalId(7, 2);
const _skin = LocalId(7, 3);
const _ibm = LocalId(7, 4);
const _anim = LocalId(7, 5);
const _times = LocalId(7, 6);
const _keys = LocalId(7, 7);

Uint8List _floatBytes(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

// skinned (root, skin over [joint]) -> joint, plus a 'move' animation
// translating joint from y=0 to y=keyframeY over one second.
SceneDocument _skinned({Vector3? ibmTranslation, double keyframeY = 1.0}) {
  final doc = SceneDocument();
  doc.addNode(
    NodeSpec(
      id: _skinnedNode,
      name: 'skinned',
      children: [_joint],
      skin: _skin,
    ),
    root: true,
  );
  doc.addNode(NodeSpec(id: _joint, name: 'joint'));
  final ibm = Matrix4.identity()
    ..setTranslation(ibmTranslation ?? Vector3.zero());
  doc.addPayload(
    PayloadSpec(
      _ibm,
      encoding: PayloadEncoding.matrices,
      bytes: _floatBytes(ibm.storage.toList()),
    ),
  );
  doc.addSkin(SkinSpec(_skin, joints: [_joint], inverseBindMatrices: _ibm));
  doc.addPayload(
    PayloadSpec(
      _times,
      encoding: PayloadEncoding.floats,
      bytes: _floatBytes([0, 1]),
    ),
  );
  doc.addPayload(
    PayloadSpec(
      _keys,
      encoding: PayloadEncoding.floats,
      bytes: _floatBytes([0, 0, 0, 0, keyframeY, 0]),
    ),
  );
  doc.addAnimation(
    AnimationSpec(
      _anim,
      name: 'move',
      channels: [
        AnimationChannelSpec(
          target: _joint,
          targetName: 'joint',
          property: AnimationProperty.translation,
          timeline: _times,
          keyframes: _keys,
        ),
      ],
    ),
  );
  return doc;
}
