import 'package:flutter_scene/src/geometry/geometry.dart'
    show Geometry, bindUnskinnedFrameInfo;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart' show ShadowCasterFaces;
import 'package:flutter_scene/src/render/instance_batching.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Which shadow casters a [ShadowEncoder] draws, keyed off
/// `RenderItem.shadowStatic`. The shadow cache renders static casters into
/// reusable tiles and dynamic casters on top every frame.
enum ShadowCasterFilter { all, staticOnly, dynamicOnly }

/// Whether [item] belongs in a shadow map drawn under [filter] for a light
/// whose casters are limited to [casterChannelMask].
///
/// The view-independent half of [ShadowEncoder.submit] (frustum culling and
/// material opacity are the rest), pulled out so the filter and channel rules
/// are testable without a render pass. Ordered so the common rejection is a
/// plain flag read.
bool shadowCasterAccepted(
  RenderItem item,
  ShadowCasterFilter filter,
  int casterChannelMask,
) {
  if (filter == ShadowCasterFilter.staticOnly && !item.shadowStatic) {
    return false;
  }
  if (filter == ShadowCasterFilter.dynamicOnly && item.shadowStatic) {
    return false;
  }
  if (!item.castsShadows) return false;
  if ((item.lightChannelMask & casterChannelMask) == 0) return false;
  return item.visible;
}

/// Records each opaque shadow caster's depth into a shadow-map render
/// pass, from a directional light's point of view.
///
/// Reuses the engine's standard vertex shaders (so unskinned and skinned
/// geometry both cast shadows) paired with the `DepthOnlyFragment`
/// shader, supplying the light-space view-projection matrix in place of
/// the camera transform. Translucent materials don't cast shadows.
class ShadowEncoder {
  ShadowEncoder(
    this._renderPass,
    this._transientsBuffer,
    this._lightSpaceMatrix,
    this._cameraPosition,
    ShadowCasterFaces casterFaces, {
    ShadowCasterFilter filter = ShadowCasterFilter.all,
    int casterChannelMask = 0xFF,
  }) : _filter = filter,
       _casterChannelMask = casterChannelMask {
    frustum = Frustum.matrix(_lightSpaceMatrix);
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    // Cull the complement of the faces that should cast: rendering front faces
    // (the default) means culling back faces, and vice versa. With base CCW
    // winding (flipped per-item for mirrored casters below), back-face culling
    // keeps the light-facing faces. [ShadowCasterFaces.back] (second-depth)
    // suits solid geometry, recording the far face to avoid self-shadow acne.
    _casterCullMode = switch (casterFaces) {
      ShadowCasterFaces.front => gpu.CullMode.backFace,
      ShadowCasterFaces.back => gpu.CullMode.frontFace,
      ShadowCasterFaces.both => gpu.CullMode.none,
    };
    _renderPass.setCullMode(_casterCullMode);
    _currentCullMode = _casterCullMode;
    _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
  }

  final gpu.RenderPass _renderPass;
  final TransientWriter _transientsBuffer;
  final Matrix4 _lightSpaceMatrix;
  final ShadowCasterFilter _filter;

  // The light's shadow-caster channels. An item casts only when its node's
  // light channels intersect these, independently of whether the light
  // shades it.
  final int _casterChannelMask;

  // The scene camera position, bound as FrameInfo.camera_position so a
  // `vertex { }` material's camera-relative displacement (e.g. a world curve)
  // bends shadow casters the same way as the color pass. The depth fragment
  // shader ignores it, so it is harmless for materials without a vertex stage.
  final Vector3 _cameraPosition;

  static final gpu.Shader _depthShader =
      baseShaderLibrary['DepthOnlyFragment']!;
  static final gpu.Shader _maskedDepthShader =
      baseShaderLibrary['DepthOnlyMaskedFragment']!;

  /// The cull mode the light's caster-face setting maps to, applied to
  /// non-masked casters.
  late final gpu.CullMode _casterCullMode;

  /// The cull mode currently set on the pass; alpha-masked casters switch to
  /// their material's own culling and back (see [submit]).
  late gpu.CullMode _currentCullMode;

  /// Frustum of the light-space view-projection, used for per-item
  /// culling.
  late final Frustum frustum;

  final Aabb3 _cullScratchAabb = Aabb3();

  /// The pipeline currently bound on the render pass, or null before the
  /// first draw. `clearBindings` leaves the pipeline in place, so
  /// consecutive casters that share one only bind it once.
  gpu.RenderPipeline? _boundPipeline;
  final List<RenderItem> _records = [];
  // See SceneEncoder._batchPool: refilled per group, read-only downstream.
  final InstanceDataBatchPool _batchPool = InstanceDataBatchPool();

  /// Records [item]'s depth, unless it is hidden, translucent (no shadow),
  /// or culled by the light frustum.
  void submit(RenderItem item) => _submit(item, false);

  /// Records an item already accepted by [RenderScene.cull].
  void submitCulled(RenderItem item) => _submit(item, true);

  void _submit(RenderItem item, bool alreadyCulled) {
    // The flag and channel checks run first: the dynamic composite iterates
    // the whole item list (most of which is static), so the common case must
    // reject before any virtual call.
    if (!shadowCasterAccepted(item, _filter, _casterChannelMask)) return;
    if (!item.material.isOpaque()) return;
    if (!alreadyCulled && item.frustumCulled) {
      final bounds = item.cullBounds;
      if (bounds != null) {
        _cullScratchAabb
          ..copyFrom(bounds)
          ..transform(item.worldTransform);
        if (!frustum.intersectsWithAabb3(_cullScratchAabb)) return;
      }
    }
    _records.add(item);
  }

  /// Emits the accepted casters, merging compatible spatial cells back into
  /// one hardware-instanced draw after culling.
  void flush() {
    _records.sort((a, b) {
      final byMaterial = a.materialIdentity.compareTo(b.materialIdentity);
      if (byMaterial != 0) return byMaterial;
      return a.geometryIdentity.compareTo(b.geometryIdentity);
    });
    var index = 0;
    while (index < _records.length) {
      final first = _records[index];
      final end = depthBatchEnd(_records, index);
      if (end > index + 1) {
        _batchPool.reset();
        for (var batchIndex = index; batchIndex < end; batchIndex++) {
          _batchPool.addFor(_records[batchIndex], indices: null);
        }
        final batches = _batchPool.batches;
        _encode(first, batches: batches);
        index = end;
        continue;
      }
      _encode(first);
      index++;
    }
    _records.clear();
  }

  void _encode(RenderItem item, {List<InstanceDataBatch>? batches}) {
    final geometry = item.geometry;
    // Skinned casters bind their joints texture through the full-vertex
    // path below; apply this item's skeleton to the (possibly shared)
    // geometry first.
    item.applyJointsTexture(geometry);
    item.applyMorphWeights(geometry);
    // An alpha-masked caster draws through the masked depth shader (so only
    // its opaque texels cast) and needs the full-vertex varyings, so it skips
    // the position-only path. It also keeps the material's own culling, so the
    // faces that are visible are the faces that cast; the caster-face mode's
    // second-depth trick has no meaning for cutout sheets.
    final masked = item.material.depthAlphaMasked;
    final fragmentShader = masked ? _maskedDepthShader : _depthShader;
    // A double-sided caster records every face regardless of the light's
    // caster-face mode or the material's culling, which is what closes the
    // light leak through single-sided geometry.
    final cullMode = item.shadowDoubleSided
        ? gpu.CullMode.none
        : (masked ? item.material.renderCullMode : _casterCullMode);
    if (cullMode != _currentCullMode) {
      _renderPass.setCullMode(cullMode);
      _currentCullMode = cullMode;
    }
    // Unskinned casters draw depth through a position-only shader and layout;
    // skinned geometry falls back to its full vertex shader and bind.
    // A `vertex { }` material displaces geometry in the color pass, so run its
    // vertex variant here too or the shadow detaches from the visible surface.
    final depthVertex = masked ? null : geometry.depthOnlyVertex;
    final materialVertex = item.material.materialVertexShader(
      depthVertex != null ? 'depth' : geometry.materialVertexVariant,
    );
    final activeVertex =
        materialVertex ?? depthVertex?.shader ?? geometry.vertexShader;
    // A masked caster runs the material's color vertex variant, which declares
    // its per-instance attribute inputs, so the instance record has to be as
    // wide here as in the color pass.
    final instanceSchema = depthVertex == null
        ? item.material.instanceAttributes
        : null;
    final attributeFloats = instanceSchema?.floatCount ?? 0;
    final pipeline = resolvePipeline(
      activeVertex,
      fragmentShader,
      vertexLayout:
          depthVertex?.layout ??
          geometry.instancedVertexLayoutFor(instanceSchema),
    );
    if (!identical(_boundPipeline, pipeline)) {
      _renderPass.clearBindings();
      _renderPass.bindPipeline(pipeline);
      _boundPipeline = pipeline;
    }
    _renderPass.setPrimitiveType(geometry.primitiveType);

    // Binds the vertex/index buffers and the per-frame uniform for one draw.
    // The light-space matrix takes the place of the camera transform (the depth
    // fragment shader ignores camera_position, but a material's Vertex() hook
    // reads it, so the real camera position is bound).
    void bindDraw(Matrix4 worldTransform) {
      if (depthVertex != null) {
        geometry.bindPositionStream(_renderPass);
        bindUnskinnedFrameInfo(
          _renderPass,
          _transientsBuffer,
          activeVertex,
          _lightSpaceMatrix,
          _cameraPosition,
          depthBias: 0.0,
        );
      } else {
        geometry.bind(
          _renderPass,
          _transientsBuffer,
          worldTransform,
          _lightSpaceMatrix,
          _cameraPosition,
          shaderOverride: materialVertex,
          depthBias: 0.0,
        );
      }
      if (materialVertex != null) {
        item.material.bindVertexStage(
          _renderPass,
          materialVertex,
          _transientsBuffer,
        );
      }
      if (masked) {
        item.material.bindDepthAlphaMask(
          _renderPass,
          fragmentShader,
          _transientsBuffer,
        );
      }
    }

    // The instance-rate model transform sits in the slot after the bound
    // vertex streams: slot 1 on the position-only path, slot
    // [vertexStreamCount] when the full stream set is bound (masked casters),
    // matching the prepass and color encoders.
    final instanceSlot = depthVertex != null ? 1 : geometry.vertexStreamCount;

    if (batches != null) {
      bindDraw(_identityTransform);
      final PackedInstances packed = depthVertex == null
          ? packInstanceDataBatches(
              batches,
              attributeFloats: attributeFloats,
              scratch: transientInstancePackingScratch,
            )
          : packInstanceTransformBatches(
              batches,
              scratch: transientInstancePackingScratch,
            );
      _drawPacked(geometry, packed, depthVertex == null, instanceSlot);
      return;
    }

    final instances = item.instanceTransforms;
    if (instances != null) {
      if (geometry.instancedVertexLayout == null) {
        // Skinned geometry has no instance-attribute path; loop.
        for (final instanceTransform in instances) {
          bindDraw(item.worldTransform * instanceTransform);
          final flip =
              item.windingFlipped != (instanceTransform.determinant() < 0);
          _renderPass.setWindingOrder(
            flip
                ? gpu.WindingOrder.counterClockwise
                : gpu.WindingOrder.clockwise,
          );
          geometry.draw(_renderPass);
        }
        return;
      }
      bindDraw(item.worldTransform);
      final packedWorldData = item.instanceWorldData;
      final packedWinding = item.instanceWorldWindingFlipped;
      final cached = packedWorldData == null || packedWinding == null
          ? null
          : transientInstancePackingScratch.singleCachedBatch(
              packedWorldData: packedWorldData,
              packedWindingFlipped: packedWinding,
              attributeFloats: item.instanceAttributeFloats,
            );
      final PackedInstances packed = depthVertex == null
          ? (cached == null
                ? packInstanceData(
                    item.worldTransform,
                    instances,
                    item.instanceColors!,
                    nodeWindingFlipped: item.windingFlipped,
                    instanceWindingFlipped: item.instanceWindingFlipped,
                    attributeData: item.instanceAttributeData,
                    attributeFloats: attributeFloats,
                    scratch: transientInstancePackingScratch,
                  )
                : packInstanceDataBatches(
                    cached,
                    attributeFloats: attributeFloats,
                    scratch: transientInstancePackingScratch,
                  ))
          : (cached == null
                ? packInstanceTransforms(
                    item.worldTransform,
                    instances,
                    nodeWindingFlipped: item.windingFlipped,
                    instanceWindingFlipped: item.instanceWindingFlipped,
                    scratch: transientInstancePackingScratch,
                  )
                : packInstanceTransformBatches(
                    cached,
                    scratch: transientInstancePackingScratch,
                  ));
      _drawPacked(geometry, packed, depthVertex == null, instanceSlot);
      transientInstancePackingScratch.releaseSingleBatch();
      return;
    }

    bindDraw(item.worldTransform);
    // Skip the model-transform instance buffer for geometry that supplies its
    // own per-instance buffer (see the color encoder), or it clobbers the
    // stream slot.
    if (geometry.instancedVertexLayout != null &&
        geometry.bindsModelTransformInstance) {
      if (depthVertex == null) {
        bindSingleInstanceData(
          _renderPass,
          item.worldTransform,
          slot: instanceSlot,
          attributeFloats: attributeFloats,
        );
      } else {
        bindSingleInstanceTransform(
          _renderPass,
          item.worldTransform,
          slot: instanceSlot,
        );
      }
    }
    // Mirrored casters reverse winding; flip the cull order so the same faces
    // that are visible also cast shadows.
    _renderPass.setWindingOrder(
      item.windingFlipped
          ? gpu.WindingOrder.counterClockwise
          : gpu.WindingOrder.clockwise,
    );
    geometry.draw(_renderPass);
  }

  static final Matrix4 _identityTransform = Matrix4.identity();

  void _drawPacked(
    Geometry geometry,
    PackedInstances packed,
    bool withColor,
    int instanceSlot,
  ) {
    if (packed.ccwCount > 0) {
      if (withColor) {
        bindInstanceData(_renderPass, packed.ccw, slot: instanceSlot);
      } else {
        bindInstanceTransforms(_renderPass, packed.ccw, slot: instanceSlot);
      }
      _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
      geometry.draw(_renderPass, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      if (withColor) {
        bindInstanceData(_renderPass, packed.cw, slot: instanceSlot);
      } else {
        bindInstanceTransforms(_renderPass, packed.cw, slot: instanceSlot);
      }
      _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
      geometry.draw(_renderPass, instanceCount: packed.cwCount);
    }
  }
}
