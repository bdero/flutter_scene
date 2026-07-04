import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/gltf.dart';

import '../geometry/geometry.dart';

/// GPU-uploads an engine [Geometry] from a [packGltfPrimitive]-packed
/// primitive.
///
/// The pure-data packing (vertex layout, index handling, normal generation)
/// is done by [packGltfPrimitive], off the raster thread on a background
/// isolate for the runtime importer; this upload half must run on the raster
/// thread. Keeping them split is what lets a large model pack without stalling
/// the UI. The offline scene emitter shares the same packer.
Geometry geometryFromPacked(PackedPrimitive packed) {
  final Geometry geometry = packed.isSkinned
      ? SkinnedGeometry()
      : UnskinnedGeometry();
  geometry.uploadVertexData(
    ByteData.sublistView(packed.vertexBytes),
    packed.vertexCount,
    ByteData.sublistView(packed.indexBytes),
    indexType: packed.indices32Bit ? gpu.IndexType.int32 : gpu.IndexType.int16,
  );
  return geometry;
}
