// Covers the pure-Dart .fscene document model: identity (ids + allocator),
// the spec types, and the SceneDocument container. No GPU is required.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('base32', () {
    test('encodes most-significant-bit first, unpadded', () {
      expect(encodeBase32(Uint8List.fromList([0x00])), '00');
      expect(encodeBase32(Uint8List.fromList([0xFF])), 'ZW');
      expect(encodeBase32(Uint8List(8)), '0000000000000');
    });
  });

  group('DocumentId', () {
    test('is 16 bytes with a 26-character token', () {
      final id = DocumentId.generate(Random(1));
      expect(id.bytes, hasLength(16));
      expect(id.toToken().length, 26);
    });

    test('is deterministic for a seeded random and stamps UUIDv4 bits', () {
      final a = DocumentId.generate(Random(7));
      final b = DocumentId.generate(Random(7));
      expect(a, b);
      expect(a.toToken(), b.toToken());
      // Version 4 in the high nibble of byte 6, variant 1 in byte 8.
      expect(a.bytes[6] & 0xF0, 0x40);
      expect(a.bytes[8] & 0xC0, 0x80);
    });

    test('distinct draws differ', () {
      final a = DocumentId.generate(Random(1));
      final b = DocumentId.generate(Random(2));
      expect(a, isNot(b));
    });
  });

  group('LocalId', () {
    test('equality and hashing are by (session, index)', () {
      expect(const LocalId(3, 9), const LocalId(3, 9));
      expect(const LocalId(3, 9).hashCode, const LocalId(3, 9).hashCode);
      expect(const LocalId(3, 9), isNot(const LocalId(3, 8)));
      expect(const LocalId(3, 9), isNot(const LocalId(4, 9)));
      final deduped = <LocalId>{}
        ..add(const LocalId(1, 1))
        ..add(const LocalId(1, 1));
      expect(deduped, hasLength(1));
    });

    test('token is 13 base32 characters of the 8 id bytes', () {
      expect(const LocalId(0, 0).toToken(), '0000000000000');
      expect(const LocalId(1, 2).toToken().length, 13);
    });
  });

  group('IdAllocator', () {
    test('mints monotonic, never-reused ids in one session', () {
      final alloc = IdAllocator(session: 42);
      expect(alloc.session, 42);
      expect(alloc.mint(), const LocalId(42, 0));
      expect(alloc.mint(), const LocalId(42, 1));
      expect(alloc.mint(), const LocalId(42, 2));
    });

    test('different sessions mint disjoint id sets (merge-safe)', () {
      final a = IdAllocator(session: 1);
      final b = IdAllocator(session: 2);
      final idsA = {for (var i = 0; i < 100; i++) a.mint()};
      final idsB = {for (var i = 0; i < 100; i++) b.mint()};
      expect(idsA, hasLength(100));
      expect(idsA.intersection(idsB), isEmpty);
    });

    test('excludedSessions forces a fresh salt', () {
      // Find the salt the seed would draw first.
      final probe = IdAllocator(random: Random(5));
      final firstSalt = probe.session;
      // The same seed, but with that salt excluded, must redraw.
      final avoided = IdAllocator(
        random: Random(5),
        excludedSessions: {firstSalt},
      );
      expect(avoided.session, isNot(firstSalt));
    });
  });

  group('TransformSpec', () {
    test('an identity TRS composes to the identity matrix', () {
      expect(TrsTransform().toMatrix4(), Matrix4.identity());
    });

    test('a translation-only TRS composes to a translation matrix', () {
      final m = TrsTransform(translation: Vector3(1, 2, 3)).toMatrix4();
      expect(m.getTranslation(), Vector3(1, 2, 3));
    });

    test('MatrixTransform returns a copy, not the stored matrix', () {
      final stored = Matrix4.identity();
      final spec = MatrixTransform(stored);
      final out = spec.toMatrix4();
      out.setEntry(0, 3, 9.0);
      expect(stored.entry(0, 3), 0.0, reason: 'toMatrix4 must not alias');
    });
  });

  group('specs', () {
    test('a plain node has no prefab instance and empty lists', () {
      final node = NodeSpec(id: const LocalId(1, 0));
      expect(node.instance, isNull);
      expect(node.children, isEmpty);
      expect(node.components, isEmpty);
      expect(node.layers, 1);
    });

    test('a prefab instance carries its source and empty deltas', () {
      final instance = PrefabInstanceSpec(
        source: const AssetRef('enemy.fscene'),
      );
      expect(instance.source.key, 'enemy.fscene');
      expect(instance.load, LoadPolicy.eager);
      expect(instance.overrides, isEmpty);
      expect(instance.removedNodes, isEmpty);
    });

    test('a texture has exactly one source', () {
      expect(
        () => TextureResource(const LocalId(1, 0)),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => TextureResource(
          const LocalId(1, 0),
          payload: const LocalId(2, 0),
          asset: const AssetRef('x.png'),
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        TextureResource(
          const LocalId(1, 0),
          payload: const LocalId(2, 0),
        ).asset,
        isNull,
      );
    });
  });

  group('SceneDocument', () {
    test('mints document-unique ids', () {
      final doc = SceneDocument();
      final ids = {for (var i = 0; i < 1000; i++) doc.newId()};
      expect(ids, hasLength(1000));
    });

    test('createNode registers the node and tracks roots', () {
      final doc = SceneDocument();
      final root = doc.createNode(name: 'root', root: true);
      final child = doc.createNode(name: 'child');
      root.children.add(child.id);

      expect(doc.node(root.id), same(root));
      expect(doc.node(child.id), same(child));
      expect(doc.roots, [root.id]);
      expect(doc.rootNodes, [root]);
    });

    test('addResource preserves the concrete type and is looked up by id', () {
      final doc = SceneDocument();
      final payload = doc.addPayload(
        PayloadSpec(doc.newId(), encoding: PayloadEncoding.vertexBuffer),
      );
      final GeometryResource geo = doc.addResource(
        GeometryResource(doc.newId(), payload: payload.id),
      );
      expect(doc.resource(geo.id), same(geo));
      expect(doc.payload(payload.id), same(payload));
    });

    test('usedSessions collects every id pool session salt', () {
      final docId = DocumentId.generate(Random(3));
      final doc = SceneDocument(
        documentId: docId,
        allocator: IdAllocator(session: 11),
      );
      doc.createNode();
      doc.addResource(
        GeometryResource(const LocalId(22, 5), payload: const LocalId(22, 6)),
      );
      expect(doc.usedSessions(), containsAll(<int>{11, 22}));
    });

    test('a fresh document has a studio environment and v1 format', () {
      final doc = SceneDocument();
      expect(doc.formatVersion, 1);
      expect(doc.stage.environment, isA<StudioEnvironment>());
      expect(doc.stage.upAxis, UpAxis.y);
      expect(doc.stage.toneMapping, 'pbrNeutral');
    });
  });
}
