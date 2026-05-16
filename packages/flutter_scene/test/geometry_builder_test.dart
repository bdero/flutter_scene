/// Covers packPrimitive's handling of the NORMAL attribute: authored
/// normals are passed through, and absent normals are generated from
/// the triangle geometry (glTF requires the client to do this; the
/// Khronos Fox sample ships no normals).
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/runtime_importer/geometry_builder.dart';
import 'package:flutter_scene_importer/gltf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads vertex `v`'s normal (floats 3..5 of the 12-float unskinned
/// vertex layout) out of packed vertex bytes.
List<double> _normalOf(PackedPrimitiveData packed, int v) {
  final floats = Float32List.sublistView(packed.vertexBytes);
  const stride = 12;
  return [
    floats[v * stride + 3],
    floats[v * stride + 4],
    floats[v * stride + 5],
  ];
}

void main() {
  test('generates +Z normals for a CCW triangle with no NORMAL', () {
    // Triangle (0,0,0), (1,0,0), (0,1,0): face normal is +Z.
    final buffer = Uint8List(36 + 6);
    final bd = ByteData.sublistView(buffer);
    const positions = <double>[0, 0, 0, 1, 0, 0, 0, 1, 0];
    for (var i = 0; i < positions.length; i++) {
      bd.setFloat32(i * 4, positions[i], Endian.little);
    }
    for (var i = 0; i < 3; i++) {
      bd.setUint16(36 + i * 2, i, Endian.little);
    }

    final packed = packPrimitive(
      primitive: GltfMeshPrimitive(attributes: {'POSITION': 0}, indices: 1),
      accessors: [
        GltfAccessor(
          componentType: GltfComponentType.float,
          count: 3,
          type: GltfAccessorType.vec3,
          bufferView: 0,
        ),
        GltfAccessor(
          componentType: GltfComponentType.unsignedShort,
          count: 3,
          type: GltfAccessorType.scalar,
          bufferView: 1,
        ),
      ],
      bufferViews: [
        GltfBufferView(buffer: 0, byteLength: 36, byteOffset: 0),
        GltfBufferView(buffer: 0, byteLength: 6, byteOffset: 36),
      ],
      bufferData: buffer,
    );

    expect(packed.vertexCount, 3);
    for (var v = 0; v < 3; v++) {
      expect(_normalOf(packed, v)[0], closeTo(0.0, 1e-6));
      expect(_normalOf(packed, v)[1], closeTo(0.0, 1e-6));
      expect(_normalOf(packed, v)[2], closeTo(1.0, 1e-6));
    }
  });

  test('de-indexes a shared-vertex mesh for flat normals', () {
    // Two triangles sharing edge v0-v1 but in different planes:
    //   A = (v0, v1, v2): face normal +Z
    //   B = (v0, v1, v3): face normal -Y
    // De-indexing must expand the 4 shared vertices to 6, each
    // carrying its own triangle's face normal (no averaging).
    final buffer = Uint8List(48 + 12);
    final bd = ByteData.sublistView(buffer);
    const positions = <double>[
      0, 0, 0, // v0
      1, 0, 0, // v1
      1, 1, 0, // v2
      1, 0, 1, // v3
    ];
    for (var i = 0; i < positions.length; i++) {
      bd.setFloat32(i * 4, positions[i], Endian.little);
    }
    const indices = <int>[0, 1, 2, 0, 1, 3];
    for (var i = 0; i < indices.length; i++) {
      bd.setUint16(48 + i * 2, indices[i], Endian.little);
    }

    final packed = packPrimitive(
      primitive: GltfMeshPrimitive(attributes: {'POSITION': 0}, indices: 1),
      accessors: [
        GltfAccessor(
          componentType: GltfComponentType.float,
          count: 4,
          type: GltfAccessorType.vec3,
          bufferView: 0,
        ),
        GltfAccessor(
          componentType: GltfComponentType.unsignedShort,
          count: 6,
          type: GltfAccessorType.scalar,
          bufferView: 1,
        ),
      ],
      bufferViews: [
        GltfBufferView(buffer: 0, byteLength: 48, byteOffset: 0),
        GltfBufferView(buffer: 0, byteLength: 12, byteOffset: 48),
      ],
      bufferData: buffer,
    );

    // 2 triangles -> 6 unique vertices after de-indexing.
    expect(packed.vertexCount, 6);
    for (var v = 0; v < 3; v++) {
      expect(_normalOf(packed, v)[0], closeTo(0.0, 1e-6));
      expect(_normalOf(packed, v)[1], closeTo(0.0, 1e-6));
      expect(_normalOf(packed, v)[2], closeTo(1.0, 1e-6));
    }
    for (var v = 3; v < 6; v++) {
      expect(_normalOf(packed, v)[0], closeTo(0.0, 1e-6));
      expect(_normalOf(packed, v)[1], closeTo(-1.0, 1e-6));
      expect(_normalOf(packed, v)[2], closeTo(0.0, 1e-6));
    }
  });

  test('passes authored normals through unchanged', () {
    // positions (36 bytes) + normals (36 bytes) + indices (6 bytes).
    final buffer = Uint8List(36 + 36 + 6);
    final bd = ByteData.sublistView(buffer);
    const positions = <double>[0, 0, 0, 1, 0, 0, 0, 1, 0];
    for (var i = 0; i < positions.length; i++) {
      bd.setFloat32(i * 4, positions[i], Endian.little);
    }
    // Authored normals all point +Y, which is deliberately not the
    // triangle's +Z face normal so a regression to generation shows.
    for (var v = 0; v < 3; v++) {
      bd.setFloat32(36 + v * 12 + 0, 0, Endian.little);
      bd.setFloat32(36 + v * 12 + 4, 1, Endian.little);
      bd.setFloat32(36 + v * 12 + 8, 0, Endian.little);
    }
    for (var i = 0; i < 3; i++) {
      bd.setUint16(72 + i * 2, i, Endian.little);
    }

    final packed = packPrimitive(
      primitive: GltfMeshPrimitive(
        attributes: {'POSITION': 0, 'NORMAL': 1},
        indices: 2,
      ),
      accessors: [
        GltfAccessor(
          componentType: GltfComponentType.float,
          count: 3,
          type: GltfAccessorType.vec3,
          bufferView: 0,
        ),
        GltfAccessor(
          componentType: GltfComponentType.float,
          count: 3,
          type: GltfAccessorType.vec3,
          bufferView: 1,
        ),
        GltfAccessor(
          componentType: GltfComponentType.unsignedShort,
          count: 3,
          type: GltfAccessorType.scalar,
          bufferView: 2,
        ),
      ],
      bufferViews: [
        GltfBufferView(buffer: 0, byteLength: 36, byteOffset: 0),
        GltfBufferView(buffer: 0, byteLength: 36, byteOffset: 36),
        GltfBufferView(buffer: 0, byteLength: 6, byteOffset: 72),
      ],
      bufferData: buffer,
    );

    for (var v = 0; v < 3; v++) {
      expect(_normalOf(packed, v), [0.0, 1.0, 0.0]);
    }
  });
}
