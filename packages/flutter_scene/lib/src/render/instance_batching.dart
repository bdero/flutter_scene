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
  Object? get jointsTexture;
}

int opaqueBatchEnd(List<OpaqueBatchRecord> records, int start) {
  final first = records[start];
  if (first.geometry.instancedVertexLayout == null ||
      first.jointsTexture != null) {
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
      next.jointsTexture == null;
}

int depthBatchEnd(List<RenderItem> records, int start) {
  final first = records[start];
  if (first.geometry.instancedVertexLayout == null ||
      first.jointsTexture != null) {
    return start + 1;
  }
  var end = start + 1;
  while (end < records.length) {
    final next = records[end];
    if (!identical(first.geometry, next.geometry) ||
        !identical(first.material, next.material) ||
        next.jointsTexture != null) {
      break;
    }
    end++;
  }
  return end;
}

InstanceDataBatch instanceDataBatchFor(
  RenderItem item, {
  required List<int>? indices,
}) {
  final instances = item.instanceTransforms;
  if (instances == null) {
    return InstanceDataBatch.single(
      nodeTransform: item.worldTransform,
      nodeWindingFlipped: item.windingFlipped,
    );
  }
  final packedWorldData = item.instanceWorldData;
  final packedWinding = item.instanceWorldWindingFlipped;
  if (packedWorldData != null && packedWinding != null) {
    return InstanceDataBatch.cached(
      packedWorldData: packedWorldData,
      packedWindingFlipped: packedWinding,
      indices: indices,
    );
  }
  return InstanceDataBatch(
    nodeTransform: item.worldTransform,
    instances: instances,
    colors: item.instanceColors!,
    nodeWindingFlipped: item.windingFlipped,
    instanceWindingFlipped: item.instanceWindingFlipped,
    indices: indices,
  );
}
