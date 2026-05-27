import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/y_flip.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Process-lifetime cache of depth-pass render pipelines, keyed by vertex
/// shader. The depth fragment shader is constant, so only the (skinned /
/// unskinned) vertex shader varies; the engine loads each shader once, so
/// the depth pass only ever needs two pipelines. Caching them keeps the
/// shadow pass from rebuilding a pipeline for every caster, every cascade,
/// every frame.
final Map<gpu.Shader, gpu.RenderPipeline> _depthPipelineCache = {};

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
  ) {
    frustum = Frustum.matrix(_lightSpaceMatrix);
    // Matrix sent to the vertex shader; carries the GLES render-to-texture
    // Y-flip (see y_flip.dart). Frustum culling keeps the unflipped one.
    _shaderLightSpaceMatrix = applyBackendYFlip(_lightSpaceMatrix);
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    // Match the standard materials' winding / culling so the same faces
    // that are visible cast shadows; a depth bias on the receiver handles
    // self-shadow acne.
    _renderPass.setCullMode(gpu.CullMode.backFace);
    _renderPass.setWindingOrder(
      backendWinding(gpu.WindingOrder.counterClockwise),
    );
  }

  final gpu.RenderPass _renderPass;
  final gpu.HostBuffer _transientsBuffer;
  final Matrix4 _lightSpaceMatrix;
  late final Matrix4 _shaderLightSpaceMatrix;

  static final gpu.Shader _depthShader =
      baseShaderLibrary['DepthOnlyFragment']!;
  static final Vector3 _cameraPositionPlaceholder = Vector3.zero();

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
    final pipeline = _depthPipelineCache[item.geometry.vertexShader] ??= gpu
        .gpuContext
        .createRenderPipeline(item.geometry.vertexShader, _depthShader);
    if (!identical(_boundPipeline, pipeline)) {
      _renderPass.bindPipeline(pipeline);
      _boundPipeline = pipeline;
    }
    _renderPass.setPrimitiveType(item.geometry.primitiveType);

    final instances = item.instanceTransforms;
    if (instances != null) {
      for (final instanceTransform in instances) {
        item.geometry.bind(
          _renderPass,
          _transientsBuffer,
          item.worldTransform * instanceTransform,
          _shaderLightSpaceMatrix,
          _cameraPositionPlaceholder,
        );
        final flip =
            item.windingFlipped != (instanceTransform.determinant() < 0);
        _renderPass.setWindingOrder(
          backendWinding(
            flip
                ? gpu.WindingOrder.clockwise
                : gpu.WindingOrder.counterClockwise,
          ),
        );
        item.geometry.draw(_renderPass);
      }
      return;
    }

    item.geometry.bind(
      _renderPass,
      _transientsBuffer,
      item.worldTransform,
      _shaderLightSpaceMatrix,
      _cameraPositionPlaceholder,
    );
    // Mirrored casters reverse winding; flip the cull order so the same faces
    // that are visible also cast shadows.
    _renderPass.setWindingOrder(
      backendWinding(
        item.windingFlipped
            ? gpu.WindingOrder.clockwise
            : gpu.WindingOrder.counterClockwise,
      ),
    );
    item.geometry.draw(_renderPass);
  }
}
