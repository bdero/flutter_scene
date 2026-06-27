import 'package:flutter_scene/src/geometry/geometry.dart'
    show bindUnskinnedFrameInfo;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
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
    final geometry = item.geometry;
    // Unskinned casters draw depth through a position-only shader and layout;
    // skinned geometry falls back to its full vertex shader and bind.
    final depthVertex = geometry.depthOnlyVertex;
    final pipeline = resolvePipeline(
      depthVertex?.shader ?? geometry.vertexShader,
      _depthShader,
      vertexLayout: depthVertex?.layout ?? geometry.instancedVertexLayout,
    );
    if (!identical(_boundPipeline, pipeline)) {
      _renderPass.bindPipeline(pipeline);
      _boundPipeline = pipeline;
    }
    _renderPass.setPrimitiveType(geometry.primitiveType);

    // Binds the vertex/index buffers and the per-frame uniform for one draw.
    // The light-space matrix takes the place of the camera transform; the
    // camera position is unused by the shadow fragment shader.
    void bindDraw(Matrix4 worldTransform) {
      if (depthVertex != null) {
        geometry.bindPositionStream(_renderPass);
        bindUnskinnedFrameInfo(
          _renderPass,
          _transientsBuffer,
          depthVertex.shader,
          _lightSpaceMatrix,
          _cameraPositionPlaceholder,
        );
      } else {
        geometry.bind(
          _renderPass,
          _transientsBuffer,
          worldTransform,
          _lightSpaceMatrix,
          _cameraPositionPlaceholder,
        );
      }
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
        bindInstanceTransforms(_renderPass, packed.ccw);
        _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
        geometry.draw(_renderPass, instanceCount: packed.ccwCount);
      }
      if (packed.cwCount > 0) {
        bindInstanceTransforms(_renderPass, packed.cw);
        _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
        geometry.draw(_renderPass, instanceCount: packed.cwCount);
      }
      return;
    }

    bindDraw(item.worldTransform);
    if (geometry.instancedVertexLayout != null) {
      bindSingleInstanceTransform(_renderPass, item.worldTransform);
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
