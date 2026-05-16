import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene_importer/constants.dart';
import 'package:flutter_scene_importer/gltf.dart';

import '../geometry/geometry.dart';

/// Builds an engine [Geometry] from a glTF mesh primitive.
///
/// Vertex layout produced here must match what
/// `shaders/flutter_scene_(un)skinned.vert` expects:
///
/// - **Unskinned** (48 bytes/vertex): position(3 f32), normal(3 f32),
///   texture_coords(2 f32), color(4 f32).
/// - **Skinned** (80 bytes/vertex): unskinned + joints(4 f32) + weights(4 f32).
class BuiltGeometry {
  BuiltGeometry({required this.geometry, required this.vertexCount});
  final Geometry geometry;
  final int vertexCount;
}

/// Pure-data result of packing a primitive into the engine's vertex layout,
/// without uploading to the GPU. Useful for unit testing and byte-level
/// comparisons against the offline `.model` import path.
class PackedPrimitiveData {
  PackedPrimitiveData({
    required this.vertexBytes,
    required this.vertexCount,
    required this.indexBytes,
    required this.indexType,
    required this.isSkinned,
  });
  final Uint8List vertexBytes;
  final int vertexCount;
  final Uint8List indexBytes;
  final gpu.IndexType indexType;
  final bool isSkinned;
}

BuiltGeometry buildGeometry({
  required GltfMeshPrimitive primitive,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
}) {
  final packed = packPrimitive(
    primitive: primitive,
    accessors: accessors,
    bufferViews: bufferViews,
    bufferData: bufferData,
  );
  final Geometry geometry =
      packed.isSkinned ? SkinnedGeometry() : UnskinnedGeometry();
  geometry.uploadVertexData(
    ByteData.sublistView(packed.vertexBytes),
    packed.vertexCount,
    ByteData.sublistView(packed.indexBytes),
    indexType: packed.indexType,
  );
  return BuiltGeometry(geometry: geometry, vertexCount: packed.vertexCount);
}

PackedPrimitiveData packPrimitive({
  required GltfMeshPrimitive primitive,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
}) {
  final positionIdx = primitive.attributes['POSITION'];
  if (positionIdx == null) {
    throw const FormatException('Mesh primitive is missing POSITION attribute');
  }
  final positions = _readVec3(positionIdx, accessors, bufferViews, bufferData);
  final vertexCount = positions.length ~/ 3;

  // Read (or synthesize) the triangle index list up front: it's needed
  // both to build the index buffer and to compute normals when the
  // glTF primitive omits them.
  final Uint32List indexList;
  final bool indices32Bit;
  if (primitive.indices != null) {
    final accessor = accessors[primitive.indices!];
    indexList = readAccessorAsUint32(
      accessor,
      bufferViews[accessor.bufferView!],
      bufferData,
    );
    indices32Bit = accessor.componentType == GltfComponentType.unsignedInt;
  } else {
    // No indices: a sequential triangle list.
    indexList = Uint32List(vertexCount);
    for (int i = 0; i < vertexCount; i++) {
      indexList[i] = i;
    }
    indices32Bit = false;
  }

  // glTF requires the client to generate normals when a primitive
  // omits them. The Khronos Fox sample, for one, ships no NORMAL
  // attribute; without this it would render with zero normals and lose
  // all shading.
  final Float32List normals;
  if (primitive.attributes.containsKey('NORMAL')) {
    normals = _readVec3(
      primitive.attributes['NORMAL']!,
      accessors,
      bufferViews,
      bufferData,
    );
  } else {
    normals = _computeNormals(positions, indexList, vertexCount);
  }
  final texCoords = _readOptionalVec2(
    'TEXCOORD_0',
    primitive,
    accessors,
    bufferViews,
    bufferData,
    vertexCount,
  );
  final colors = _readOptionalColor(
    'COLOR_0',
    primitive,
    accessors,
    bufferViews,
    bufferData,
    vertexCount,
  );

  final hasJoints =
      primitive.attributes.containsKey('JOINTS_0') &&
      primitive.attributes.containsKey('WEIGHTS_0');

  final perVertex = hasJoints ? kSkinnedPerVertexSize : kUnskinnedPerVertexSize;
  final stride = perVertex ~/ 4; // floats per vertex
  final out = Float32List(vertexCount * stride);

  for (int i = 0; i < vertexCount; i++) {
    final o = i * stride;
    out[o + 0] = positions[i * 3 + 0];
    out[o + 1] = positions[i * 3 + 1];
    out[o + 2] = positions[i * 3 + 2];
    out[o + 3] = normals[i * 3 + 0];
    out[o + 4] = normals[i * 3 + 1];
    out[o + 5] = normals[i * 3 + 2];
    out[o + 6] = texCoords[i * 2 + 0];
    out[o + 7] = texCoords[i * 2 + 1];
    out[o + 8] = colors[i * 4 + 0];
    out[o + 9] = colors[i * 4 + 1];
    out[o + 10] = colors[i * 4 + 2];
    out[o + 11] = colors[i * 4 + 3];
  }

  if (hasJoints) {
    final joints = _readVec4(
      primitive.attributes['JOINTS_0']!,
      accessors,
      bufferViews,
      bufferData,
    );
    final weights = _readVec4(
      primitive.attributes['WEIGHTS_0']!,
      accessors,
      bufferViews,
      bufferData,
    );
    for (int i = 0; i < vertexCount; i++) {
      final o = i * stride + 12;
      out[o + 0] = joints[i * 4 + 0];
      out[o + 1] = joints[i * 4 + 1];
      out[o + 2] = joints[i * 4 + 2];
      out[o + 3] = joints[i * 4 + 3];
      out[o + 4] = weights[i * 4 + 0];
      out[o + 5] = weights[i * 4 + 1];
      out[o + 6] = weights[i * 4 + 2];
      out[o + 7] = weights[i * 4 + 3];
    }
  }

  // flutter_gpu wants 16- or 32-bit indices. Pass 32-bit through;
  // narrow everything else to 16-bit.
  final Uint8List indexBytes;
  final gpu.IndexType indexType;
  if (indices32Bit) {
    indexBytes = indexList.buffer.asUint8List(
      indexList.offsetInBytes,
      indexList.lengthInBytes,
    );
    indexType = gpu.IndexType.int32;
  } else {
    final widened = Uint16List(indexList.length);
    for (int i = 0; i < indexList.length; i++) {
      widened[i] = indexList[i];
    }
    indexBytes = widened.buffer.asUint8List(
      widened.offsetInBytes,
      widened.lengthInBytes,
    );
    indexType = gpu.IndexType.int16;
  }

  return PackedPrimitiveData(
    vertexBytes: out.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes),
    vertexCount: vertexCount,
    indexBytes: indexBytes,
    indexType: indexType,
    isSkinned: hasJoints,
  );
}

Float32List _readVec3(
  int idx,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
) {
  final accessor = accessors[idx];
  return readAccessorAsFloat32(
    accessor,
    bufferViews[accessor.bufferView!],
    bufferData,
  );
}

Float32List _readVec4(
  int idx,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
) {
  final accessor = accessors[idx];
  return readAccessorAsFloat32(
    accessor,
    bufferViews[accessor.bufferView!],
    bufferData,
  );
}

/// Generates per-vertex normals from a triangle list, used when a glTF
/// primitive omits the NORMAL attribute (the spec requires the client
/// to generate them).
///
/// Each triangle's face normal (the unnormalized cross product, so
/// larger triangles contribute proportionally) is added to its three
/// vertices, then every vertex normal is normalized. This produces
/// smoothed normals, which is what common glTF loaders do and which
/// the engine's bind-pose / skinning paths handle uniformly with
/// authored normals.
Float32List _computeNormals(
  Float32List positions,
  Uint32List indices,
  int vertexCount,
) {
  final normals = Float32List(vertexCount * 3);
  for (int t = 0; t + 2 < indices.length; t += 3) {
    final i0 = indices[t];
    final i1 = indices[t + 1];
    final i2 = indices[t + 2];
    final ax = positions[i0 * 3];
    final ay = positions[i0 * 3 + 1];
    final az = positions[i0 * 3 + 2];
    final e1x = positions[i1 * 3] - ax;
    final e1y = positions[i1 * 3 + 1] - ay;
    final e1z = positions[i1 * 3 + 2] - az;
    final e2x = positions[i2 * 3] - ax;
    final e2y = positions[i2 * 3 + 1] - ay;
    final e2z = positions[i2 * 3 + 2] - az;
    final nx = e1y * e2z - e1z * e2y;
    final ny = e1z * e2x - e1x * e2z;
    final nz = e1x * e2y - e1y * e2x;
    for (final i in [i0, i1, i2]) {
      normals[i * 3] += nx;
      normals[i * 3 + 1] += ny;
      normals[i * 3 + 2] += nz;
    }
  }
  for (int i = 0; i < vertexCount; i++) {
    final x = normals[i * 3];
    final y = normals[i * 3 + 1];
    final z = normals[i * 3 + 2];
    final len = sqrt(x * x + y * y + z * z);
    if (len > 1e-12) {
      normals[i * 3] = x / len;
      normals[i * 3 + 1] = y / len;
      normals[i * 3 + 2] = z / len;
    } else {
      // Degenerate vertex (only touched by zero-area triangles).
      normals[i * 3 + 1] = 1.0;
    }
  }
  return normals;
}

Float32List _readOptionalVec2(
  String name,
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  int vertexCount,
) {
  final idx = primitive.attributes[name];
  if (idx == null) return Float32List(vertexCount * 2);
  final accessor = accessors[idx];
  return readAccessorAsFloat32(
    accessor,
    bufferViews[accessor.bufferView!],
    bufferData,
  );
}

Float32List _readOptionalColor(
  String name,
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  int vertexCount,
) {
  final idx = primitive.attributes[name];
  if (idx == null) {
    // Default vertex color = opaque white.
    final out = Float32List(vertexCount * 4);
    for (int i = 0; i < vertexCount; i++) {
      out[i * 4 + 0] = 1.0;
      out[i * 4 + 1] = 1.0;
      out[i * 4 + 2] = 1.0;
      out[i * 4 + 3] = 1.0;
    }
    return out;
  }
  final accessor = accessors[idx];
  final raw = readAccessorAsFloat32(
    accessor,
    bufferViews[accessor.bufferView!],
    bufferData,
  );
  if (accessor.type == GltfAccessorType.vec4) return raw;
  // Promote vec3 colors to vec4 with alpha=1.
  final out = Float32List(vertexCount * 4);
  for (int i = 0; i < vertexCount; i++) {
    out[i * 4 + 0] = raw[i * 3 + 0];
    out[i * 4 + 1] = raw[i * 3 + 1];
    out[i * 4 + 2] = raw[i * 3 + 2];
    out[i * 4 + 3] = 1.0;
  }
  return out;
}
