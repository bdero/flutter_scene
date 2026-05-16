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

  // Source attribute arrays, indexed by original glTF vertex index.
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
  final joints =
      hasJoints
          ? _readVec4(
            primitive.attributes['JOINTS_0']!,
            accessors,
            bufferViews,
            bufferData,
          )
          : null;
  final weights =
      hasJoints
          ? _readVec4(
            primitive.attributes['WEIGHTS_0']!,
            accessors,
            bufferViews,
            bufferData,
          )
          : null;

  // Determine the output vertex set.
  //
  // When the primitive authors normals, the mesh is kept as-is:
  // `srcOf` is the identity and the glTF index buffer is reused.
  //
  // When normals are absent, glTF requires the client to generate
  // flat normals -- each triangle gets its own face normal. Shared
  // vertices can't carry per-triangle normals, so the mesh is
  // de-indexed: every triangle is expanded to three unique vertices
  // and a sequential index buffer is emitted. The Khronos Fox and
  // RecursiveSkeletons samples both ship without normals.
  final List<int> srcOf; // output vertex index -> source vertex index
  final Float32List normals; // output-vertex normals (3 per vertex)
  final Uint32List outIndexList;
  final bool outIndices32Bit;

  if (primitive.attributes.containsKey('NORMAL')) {
    normals = _readVec3(
      primitive.attributes['NORMAL']!,
      accessors,
      bufferViews,
      bufferData,
    );
    srcOf = List<int>.generate(vertexCount, (i) => i);
    outIndexList = indexList;
    outIndices32Bit = indices32Bit;
  } else {
    final triCount = indexList.length ~/ 3;
    final outCount = triCount * 3;
    srcOf = List<int>.filled(outCount, 0);
    normals = Float32List(outCount * 3);
    for (int t = 0; t < triCount; t++) {
      final i0 = indexList[t * 3];
      final i1 = indexList[t * 3 + 1];
      final i2 = indexList[t * 3 + 2];
      final ax = positions[i0 * 3];
      final ay = positions[i0 * 3 + 1];
      final az = positions[i0 * 3 + 2];
      final e1x = positions[i1 * 3] - ax;
      final e1y = positions[i1 * 3 + 1] - ay;
      final e1z = positions[i1 * 3 + 2] - az;
      final e2x = positions[i2 * 3] - ax;
      final e2y = positions[i2 * 3 + 1] - ay;
      final e2z = positions[i2 * 3 + 2] - az;
      var nx = e1y * e2z - e1z * e2y;
      var ny = e1z * e2x - e1x * e2z;
      var nz = e1x * e2y - e1y * e2x;
      final len = sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 1e-12) {
        nx /= len;
        ny /= len;
        nz /= len;
      } else {
        // Degenerate (zero-area) triangle: pick an arbitrary normal.
        nx = 0;
        ny = 1;
        nz = 0;
      }
      for (int c = 0; c < 3; c++) {
        final k = t * 3 + c;
        srcOf[k] = indexList[t * 3 + c];
        normals[k * 3] = nx;
        normals[k * 3 + 1] = ny;
        normals[k * 3 + 2] = nz;
      }
    }
    outIndexList = Uint32List(outCount);
    for (int k = 0; k < outCount; k++) {
      outIndexList[k] = k;
    }
    // 16-bit indices address 0..65535.
    outIndices32Bit = outCount > 0x10000;
  }

  final outVertexCount = srcOf.length;
  final perVertex = hasJoints ? kSkinnedPerVertexSize : kUnskinnedPerVertexSize;
  final stride = perVertex ~/ 4; // floats per vertex
  final out = Float32List(outVertexCount * stride);

  for (int k = 0; k < outVertexCount; k++) {
    final o = k * stride;
    final s = srcOf[k];
    out[o + 0] = positions[s * 3 + 0];
    out[o + 1] = positions[s * 3 + 1];
    out[o + 2] = positions[s * 3 + 2];
    out[o + 3] = normals[k * 3 + 0];
    out[o + 4] = normals[k * 3 + 1];
    out[o + 5] = normals[k * 3 + 2];
    out[o + 6] = texCoords[s * 2 + 0];
    out[o + 7] = texCoords[s * 2 + 1];
    out[o + 8] = colors[s * 4 + 0];
    out[o + 9] = colors[s * 4 + 1];
    out[o + 10] = colors[s * 4 + 2];
    out[o + 11] = colors[s * 4 + 3];
    if (hasJoints) {
      final j = o + 12;
      out[j + 0] = joints![s * 4 + 0];
      out[j + 1] = joints[s * 4 + 1];
      out[j + 2] = joints[s * 4 + 2];
      out[j + 3] = joints[s * 4 + 3];
      out[j + 4] = weights![s * 4 + 0];
      out[j + 5] = weights[s * 4 + 1];
      out[j + 6] = weights[s * 4 + 2];
      out[j + 7] = weights[s * 4 + 3];
    }
  }

  // flutter_gpu wants 16- or 32-bit indices. Pass 32-bit through;
  // narrow everything else to 16-bit.
  final Uint8List indexBytes;
  final gpu.IndexType indexType;
  if (outIndices32Bit) {
    indexBytes = outIndexList.buffer.asUint8List(
      outIndexList.offsetInBytes,
      outIndexList.lengthInBytes,
    );
    indexType = gpu.IndexType.int32;
  } else {
    final widened = Uint16List(outIndexList.length);
    for (int i = 0; i < outIndexList.length; i++) {
      widened[i] = outIndexList[i];
    }
    indexBytes = widened.buffer.asUint8List(
      widened.offsetInBytes,
      widened.lengthInBytes,
    );
    indexType = gpu.IndexType.int16;
  }

  return PackedPrimitiveData(
    vertexBytes: out.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes),
    vertexCount: outVertexCount,
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
