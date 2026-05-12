import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/scene_encoder.dart';
import 'package:flutter_scene/src/shaders.dart';

/// A [SceneDrawList] that records each opaque shadow caster's depth into a
/// shadow-map render pass, from a directional light's point of view.
///
/// Reuses the engine's standard vertex shaders (so unskinned and skinned
/// geometry both cast shadows) paired with the `DepthOnlyFragment`
/// shader, supplying the light-space view-projection matrix in place of
/// the camera transform. Translucent materials don't cast shadows.
class ShadowEncoder implements SceneDrawList {
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

  @override
  late final Frustum frustum;

  @override
  final Aabb3 cullScratchAabb = Aabb3();

  @override
  void encode(Matrix4 worldTransform, Geometry geometry, Material material) {
    if (!material.isOpaque()) {
      return;
    }
    _renderPass.clearBindings();
    final pipeline = gpu.gpuContext.createRenderPipeline(
      geometry.vertexShader,
      _depthShader,
    );
    _renderPass.bindPipeline(pipeline);
    geometry.bind(
      _renderPass,
      _transientsBuffer,
      worldTransform,
      _lightSpaceMatrix,
      _cameraPositionPlaceholder,
    );
    _renderPass.draw();
  }
}
