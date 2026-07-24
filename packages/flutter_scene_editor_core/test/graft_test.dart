// Covers the cross-document graft used by GLB import-into-scene. The
// load-bearing checks are that a grafted document has no dangling id
// references (every child, resource, payload, skin, and animation ref
// resolves) and that the graft transaction reverts byte-for-byte, so an
// import is one clean undoable edit.
//
// Runs only when the source GLB corpus is present (CI without it skips).

import 'dart:io';

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('graftDocumentRecords', () {
    for (final name in const ['fcar.glb', 'dash.glb']) {
      test('grafts $name into an empty document with no dangling refs', () {
        final path = _resolve('examples/assets_src/$name');
        if (!File(path).existsSync()) {
          // ignore: avoid_print
          print('Test data missing ($path) - skipping.');
          return;
        }
        final source = importGlbToSceneDocument(File(path).readAsBytesSync());
        final target = SceneDocument(allocator: IdAllocator(session: 1));
        final graft = graftDocumentRecords(target, source);
        Transaction(
          name: 'Import',
          records: graft.records,
        ).apply(DocumentMutator(target));

        // Every entity came across.
        expect(target.nodes.length, source.nodes.length);
        expect(target.resources.length, source.resources.length);
        expect(target.skins.length, source.skins.length);
        expect(target.animations.length, source.animations.length);
        expect(target.payloads.length, source.payloads.length);
        expect(target.roots, graft.rootIds);
        // Fresh ids, so nothing collides with the source ids.
        for (final id in source.nodes.keys) {
          expect(target.nodes.containsKey(id), isFalse);
        }
        _expectNoDanglingRefs(target);
      });
    }

    test('appends to a non-empty document, preserving existing content', () {
      final path = _resolve('examples/assets_src/fcar.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final target = SceneDocument(allocator: IdAllocator(session: 2));
      final existing = target.createNode(name: 'Existing', root: true);
      final source = importGlbToSceneDocument(File(path).readAsBytesSync());
      final graft = graftDocumentRecords(target, source);
      Transaction(
        name: 'Import',
        records: graft.records,
      ).apply(DocumentMutator(target));

      expect(target.nodes.length, source.nodes.length + 1);
      // The existing root is kept and the imported roots are appended after it.
      expect(target.roots.first, existing.id);
      expect(target.roots.sublist(1), graft.rootIds);
      _expectNoDanglingRefs(target);
    });

    test('grafts under a parent node when given one', () {
      final path = _resolve('examples/assets_src/fcar.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final target = SceneDocument(allocator: IdAllocator(session: 3));
      final parent = target.createNode(name: 'Group', root: true);
      final source = importGlbToSceneDocument(File(path).readAsBytesSync());
      final graft = graftDocumentRecords(target, source, parentId: parent.id);
      Transaction(
        name: 'Import',
        records: graft.records,
      ).apply(DocumentMutator(target));

      // Imported roots are children of the parent, not document roots.
      expect(target.roots, [parent.id]);
      expect(target.nodes[parent.id]!.children, graft.rootIds);
      _expectNoDanglingRefs(target);
    });

    test('wrapRootsUnderGroup reparents roots under a transformed group', () {
      final doc = SceneDocument(allocator: IdAllocator(session: 5));
      final a = doc.createNode(name: 'A', root: true);
      final b = doc.createNode(name: 'B', root: true);
      final transform = TrsTransform(scale: Vector3.all(2.0));
      final groupId = wrapRootsUnderGroup(
        doc,
        name: 'Imported',
        transform: transform,
      );

      expect(doc.roots, [groupId]);
      expect(doc.nodes[groupId]!.name, 'Imported');
      expect(doc.nodes[groupId]!.children, [a.id, b.id]);
      final t = doc.nodes[groupId]!.transform as TrsTransform;
      expect(t.scale, Vector3.all(2.0));
      // The former roots are kept as nodes, just no longer document roots.
      expect(doc.nodes.containsKey(a.id), isTrue);
      expect(doc.nodes.containsKey(b.id), isTrue);
    });

    test('the import transaction reverts byte-for-byte (undo)', () {
      final path = _resolve('examples/assets_src/dash.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final target = SceneDocument(allocator: IdAllocator(session: 4));
      target.createNode(name: 'Existing', root: true);
      final before = writeFscene(target);

      final history = EditHistory(DocumentMutator(target));
      final source = importGlbToSceneDocument(File(path).readAsBytesSync());
      final graft = graftDocumentRecords(target, source);
      history.commit(Transaction(name: 'Import', records: graft.records));
      expect(target.nodes.length, greaterThan(1));
      expect(target.skins, isNotEmpty);
      expect(target.animations, isNotEmpty);

      history.undo();
      expect(writeFscene(target), before);
      expect(target.skins, isEmpty);
      expect(target.animations, isEmpty);
      expect(target.payloads, isEmpty);
      expect(target.resources, isEmpty);
    });
  });
}

// Asserts every id reference in [doc] resolves to an entry of the right pool.
void _expectNoDanglingRefs(SceneDocument doc) {
  bool node(LocalId id) => doc.nodes.containsKey(id);
  bool res(LocalId id) => doc.resources.containsKey(id);
  bool payload(LocalId id) => doc.payloads.containsKey(id);

  for (final id in doc.roots) {
    expect(node(id), isTrue, reason: 'root $id missing');
  }
  for (final n in doc.nodes.values) {
    for (final c in n.children) {
      expect(node(c), isTrue, reason: 'child $c of ${n.id} missing');
    }
    if (n.skin != null) {
      expect(doc.skins.containsKey(n.skin), isTrue, reason: 'skin missing');
    }
    for (final comp in n.components) {
      for (final value in comp.properties.values) {
        _forEachRef(value, onNode: node, onResource: res);
      }
    }
  }
  for (final r in doc.resources.values) {
    switch (r) {
      case GeometryResource g:
        if (g.vertices != null) {
          expect(payload(g.vertices!), isTrue, reason: 'vertices missing');
        }
        if (g.indices != null) {
          expect(payload(g.indices!), isTrue, reason: 'indices missing');
        }
      case TextureResource t:
        if (t.payload != null) {
          expect(
            payload(t.payload!),
            isTrue,
            reason: 'texture payload missing',
          );
        }
      case MaterialResource m:
        for (final value in m.properties.values) {
          _forEachRef(value, onNode: node, onResource: res);
        }
      case RenderTextureResource():
        break;
      case EnvironmentResource():
        break;
    }
  }
  for (final s in doc.skins.values) {
    for (final j in s.joints) {
      expect(node(j), isTrue, reason: 'joint $j missing');
    }
    expect(payload(s.inverseBindMatrices), isTrue, reason: 'ibm missing');
    if (s.skeleton != null) {
      expect(node(s.skeleton!), isTrue, reason: 'skeleton missing');
    }
  }
  for (final a in doc.animations.values) {
    for (final ch in a.channels) {
      expect(node(ch.target), isTrue, reason: 'anim target missing');
      expect(payload(ch.timeline), isTrue, reason: 'timeline missing');
      expect(payload(ch.keyframes), isTrue, reason: 'keyframes missing');
    }
  }
}

void _forEachRef(
  PropertyValue value, {
  required bool Function(LocalId) onNode,
  required bool Function(LocalId) onResource,
}) {
  switch (value) {
    case NodeRefValue(:final id):
      expect(onNode(id), isTrue, reason: 'node ref $id missing');
    case ResourceRefValue(:final id):
      expect(onResource(id), isTrue, reason: 'resource ref $id missing');
    case ListValue(:final values):
      for (final v in values) {
        _forEachRef(v, onNode: onNode, onResource: onResource);
      }
    case MapValue(:final values):
      for (final v in values.values) {
        _forEachRef(v, onNode: onNode, onResource: onResource);
      }
    default:
      break;
  }
}

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync()) return candidate;
  }
  return relative;
}
