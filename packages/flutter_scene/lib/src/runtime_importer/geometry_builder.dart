import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/gltf.dart';

import '../geometry/geometry.dart';
import '../geometry/morph_targets.dart';
import '../geometry/morphed_geometry.dart';

/// GPU-uploads an engine [Geometry] from a [packGltfPrimitive]-packed
/// primitive.
///
/// The pure-data packing (vertex layout, index handling, normal generation)
/// is done by [packGltfPrimitive], off the raster thread on a background
/// isolate for the runtime importer; this upload half must run on the raster
/// thread. Keeping them split is what lets a large model pack without stalling
/// the UI. The offline scene emitter shares the same packer.
///
/// [morphTargetNames] and [defaultMorphWeights] carry the owning glTF mesh's
/// target metadata when the primitive is morphed.
Geometry geometryFromPacked(
  PackedPrimitive packed, {
  List<String>? morphTargetNames,
  List<double>? defaultMorphWeights,
}) {
  final morph = packed.morphTargets;
  final Geometry geometry = morph != null
      ? (packed.isSkinned
            ? MorphedSkinnedGeometry(
                morphDataFromPacked(
                  morph,
                  targetNames: morphTargetNames,
                  defaultWeights: defaultMorphWeights,
                ),
              )
            : MorphedUnskinnedGeometry(
                morphDataFromPacked(
                  morph,
                  targetNames: morphTargetNames,
                  defaultWeights: defaultMorphWeights,
                ),
              ))
      : (packed.isSkinned ? SkinnedGeometry() : UnskinnedGeometry());
  geometry.uploadVertexData(
    ByteData.sublistView(packed.vertexBytes),
    packed.vertexCount,
    ByteData.sublistView(packed.indexBytes),
    indexType: packed.indices32Bit ? gpu.IndexType.int32 : gpu.IndexType.int16,
  );
  geometry.sourceWindingFlipped = packed.sourceWindingFlipped;
  return geometry;
}

/// Wraps packed morph deltas as engine [MorphTargetData], attaching the
/// mesh-level [targetNames] and [defaultWeights].
MorphTargetData morphDataFromPacked(
  PackedMorphTargets packed, {
  List<String>? targetNames,
  List<double>? defaultWeights,
}) => MorphTargetData(
  vertexCount: packed.vertexCount,
  targetCount: packed.targetCount,
  positionDeltas: packed.positionDeltas,
  normalDeltas: packed.normalDeltas,
  tangentDeltas: packed.tangentDeltas,
  targetNames: targetNames,
  defaultWeights: defaultWeights,
);
