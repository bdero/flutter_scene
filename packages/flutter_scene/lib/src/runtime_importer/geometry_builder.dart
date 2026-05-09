import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene_importer/constants.dart';

import '../geometry/geometry.dart';
import 'accessor.dart';
import 'gltf_types.dart';

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

  final normals = _readOptionalVec3(
    'NORMAL',
    primitive,
    accessors,
    bufferViews,
    bufferData,
    vertexCount,
  );
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

  // Indices: glTF uses optional unsigned 8/16/32 bit. flutter_gpu wants 16 or
  // 32. Widen byte indices to 16, otherwise pass through.
  final Uint8List indexBytes;
  final gpu.IndexType indexType;
  if (primitive.indices != null) {
    final accessor = accessors[primitive.indices!];
    final bufferView = bufferViews[accessor.bufferView!];
    final list = readAccessorAsUint32(accessor, bufferView, bufferData);
    if (accessor.componentType == GltfComponentType.unsignedInt) {
      indexBytes = list.buffer.asUint8List(
        list.offsetInBytes,
        list.lengthInBytes,
      );
      indexType = gpu.IndexType.int32;
    } else {
      final widened = Uint16List(list.length);
      for (int i = 0; i < list.length; i++) {
        widened[i] = list[i];
      }
      indexBytes = widened.buffer.asUint8List(
        widened.offsetInBytes,
        widened.lengthInBytes,
      );
      indexType = gpu.IndexType.int16;
    }
  } else {
    // No indices: synthesize a sequential 16-bit index buffer.
    final widened = Uint16List(vertexCount);
    for (int i = 0; i < vertexCount; i++) {
      widened[i] = i;
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

Float32List _readOptionalVec3(
  String name,
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  int vertexCount,
) {
  final idx = primitive.attributes[name];
  if (idx == null) return Float32List(vertexCount * 3); // zero-initialized
  return _readVec3(idx, accessors, bufferViews, bufferData);
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
