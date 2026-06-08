// Covers the scene-structure diff: the node-id-keyed comparison of two
// documents that scene hot reload patches from. GPU-free.

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
}
