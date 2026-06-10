// Covers the scene-structure diff: the node-id-keyed comparison of two
// documents that scene hot reload patches from. GPU-free.

import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/reload/diff.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const _a = LocalId(1, 1);
const _b = LocalId(1, 2);
const _c = LocalId(1, 3);
const _mat1 = LocalId(9, 1);
const _mat2 = LocalId(9, 2);

ComponentSpec _mesh(LocalId material) =>
    ComponentSpec('mesh', properties: {'material': ResourceRefValue(material)});

// Base scene: a (root) -> b, where b has a mesh referencing mat1.
SceneDocument _base() {
  final doc = SceneDocument();
  doc.addResource(MaterialResource(_mat1, type: 'physicallyBased'));
  doc.addNode(NodeSpec(id: _a, name: 'a', children: [_b]), root: true);
  doc.addNode(NodeSpec(id: _b, name: 'b', components: [_mesh(_mat1)]));
  return doc;
}

NodeChange _change(SceneDiff diff, LocalId id) =>
    diff.changed.firstWhere((c) => c.id == id);

void main() {
  test('identical documents diff to nothing', () {
    expect(diffScene(_base(), _base()).isEmpty, isTrue);
  });

  test('detects an added node', () {
    final next = _base();
    next.node(_a)!.children.add(_c);
    next.addNode(NodeSpec(id: _c, name: 'c'));

    final diff = diffScene(_base(), next);
    expect(diff.added, [_c]);
    expect(diff.removed, isEmpty);
  });

  test('detects a removed node', () {
    final next = _base();
    next.nodes.remove(_b);
    next.node(_a)!.children.remove(_b);

    final diff = diffScene(_base(), next);
    expect(diff.removed, [_b]);
    expect(diff.added, isEmpty);
  });

  test('detects a transform change', () {
    final next = _base();
    next.node(_a)!.transform = TrsTransform(translation: Vector3(1, 2, 3));

    final diff = diffScene(_base(), next);
    expect(_change(diff, _a).transform, isTrue);
    expect(_change(diff, _a).components, isFalse);
  });

  test('detects name and layer changes', () {
    final next = _base();
    next.node(_b)!
      ..name = 'renamed'
      ..layers = 4;

    final change = _change(diffScene(_base(), next), _b);
    expect(change.name, isTrue);
    expect(change.layers, isTrue);
  });

  test('detects a component property change', () {
    final next = _base();
    next.node(_b)!.components
      ..clear()
      ..add(_mesh(_mat2));

    final change = _change(diffScene(_base(), next), _b);
    expect(change.components, isTrue);
    expect(change.transform, isFalse);
  });

  test('detects a reparent', () {
    final next = _base();
    next.node(_a)!.children.remove(_b);
    next.roots.add(_b);

    final change = _change(diffScene(_base(), next), _b);
    expect(change.reparented, isTrue);
  });

  group('skins and animations', () {
    test('identical skinned documents diff to nothing', () {
      final diff = diffScene(_skinned(), _skinned());
      expect(diff.isEmpty, isTrue);
      expect(diff.animationsChanged, isFalse);
    });

    test('detects an inverse-bind-matrix payload change', () {
      final next = _skinned(ibmScale: 2.0);
      final change = _change(diffScene(_skinned(), next), _a);
      expect(change.skin, isTrue);
    });

    test('detects a joint-list change', () {
      final next = _skinned();
      next.skins[_skin]!.joints.add(_a);
      final change = _change(diffScene(_skinned(), next), _a);
      expect(change.skin, isTrue);
    });

    test('marks a skin stale when a joint node is recreated', () {
      // The joint b gets a new id (= a new live node), so even though the
      // skinned node a's spec only changes through the skin's joint list, the
      // live binding must be rebuilt.
      final next = _skinned();
      next.nodes.remove(_b);
      next.node(_a)!.children.remove(_b);
      next.addNode(NodeSpec(id: _c, name: 'b'));
      next.node(_a)!.children.add(_c);
      next.skins[_skin]!.joints
        ..clear()
        ..add(_c);

      final change = _change(diffScene(_skinned(), next), _a);
      expect(change.skin, isTrue);
    });

    test('detects a keyframe payload change', () {
      final next = _skinned(keyframeScale: 3.0);
      final diff = diffScene(_skinned(), next);
      expect(diff.animationsChanged, isTrue);
      expect(diff.changed, isEmpty);
    });

    test('detects an added animation', () {
      final next = _skinned();
      next.addAnimation(AnimationSpec(const LocalId(8, 9), name: 'extra'));
      expect(diffScene(_skinned(), next).animationsChanged, isTrue);
    });

    test('rebinds animations when a channel target is renamed', () {
      final next = _skinned();
      next.node(_b)!.name = 'renamed';
      expect(diffScene(_skinned(), next).animationsChanged, isTrue);
    });

    test('rebinds animations when a channel target rest transform moves', () {
      final next = _skinned();
      next.node(_b)!.transform = TrsTransform(translation: Vector3(0, 1, 0));
      expect(diffScene(_skinned(), next).animationsChanged, isTrue);
    });

    test('keeps animations bound across unrelated changes', () {
      final next = _skinned();
      next.node(_a)!.layers = 2;
      expect(diffScene(_skinned(), next).animationsChanged, isFalse);
    });
  });
}

const _skin = LocalId(8, 1);
const _ibm = LocalId(8, 2);
const _anim = LocalId(8, 3);
const _times = LocalId(8, 4);
const _keys = LocalId(8, 5);

Uint8List _floatBytes(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

// Skinned scene: a (root, skinned by _skin with joint b) -> b, plus one
// animation translating b.
SceneDocument _skinned({double ibmScale = 1.0, double keyframeScale = 1.0}) {
  final doc = SceneDocument();
  doc.addNode(
    NodeSpec(id: _a, name: 'a', children: [_b], skin: _skin),
    root: true,
  );
  doc.addNode(NodeSpec(id: _b, name: 'b'));
  doc.addPayload(
    PayloadSpec(
      _ibm,
      encoding: PayloadEncoding.matrices,
      bytes: _floatBytes(
        Matrix4.identity()
            .scaledByDouble(ibmScale, ibmScale, ibmScale, 1)
            .storage
            .toList(),
      ),
    ),
  );
  doc.addSkin(SkinSpec(_skin, joints: [_b], inverseBindMatrices: _ibm));
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
      bytes: _floatBytes([0, 0, 0, 0, keyframeScale, 0]),
    ),
  );
  doc.addAnimation(
    AnimationSpec(
      _anim,
      name: 'move',
      channels: [
        AnimationChannelSpec(
          target: _b,
          targetName: 'b',
          property: AnimationProperty.translation,
          timeline: _times,
          keyframes: _keys,
        ),
      ],
    ),
  );
  return doc;
}
