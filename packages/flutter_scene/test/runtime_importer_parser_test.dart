import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
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

  test('primitive packing preserves TEXCOORD_0 and TEXCOORD_1', () {
    final source = Float32List.fromList([
      // Positions.
      0, 0, 0, 0, 1, 0, 1, 0, 0,
      // Normals.
      0, 0, 1, 0, 0, 1, 0, 0, 1,
      // UV0.
      0, 0, 0.5, 0.5, 1, 1,
      // UV1.
      0.25, 0.75, 0.5, 0.25, 0.75, 0.5,
      // Tangents.
      1, 0, 0, 1, 0, 1, 0, -1, -1, 0, 0, 1,
    ]);
    final views = <GltfBufferView>[
      GltfBufferView(buffer: 0, byteOffset: 0, byteLength: 36),
      GltfBufferView(buffer: 0, byteOffset: 36, byteLength: 36),
      GltfBufferView(buffer: 0, byteOffset: 72, byteLength: 24),
      GltfBufferView(buffer: 0, byteOffset: 96, byteLength: 24),
      GltfBufferView(buffer: 0, byteOffset: 120, byteLength: 48),
    ];
    GltfAccessor accessor(int view, GltfAccessorType type) => GltfAccessor(
      componentType: GltfComponentType.float,
      count: 3,
      type: type,
      bufferView: view,
    );
    final packed = packGltfPrimitive(
      primitive: GltfMeshPrimitive(
        attributes: const {
          'POSITION': 0,
          'NORMAL': 1,
          'TEXCOORD_0': 2,
          'TEXCOORD_1': 3,
          'TANGENT': 4,
        },
      ),
      accessors: [
        accessor(0, GltfAccessorType.vec3),
        accessor(1, GltfAccessorType.vec3),
        accessor(2, GltfAccessorType.vec2),
        accessor(3, GltfAccessorType.vec2),
        accessor(4, GltfAccessorType.vec4),
      ],
      bufferViews: views,
      bufferData: source.buffer.asUint8List(),
    );

    final vertices = Float32List.sublistView(packed.vertexBytes);
    expect(vertices.sublist(6, 10), [0, 0, 0.25, 0.75]);
    expect(vertices.sublist(18 + 6, 18 + 10), [0.5, 0.5, 0.5, 0.25]);
    expect(vertices.sublist(36 + 6, 36 + 10), [1, 1, 0.75, 0.5]);
    expect(vertices.sublist(14, 18), [1, 0, 0, 1]);
    expect(vertices.sublist(18 + 14, 18 + 18), [0, 1, 0, -1]);
    expect(vertices.sublist(36 + 14, 36 + 18), [-1, 0, 0, 1]);
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
