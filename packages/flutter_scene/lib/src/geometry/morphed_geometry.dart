/// Geometry subclasses carrying glTF morph targets (blend shapes).
///
/// Both classes keep the base vertex data and blend
/// `base + sum(weight_i * delta_i)` on the CPU into a fresh vertex upload
/// whenever the applied weights change. Morphing happens before skinning;
/// the skinned variant blends the same interleaved layout the skin matrix
/// consumes, so the skin transforms already-morphed positions.
library;

import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/morph_targets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Unskinned geometry with morph targets.
///
/// Construct it, then upload the base vertices with
/// [Geometry.uploadVertexData] (72 bytes per vertex, the standard unskinned
/// layout). The owning [Node]'s morph weights are applied per draw through
/// [Geometry.setMorphWeights].
/// {@category Geometry}
class MorphedUnskinnedGeometry extends UnskinnedGeometry with _MorphBlending {
  /// Creates unskinned geometry morphed by [morphTargets].
  MorphedUnskinnedGeometry(MorphTargetData morphTargets) {
    _initMorphState(morphTargets);
  }

  @override
  int get _strideInFloats => kUnskinnedPerVertexSize ~/ 4;
}

/// Skinned geometry with morph targets, blended before the skin matrix is
/// applied.
/// {@category Geometry}
class MorphedSkinnedGeometry extends SkinnedGeometry with _MorphBlending {
  /// Creates skinned geometry morphed by [morphTargets].
  MorphedSkinnedGeometry(MorphTargetData morphTargets) {
    _initMorphState(morphTargets);
  }

  @override
  int get _strideInFloats => kSkinnedPerVertexSize ~/ 4;
}

/// Shared morph state and CPU blending over the interleaved vertex layouts.
///
/// The base vertex bytes are stashed at upload; a weight change re-blends
/// position and normal into a scratch copy and re-uploads it. A geometry
/// shared by nodes holding different weights re-blends on every draw.
/// TODO(morph-cpu-share): cache per-weight-set uploads for shared geometry.
mixin _MorphBlending on Geometry {
  late final MorphTargetData _morphData;

  // Base interleaved vertex floats and the index upload, kept so a blend can
  // re-upload without the caller's buffers.
  Float32List? _baseVertexFloats;
  int _baseVertexCount = 0;
  ByteData? _baseIndices;
  gpu.IndexType _baseIndexType = gpu.IndexType.int16;

  // The last-blended weights and the reused blend output.
  Float32List? _appliedWeights;
  Float32List? _blendScratch;
  bool _uploadingBlend = false;

  /// Floats per vertex of this geometry's interleaved layout. Position sits
  /// at offset 0 and normal at offset 3 in both layouts.
  int get _strideInFloats;

  @override
  MorphTargetData get morphTargets => _morphData;

  // Called by the subclass constructors.
  void _initMorphState(MorphTargetData data) {
    _morphData = data;
  }

  @override
  void uploadVertexData(
    ByteData vertices,
    int vertexCount,
    ByteData? indices, {
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    if (!_uploadingBlend) {
      if (vertexCount != _morphData.vertexCount) {
        throw ArgumentError(
          'Morphed geometry uploaded $vertexCount vertices, but its morph '
          'targets cover ${_morphData.vertexCount}',
        );
      }
      _baseVertexFloats = Float32List.fromList(
        Float32List.sublistView(vertices),
      );
      _baseVertexCount = vertexCount;
      _baseIndices = indices;
      _baseIndexType = indexType;
      _appliedWeights = null;
    }
    super.uploadVertexData(
      vertices,
      vertexCount,
      indices,
      indexType: indexType,
    );
    if (!_uploadingBlend) _expandBoundsForMorphRange();
  }

  @override
  void setMorphWeights(Float32List? weights) {
    if (weights == null) return;
    final base = _baseVertexFloats;
    if (base == null) return; // Nothing uploaded yet.
    if (_weightsMatch(weights)) return;
    _appliedWeights = Float32List.fromList(weights);
    final blended = _blendScratch ??= Float32List(base.length);
    _blendInterleaved(base, blended, weights);
    _uploadingBlend = true;
    try {
      uploadVertexData(
        ByteData.sublistView(blended),
        _baseVertexCount,
        _baseIndices,
        indexType: _baseIndexType,
      );
    } finally {
      _uploadingBlend = false;
    }
  }

  bool _weightsMatch(Float32List weights) {
    final applied = _appliedWeights;
    if (applied == null) {
      // The base upload is the all-zero blend.
      for (final w in weights) {
        if (w != 0.0) return false;
      }
      return true;
    }
    if (applied.length != weights.length) return false;
    for (var i = 0; i < weights.length; i++) {
      if (applied[i] != weights[i]) return false;
    }
    return true;
  }

  // Additive position/normal blend over the interleaved floats, then a
  // normal renormalization with a near-zero guard (a collapsed sum keeps
  // the base normal).
  void _blendInterleaved(
    Float32List base,
    Float32List out,
    Float32List weights,
  ) {
    out.setAll(0, base);
    final data = _morphData;
    final stride = _strideInFloats;
    final vertexCount = data.vertexCount;
    final positionDeltas = data.positionDeltas;
    final normalDeltas = data.normalDeltas;
    final count = weights.length < data.targetCount
        ? weights.length
        : data.targetCount;
    for (var t = 0; t < count; t++) {
      final w = weights[t];
      if (w == 0.0) continue;
      final offset = t * vertexCount * 3;
      for (var v = 0; v < vertexCount; v++) {
        final o = v * stride;
        final d = offset + v * 3;
        out[o] += w * positionDeltas[d];
        out[o + 1] += w * positionDeltas[d + 1];
        out[o + 2] += w * positionDeltas[d + 2];
        if (normalDeltas != null) {
          out[o + 3] += w * normalDeltas[d];
          out[o + 4] += w * normalDeltas[d + 1];
          out[o + 5] += w * normalDeltas[d + 2];
        }
      }
    }
    if (normalDeltas != null) {
      for (var v = 0; v < vertexCount; v++) {
        final o = v * stride + 3;
        final x = out[o], y = out[o + 1], z = out[o + 2];
        final lengthSquared = x * x + y * y + z * z;
        if (lengthSquared > 1e-12) {
          final inverseLength = 1.0 / sqrt(lengthSquared);
          out[o] = x * inverseLength;
          out[o + 1] = y * inverseLength;
          out[o + 2] = z * inverseLength;
        } else {
          out[o] = base[o];
          out[o + 1] = base[o + 1];
          out[o + 2] = base[o + 2];
        }
      }
    }
  }

  // Expands the base AABB by each axis's summed worst-case delta, assuming
  // weights stay in [0, 1] (the common authored range).
  // TODO(morph-bounds): account for weights outside [0, 1] and fold morph
  // extents into the skinned pose-union bake.
  void _expandBoundsForMorphRange() {
    final bounds = localBounds;
    if (bounds == null) return;
    final data = _morphData;
    final lo = [0.0, 0.0, 0.0];
    final hi = [0.0, 0.0, 0.0];
    for (var t = 0; t < data.targetCount; t++) {
      final offset = t * data.vertexCount * 3;
      for (var axis = 0; axis < 3; axis++) {
        var minDelta = 0.0;
        var maxDelta = 0.0;
        for (var v = 0; v < data.vertexCount; v++) {
          final delta = data.positionDeltas[offset + v * 3 + axis];
          if (delta < minDelta) minDelta = delta;
          if (delta > maxDelta) maxDelta = delta;
        }
        lo[axis] += minDelta;
        hi[axis] += maxDelta;
      }
    }
    final expanded = vm.Aabb3.minMax(
      bounds.min + vm.Vector3(lo[0], lo[1], lo[2]),
      bounds.max + vm.Vector3(hi[0], hi[1], hi[2]),
    );
    final center = (expanded.min + expanded.max) * 0.5;
    setLocalBounds(
      expanded,
      vm.Sphere.centerRadius(center, (expanded.max - center).length),
    );
  }
}
