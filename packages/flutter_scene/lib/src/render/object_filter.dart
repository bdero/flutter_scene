import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart'
    show bindUnskinnedFrameInfo;
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Selects which scene nodes an object-filtered draw includes.
///
/// Used by the object-filtered draw (the selection mask, and the public
/// `RenderPassContext.drawObjects`) to pick a subset of the scene's
/// drawable geometry to render flat into a target.
/// {@category Rendering}
class NodeFilter {
  /// Includes every visible drawable node.
  const NodeFilter.all() : _layerMask = null, _predicate = null;

  /// Includes nodes whose render layers intersect [mask].
  const NodeFilter.layers(int mask) : _layerMask = mask, _predicate = null;

  /// Includes nodes for which [predicate] returns true.
  ///
  /// The predicate is called with each candidate node every frame, so keep
  /// it cheap (a set membership test is ideal).
  const NodeFilter.where(bool Function(Object node) predicate)
    : _predicate = predicate,
      _layerMask = null;

  final int? _layerMask;
  final bool Function(Object node)? _predicate;

  /// Whether [item] passes this filter.
  bool _matches(RenderItem item, int viewLayerMask) {
    if ((item.layers & viewLayerMask) == 0) return false;
    final mask = _layerMask;
    if (mask != null) return (item.layers & mask) != 0;
    final predicate = _predicate;
    if (predicate != null) {
      final node = item.sourceNode;
      return node != null && predicate(node);
    }
    return true;
  }
}

/// Draws a filtered set of the scene's geometry flat into [target], each
/// item filled with a solid color (coverage in alpha), with its own cleared
/// depth so the filtered objects self-occlude but are not occluded by the
/// rest of the scene (an x-ray silhouette, what a selection mask wants).
///
/// Reuses the engine's geometry binding (instancing, skinning, winding) so
/// the silhouette matches the main pass exactly on every backend. This is
/// the shared implementation behind the built-in selection mask and the
/// public object-filtered draw.
void renderObjectMask({
  required gpu.Texture target,
  required gpu.Texture depth,
  required Vector4 clearColor,
  required Matrix4 cameraTransform,
  required Vector3 cameraPosition,
  required RenderScene renderScene,
  required TransientWriter transientsBuffer,
  required int layerMask,
  required NodeFilter filter,
  required Vector4 Function(RenderItem item) colorOf,
}) {
  final renderTarget = gpu.RenderTarget.singleColor(
    gpu.ColorAttachment(texture: target, clearValue: clearColor),
    depthStencilAttachment: gpu.DepthStencilAttachment(
      texture: depth,
      depthClearValue: 1.0,
    ),
  );
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(renderTarget);
  final encoder = _ObjectMaskEncoder(
    renderPass,
    transientsBuffer,
    cameraTransform,
    cameraPosition,
    layerMask,
    filter,
    colorOf,
  );
  renderScene.cull(encoder.frustum, encoder.submit);
  rendererSubmissions.submit(commandBuffer);
}

/// Records each filtered item's geometry flat into a color mask. Mirrors the
/// depth-prepass encoder (standard vertex shaders, instancing/skinning,
/// winding), paired with the flat `MaskFragment`.
class _ObjectMaskEncoder {
  _ObjectMaskEncoder(
    this._renderPass,
    this._transientsBuffer,
    this._cameraTransform,
    this._cameraPosition,
    this._layerMask,
    this._filter,
    this._colorOf,
  ) {
    frustum = Frustum.matrix(_cameraTransform);
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    _renderPass.setCullMode(gpu.CullMode.backFace);
    _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
  }

  final gpu.RenderPass _renderPass;
  final TransientWriter _transientsBuffer;
  final Matrix4 _cameraTransform;
  final Vector3 _cameraPosition;
  final int _layerMask;
  final NodeFilter _filter;
  final Vector4 Function(RenderItem item) _colorOf;

  static final gpu.Shader _maskShader = baseShaderLibrary['MaskFragment']!;

  late final Frustum frustum;
  final Aabb3 cullScratchAabb = Aabb3();
  gpu.RenderPipeline? _boundPipeline;

  void submit(RenderItem item) {
    if (!item.visible) return;
    if (!_filter._matches(item, _layerMask)) return;
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
    // Skinned items draw through the full bind path below; apply this item's
    // skeleton to the (possibly shared) geometry first.
    item.applyJointsTexture(geometry);
    // Unskinned geometry fills the mask through a position-only shader and
    // layout; skinned geometry falls back to its full vertex shader and bind.
    // A `vertex { }` material displaces geometry, so pick against its displaced
    // silhouette by running the material's vertex variant here too. This pass
    // binds the real camera, so a camera-relative displacement is correct.
    final depthVertex = geometry.depthOnlyVertex;
    final materialVertex = item.material.materialVertexShader(
      depthVertex != null ? 'depth' : geometry.materialVertexVariant,
    );
    final activeVertex =
        materialVertex ?? depthVertex?.shader ?? geometry.vertexShader;
    final pipeline = resolvePipeline(
      activeVertex,
      _maskShader,
      vertexLayout: depthVertex?.layout ?? geometry.instancedVertexLayout,
    );
    if (!identical(_boundPipeline, pipeline)) {
      _renderPass.bindPipeline(pipeline);
      _boundPipeline = pipeline;
    }
    _renderPass.setPrimitiveType(geometry.primitiveType);
    // Per item, since a double-sided geometry (a billboard) would otherwise be
    // back-face culled out of the mask. Reset for every item so it does not
    // leak to the next.
    _renderPass.setCullMode(
      geometry.isDoubleSided ? gpu.CullMode.none : gpu.CullMode.backFace,
    );
    final highlight = _colorOf(item);
    final color = Float32List(4)
      ..[0] = highlight.x
      ..[1] = highlight.y
      ..[2] = highlight.z
      ..[3] = highlight.w == 0 ? 1.0 : highlight.w;
    _renderPass.bindUniform(
      _maskShader.getUniformSlot('MaskInfo'),
      _transientsBuffer.emplace(ByteData.sublistView(color)),
    );

    // Binds the vertex/index buffers and the per-frame uniform for one draw.
    void bindDraw(Matrix4 worldTransform) {
      if (depthVertex != null) {
        geometry.bindPositionStream(_renderPass);
        bindUnskinnedFrameInfo(
          _renderPass,
          _transientsBuffer,
          activeVertex,
          _cameraTransform,
          _cameraPosition,
        );
      } else {
        geometry.bind(
          _renderPass,
          _transientsBuffer,
          worldTransform,
          _cameraTransform,
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
    }

    final instances = item.instanceTransforms;
    if (instances != null) {
      if (geometry.instancedVertexLayout == null) {
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
    // Only bind a model-transform instance buffer when the geometry expects one
    // at the slot after its vertex streams. A geometry that supplies its own
    // per-instance buffer (a billboard batch) sets this false; binding here
    // would clobber slot 1 and the shader would read its instance attributes as
    // a transform matrix.
    if (geometry.instancedVertexLayout != null &&
        geometry.bindsModelTransformInstance) {
      bindSingleInstanceTransform(_renderPass, item.worldTransform);
    }
    _renderPass.setWindingOrder(
      item.windingFlipped
          ? gpu.WindingOrder.clockwise
          : gpu.WindingOrder.counterClockwise,
    );
    geometry.draw(_renderPass);
  }
}
