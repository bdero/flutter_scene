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

/// Recycles [InstanceDataBatch] objects across frames.
///
/// A batch describes where one group's instance data lives and is read, never
/// retained, by the pack call it is handed to. Because that lifetime ends
/// inside the same flush that created it, the encoders refill a fixed set of
/// batch objects rather than allocating one per batched group per frame, which
/// on a scene with many batched runs was one of the larger per-frame
/// allocation sources left in the encoders.
///
/// Call [reset] before filling, then [addFor] once per group; [batches] is the
/// live list, valid until the next [reset].
final class InstanceDataBatchPool {
  final List<InstanceDataBatch> _live = [];
  final List<InstanceDataBatch> _spare = [];

  /// The batches filled since the last [reset], in fill order.
  List<InstanceDataBatch> get batches => _live;

  /// Returns every live batch to the free list. The batches themselves are
  /// kept, so a steady-state frame allocates none.
  void reset() {
    for (final batch in _live) {
      // Dropped on the way to the free list, or a spare batch keeps its last
      // group's instance data reachable until something reuses that slot,
      // which may never happen. Unloading a large instanced mesh would leave
      // its packed transforms alive in the pool.
      batch.clearPayload();
    }
    _spare.addAll(_live);
    _live.clear();
  }

  /// Fills the next batch from [item], the pooled spelling of
  /// [instanceDataBatchFor].
  void addFor(
    RenderItem item, {
    required List<int>? indices,
    bool? windingFlipped,
  }) {
    final batch = _spare.isEmpty
        ? InstanceDataBatch.pooled()
        : _spare.removeLast();
    _live.add(batch);
    fillInstanceDataBatch(
      batch,
      item,
      indices: indices,
      windingFlipped: windingFlipped,
    );
  }
}

/// Describes [item]'s instance data in a freshly allocated batch.
///
/// The encoders use [InstanceDataBatchPool.addFor] instead, which fills a
/// recycled batch; this spelling remains for one-off callers.
InstanceDataBatch instanceDataBatchFor(
  RenderItem item, {
  required List<int>? indices,
  bool? windingFlipped,
}) {
  final batch = InstanceDataBatch.pooled();
  fillInstanceDataBatch(
    batch,
    item,
    indices: indices,
    windingFlipped: windingFlipped,
  );
  return batch;
}

/// Points [batch] at [item]'s instance data, overwriting every field so a
/// recycled batch carries nothing from its previous group.
void fillInstanceDataBatch(
  InstanceDataBatch batch,
  RenderItem item, {
  required List<int>? indices,
  bool? windingFlipped,
}) {
  final resolvedWinding = windingFlipped ?? item.windingFlipped;
  final instances = item.instanceTransforms;
  if (instances == null) {
    batch.setSingle(
      nodeTransform: item.worldTransform,
      nodeWindingFlipped: resolvedWinding,
    );
    return;
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
    batch.setCached(
      packedWorldData: packedWorldData,
      packedWindingFlipped: packedWinding,
      indices: indices,
      attributeFloats: attributeFloats,
    );
    return;
  }
  batch.setInstances(
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
