import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene_importer/gltf.dart';
import 'package:test/test.dart';

/// Tests for the pure-data layer of the runtime importer (no GPU required).
///
/// Loads .glb files from the workspace's examples/assets_src/ via dart:io
/// and validates that the parser extracts the expected structure.

void main() {
  group('parseGlb', () {
    test('rejects too-short input', () {
      expect(
        () => parseGlb(_bytes([0, 1, 2])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-glTF magic', () {
      // 12 bytes that don't start with 'glTF'.
      final bytes = _bytes([
        0x00,
        0x00,
        0x00,
        0x00,
        0x02,
        0x00,
        0x00,
        0x00,
        0x0c,
        0x00,
        0x00,
        0x00,
      ]);
      expect(() => parseGlb(bytes), throwsA(isA<FormatException>()));
    });
  });

  group('two_triangles.glb', () {
    late GlbContents container;
    late GltfDocument doc;

    setUpAll(() {
      final bytes = File('${_assetsDir()}/two_triangles.glb').readAsBytesSync();
      container = parseGlb(bytes);
      doc = parseGltfJson(container.json);
    });

    test('container has JSON and a non-empty BIN chunk', () {
      expect(container.json.isNotEmpty, isTrue);
      expect(container.binaryChunk.isNotEmpty, isTrue);
    });

    test('document has at least one scene and node', () {
      expect(doc.scenes, isNotEmpty);
      expect(doc.nodes, isNotEmpty);
      expect(doc.meshes, isNotEmpty);
    });

    test('mesh primitive has POSITION attribute', () {
      final mesh = doc.meshes.first;
      expect(mesh.primitives, isNotEmpty);
      expect(mesh.primitives.first.attributes.containsKey('POSITION'), isTrue);
    });

    test(
      'POSITION accessor reads as Float32List with the right cardinality',
      () {
        final primitive = doc.meshes.first.primitives.first;
        final accessor = doc.accessors[primitive.attributes['POSITION']!];
        final view = doc.bufferViews[accessor.bufferView!];
        final positions = readAccessorAsFloat32(
          accessor,
          view,
          container.binaryChunk,
        );
        expect(accessor.type, GltfAccessorType.vec3);
        expect(positions.length, accessor.count * 3);
        // No NaN or infinity in well-formed data.
        for (final v in positions) {
          expect(v.isFinite, isTrue);
        }
      },
    );

    test(
      'indices accessor (if present) reads as Uint32List with cardinality count',
      () {
        final primitive = doc.meshes.first.primitives.first;
        if (primitive.indices == null) return;
        final accessor = doc.accessors[primitive.indices!];
        final view = doc.bufferViews[accessor.bufferView!];
        final indices = readAccessorAsUint32(
          accessor,
          view,
          container.binaryChunk,
        );
        expect(accessor.type, GltfAccessorType.scalar);
        expect(indices.length, accessor.count);
      },
    );
  });

  group('all bundled .glb files parse without errors', () {
    for (final fileName in [
      'two_triangles.glb',
      'flutter_logo_baked.glb',
      'fcar.glb',
      'dash.glb',
    ]) {
      test(fileName, () {
        final path = '${_assetsDir()}/$fileName';
        if (!File(path).existsSync()) return; // skip if not present
        final bytes = File(path).readAsBytesSync();
        final container = parseGlb(bytes);
        final doc = parseGltfJson(container.json);
        expect(doc.nodes, isNotEmpty);
      });
    }
  });
}

/// Locates the examples/assets_src/ directory in the workspace, regardless of
/// whether tests run from the workspace root or the package directory.
String _assetsDir() {
  for (final candidate in [
    'examples/assets_src',
    '../../examples/assets_src',
    '../../../examples/assets_src',
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'Could not locate examples/assets_src/ relative to ${Directory.current.path}',
  );
}

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);
