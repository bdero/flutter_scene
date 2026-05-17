import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/shaders.dart';

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
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    // Match the standard materials' winding / culling so the same faces
    // that are visible cast shadows; a depth bias on the receiver handles
    // self-shadow acne.
    _renderPass.setCullMode(gpu.CullMode.backFace);
    _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
  }

  final gpu.RenderPass _renderPass;
  final gpu.HostBuffer _transientsBuffer;
  final Matrix4 _lightSpaceMatrix;

  static final gpu.Shader _depthShader =
      baseShaderLibrary['DepthOnlyFragment']!;
  static final Vector3 _cameraPositionPlaceholder = Vector3.zero();

  /// Frustum of the light-space view-projection, used for per-item
  /// culling.
  late final Frustum frustum;

  /// Reusable AABB for the per-item cull check.
  final Aabb3 cullScratchAabb = Aabb3();

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
    final pipeline = gpu.gpuContext.createRenderPipeline(
      item.geometry.vertexShader,
      _depthShader,
    );
    _renderPass.bindPipeline(pipeline);

    final instances = item.instanceTransforms;
    if (instances != null) {
      for (final instanceTransform in instances) {
        item.geometry.bind(
          _renderPass,
          _transientsBuffer,
          item.worldTransform * instanceTransform,
          _lightSpaceMatrix,
          _cameraPositionPlaceholder,
        );
        _renderPass.draw();
      }
      return;
    }

    item.geometry.bind(
      _renderPass,
      _transientsBuffer,
      item.worldTransform,
      _lightSpaceMatrix,
      _cameraPositionPlaceholder,
    );
    _renderPass.draw();
  }
}
