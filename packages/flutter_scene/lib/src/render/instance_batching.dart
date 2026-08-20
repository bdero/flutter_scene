import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

abstract interface class OpaqueBatchRecord {
  Geometry get geometry;
  Material get material;
  Object get pipeline;
  double get fade;
  int get lightListOffset;
  int get lightListCount;
  int get lightChannelMask;
  Object? get jointsTexture;
  Object? get morphWeights;
}

int opaqueBatchEnd(List<OpaqueBatchRecord> records, int start) {
  final first = records[start];
  // Skinned and morphed items carry per-item state (skeleton, weights)
  // bound outside the instance buffer, so they draw unbatched. Batching also
  // synthesizes one instance per node, and a node carries no per-instance
  // attribute values, so a material declaring them draws its items separately
  // (each from its own instanced mesh's data).
  // TODO(instance-attributes-batching): give a node a per-node attribute
  // source so these can batch too.
  if (first.geometry.instancedVertexLayout == null ||
      first.jointsTexture != null ||
      first.morphWeights != null ||
      first.material.instanceAttributes != null) {
    return start + 1;
  }
  var end = start + 1;
  while (end < records.length && _canBatchOpaque(first, records[end])) {
    end++;
  }
  return end;
}

bool _canBatchOpaque(OpaqueBatchRecord first, OpaqueBatchRecord next) {
  return identical(first.pipeline, next.pipeline) &&
      identical(first.geometry, next.geometry) &&
      identical(first.material, next.material) &&
      first.fade == next.fade &&
      first.lightListOffset == next.lightListOffset &&
      first.lightListCount == next.lightListCount &&
      first.lightChannelMask == next.lightChannelMask &&
      next.jointsTexture == null &&
      next.morphWeights == null;
}

int depthBatchEnd(List<RenderItem> records, int start) {
  final first = records[start];
  if (first.geometry.instancedVertexLayout == null ||
      first.jointsTexture != null ||
      first.morphWeights != null) {
    return start + 1;
  }
  var end = start + 1;
  while (end < records.length) {
    final next = records[end];
    if (!identical(first.geometry, next.geometry) ||
        !identical(first.material, next.material) ||
        next.jointsTexture != null ||
        next.morphWeights != null) {
      break;
    }
    end++;
  }
  return end;
}

InstanceDataBatch instanceDataBatchFor(
  RenderItem item, {
  required List<int>? indices,
  bool? windingFlipped,
}) {
  final resolvedWinding = windingFlipped ?? item.windingFlipped;
  final instances = item.instanceTransforms;
  if (instances == null) {
    return InstanceDataBatch.single(
      nodeTransform: item.worldTransform,
      nodeWindingFlipped: resolvedWinding,
    );
  }
  final packedWorldData = item.instanceWorldData;
  final packedWinding = item.instanceWorldWindingFlipped;
  final attributeData = item.instanceAttributeData;
  final attributeFloats = attributeData == null
      ? 0
      : item.instanceAttributeFloats;
  if (resolvedWinding == item.windingFlipped &&
      packedWorldData != null &&
      packedWinding != null) {
    return InstanceDataBatch.cached(
      packedWorldData: packedWorldData,
      packedWindingFlipped: packedWinding,
      indices: indices,
      attributeFloats: attributeFloats,
    );
  }
  return InstanceDataBatch(
    nodeTransform: item.worldTransform,
    instances: instances,
    colors: item.instanceColors!,
    nodeWindingFlipped: resolvedWinding,
    instanceWindingFlipped: item.instanceWindingFlipped,
    indices: indices,
    attributeData: attributeData,
    attributeFloats: attributeFloats,
  );
}
