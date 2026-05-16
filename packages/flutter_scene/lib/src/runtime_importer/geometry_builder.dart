import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene_importer/gltf.dart';

import '../geometry/geometry.dart';

/// An engine [Geometry] built from a glTF mesh primitive, paired with
/// its vertex count.
class BuiltGeometry {
  BuiltGeometry({required this.geometry, required this.vertexCount});
  final Geometry geometry;
  final int vertexCount;
}

/// Builds and GPU-uploads an engine [Geometry] from a glTF mesh
/// primitive.
///
/// The pure-data packing (vertex layout, index handling, normal
/// generation) is done by [packGltfPrimitive] in flutter_scene_importer
/// so the runtime GLB importer and the offline `.model` emitter share
/// one implementation.
BuiltGeometry buildGeometry({
  required GltfMeshPrimitive primitive,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
}) {
  final packed = packGltfPrimitive(
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
    indexType: packed.indices32Bit ? gpu.IndexType.int32 : gpu.IndexType.int16,
  );
  return BuiltGeometry(geometry: geometry, vertexCount: packed.vertexCount);
}
