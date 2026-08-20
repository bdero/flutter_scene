/// Geometry subclasses carrying glTF morph targets (blend shapes).
///
/// Two blend paths share one semantic, `base + sum(weight_i * delta_i)`
/// with morphing always applied before skinning:
///
///  * GPU (the default): the deltas upload once into an RGBA32F texture
///    (row band per target, see [MorphTexturePacking]) and the morphed
///    vertex shader sums the highest-magnitude [kMaxGpuMorphTargets]
///    weights per draw.
///  * CPU (the fallback): when the packed deltas exceed the guaranteed
///    texture dimensions ([kMorphTextureMaxDimension]), a weight change
///    re-blends position and normal into a fresh vertex upload.
///
/// The policy is deterministic: GPU whenever [computeMorphTexturePacking]
/// fits, CPU otherwise; [usesGpuMorphing] reports the choice.
library;

import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/morph_targets.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
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
    if (usesGpuMorphing) setVertexShaderName('MorphedUnskinnedVertex');
  }

  @override
  int get _strideInFloats => kUnskinnedPerVertexSize ~/ 4;

  /// On the GPU path the depth-style passes must run the full morphed
  /// vertex shader (a position-only fetch would draw the unmorphed base);
  /// the CPU path keeps the position-only fast path since its buffer
  /// already holds the blended positions.
  @override
  ({gpu.Shader shader, VertexLayoutDescriptor layout})? get depthOnlyVertex =>
      usesGpuMorphing ? null : super.depthOnlyVertex;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    super.bind(
      pass,
      transientsBuffer,
      modelTransform,
      cameraTransform,
      cameraPosition,
      shaderOverride: shaderOverride,
      depthBias: depthBias,
    );
    _bindMorphStage(pass, transientsBuffer, shaderOverride);
  }
}

/// Skinned geometry with morph targets, blended before the skin matrix is
/// applied on both paths.
///
/// A skinned morphed draw spends two vertex-stage samplers (the joints
/// texture plus the morph texture). With the 15-sampler lit fragment stage
/// that totals 17 combined units, one over the GLES 3.0 minimum of 16, so a
/// driver at the bare minimum cannot bind a lit skinned morphed draw (real
/// GLES3 hardware reports 32 or more).
/// TODO(morph-sampler-budget): pack the joint matrices and morph deltas
/// into one vertex-stage texture to fit the GLES minimum.
/// {@category Geometry}
class MorphedSkinnedGeometry extends SkinnedGeometry with _MorphBlending {
  /// Creates skinned geometry morphed by [morphTargets].
  MorphedSkinnedGeometry(MorphTargetData morphTargets) {
    _initMorphState(morphTargets);
    if (usesGpuMorphing) setVertexShaderName('MorphedSkinnedVertex');
  }

  @override
  int get _strideInFloats => kSkinnedPerVertexSize ~/ 4;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    super.bind(
      pass,
      transientsBuffer,
      modelTransform,
      cameraTransform,
      cameraPosition,
      shaderOverride: shaderOverride,
      depthBias: depthBias,
    );
    _bindMorphStage(pass, transientsBuffer, shaderOverride);
  }
}

/// Shared morph state and the two blend paths over the interleaved vertex
/// layouts.
///
/// On the CPU path a geometry shared by nodes holding different weights
/// re-blends on every draw.
/// TODO(morph-cpu-share): cache per-weight-set uploads for shared geometry.
mixin _MorphBlending on Geometry {
  late final MorphTargetData _morphData;
  MorphTexturePacking? _packing;

  // Base interleaved vertex floats and the index upload, kept so a CPU
  // blend can re-upload without the caller's buffers.
  Float32List? _baseVertexFloats;
  int _baseVertexCount = 0;
  ByteData? _baseIndices;
  gpu.IndexType _baseIndexType = gpu.IndexType.int16;

  // CPU path: the last-blended weights and the reused blend output.
  Float32List? _appliedWeights;
  Float32List? _blendScratch;
  bool _uploadingBlend = false;

  // GPU path: the per-draw weights, the once-uploaded delta texture, and
  // the reused MorphInfo uniform floats.
  Float32List? _gpuWeights;
  gpu.Texture? _morphTexture;
  final Float32List _morphInfoScratch = Float32List(
    4 + kMaxGpuMorphTargets * 4,
  );
  bool _warnedCustomVertexVariant = false;

  /// Floats per vertex of this geometry's interleaved layout. Position sits
  /// at offset 0 and normal at offset 3 in both layouts.
  int get _strideInFloats;

  @override
  MorphTargetData get morphTargets => _morphData;

  /// Whether this geometry blends on the GPU (the deltas fit the guaranteed
  /// texture dimensions) or falls back to CPU blending.
  bool get usesGpuMorphing => _packing != null;

  // Called by the subclass constructors.
  void _initMorphState(MorphTargetData data) {
    _morphData = data;
    _packing = computeMorphTexturePacking(data);
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
    if (usesGpuMorphing) {
      // Retained by reference: the render item hands the node's live list
      // right before each draw's bind, which reads it synchronously.
      _gpuWeights = weights;
      return;
    }
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

  // Binds the morph texture and the active (index, weight) pairs for one
  // draw. No-op on the CPU path (the vertex buffer already holds the
  // blend). A custom material's vertex variant has no morph stage, so those
  // draws render the unmorphed base.
  // TODO(morph-custom-materials): generate morphed vertex variants for
  // `.fmat` materials with a `vertex { }` block.
  void _bindMorphStage(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    gpu.Shader? shaderOverride,
  ) {
    final packing = _packing;
    if (packing == null) return;
    if (shaderOverride != null && !identical(shaderOverride, vertexShader)) {
      if (!_warnedCustomVertexVariant) {
        _warnedCustomVertexVariant = true;
        debugPrint(
          'A custom material vertex stage was bound to morphed geometry; '
          'its draws render without morphing.',
        );
      }
      return;
    }
    final shader = vertexShader;

    final texture = _morphTexture ??= _buildMorphTexture(packing);
    pass.bindTexture(
      shader.getUniformSlot('morph_texture'),
      texture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
        mipFilter: gpu.MipFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );

    final weights = _gpuWeights ?? _morphData.defaultWeights;
    final active = MorphTargetData.selectActiveTargets(weights);
    final scratch = _morphInfoScratch;
    scratch.fillRange(0, scratch.length, 0);
    scratch[0] = active.length.toDouble();
    scratch[1] = packing.width.toDouble();
    scratch[2] = packing.rowsPerAttribute.toDouble();
    scratch[3] = packing.includesNormals ? 1 : 0;
    for (var i = 0; i < active.length; i++) {
      scratch[4 + i * 4] = packing.bandStart(active[i].index).toDouble();
      scratch[4 + i * 4 + 1] = active[i].weight;
    }
    pass.bindUniform(
      shader.getUniformSlot('MorphInfo'),
      transientsBuffer.emplace(ByteData.sublistView(scratch)),
    );
  }

  // Uploads the packed delta texels once. The texture is static content, so
  // no ring is needed.
  gpu.Texture _buildMorphTexture(MorphTexturePacking packing) {
    final texels = buildMorphTexturePayload(_morphData, packing);
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      packing.width,
      packing.height,
      format: gpu.PixelFormat.r32g32b32a32Float,
    );
    texture.overwrite(ByteData.sublistView(texels));
    return texture;
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
