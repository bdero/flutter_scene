import 'package:flutter_scene/src/geometry/geometry.dart'
    show bindUnskinnedFrameInfo;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart' show ShadowCasterFaces;
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
  }) : _filter = filter {
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
    _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
  }

  final gpu.RenderPass _renderPass;
  final TransientWriter _transientsBuffer;
  final Matrix4 _lightSpaceMatrix;
  final ShadowCasterFilter _filter;

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

  /// Reusable AABB for the per-item cull check.
  final Aabb3 cullScratchAabb = Aabb3();

  /// The pipeline currently bound on the render pass, or null before the
  /// first draw. `clearBindings` leaves the pipeline in place, so
  /// consecutive casters that share one only bind it once.
  gpu.RenderPipeline? _boundPipeline;

  /// Records [item]'s depth, unless it is hidden, translucent (no shadow),
  /// or culled by the light frustum.
  void submit(RenderItem item) {
    if (!item.visible) return;
    if (!item.material.isOpaque()) return;
    if (_filter == ShadowCasterFilter.staticOnly && !item.shadowStatic) return;
    if (_filter == ShadowCasterFilter.dynamicOnly && item.shadowStatic) return;
    if (item.frustumCulled) {
      final bounds = item.cullBounds;
      if (bounds != null) {
        cullScratchAabb
          ..copyFrom(bounds)
          ..transform(item.worldTransform);
        if (!frustum.intersectsWithAabb3(cullScratchAabb)) return;
      }
    }
    _renderPass.clearBindings();
    final geometry = item.geometry;
    // An alpha-masked caster draws through the masked depth shader (so only
    // its opaque texels cast) and needs the full-vertex varyings, so it skips
    // the position-only path. It also keeps the material's own culling, so the
    // faces that are visible are the faces that cast; the caster-face mode's
    // second-depth trick has no meaning for cutout sheets.
    final masked = item.material.depthAlphaMasked;
    final fragmentShader = masked ? _maskedDepthShader : _depthShader;
    final cullMode = masked ? item.material.renderCullMode : _casterCullMode;
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
    final pipeline = resolvePipeline(
      activeVertex,
      fragmentShader,
      vertexLayout: depthVertex?.layout ?? geometry.instancedVertexLayout,
    );
    if (!identical(_boundPipeline, pipeline)) {
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
        );
      } else {
        geometry.bind(
          _renderPass,
          _transientsBuffer,
          worldTransform,
          _lightSpaceMatrix,
          _cameraPosition,
          shaderOverride: materialVertex,
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
                ? gpu.WindingOrder.clockwise
                : gpu.WindingOrder.counterClockwise,
          );
          geometry.draw(_renderPass);
        }
        return;
      }
      bindDraw(item.worldTransform);
      final packed = packInstanceTransforms(
        item.worldTransform,
        instances,
        nodeWindingFlipped: item.windingFlipped,
      );
      if (packed.ccwCount > 0) {
        bindInstanceTransforms(_renderPass, packed.ccw, slot: instanceSlot);
        _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
        geometry.draw(_renderPass, instanceCount: packed.ccwCount);
      }
      if (packed.cwCount > 0) {
        bindInstanceTransforms(_renderPass, packed.cw, slot: instanceSlot);
        _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
        geometry.draw(_renderPass, instanceCount: packed.cwCount);
      }
      return;
    }

    bindDraw(item.worldTransform);
    // Skip the model-transform instance buffer for geometry that supplies its
    // own per-instance buffer (see the color encoder), or it clobbers the
    // stream slot.
    if (geometry.instancedVertexLayout != null &&
        geometry.bindsModelTransformInstance) {
      bindSingleInstanceTransform(
        _renderPass,
        item.worldTransform,
        slot: instanceSlot,
      );
    }
    // Mirrored casters reverse winding; flip the cull order so the same faces
    // that are visible also cast shadows.
    _renderPass.setWindingOrder(
      item.windingFlipped
          ? gpu.WindingOrder.clockwise
          : gpu.WindingOrder.counterClockwise,
    );
    geometry.draw(_renderPass);
  }
}
