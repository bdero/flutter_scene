import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/shaders.dart';

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

/// Process-lifetime cache of flat-fill pipelines, keyed by vertex shader
/// (skinned vs unskinned). The fragment shader is constant, so at most two
/// pipelines exist.
final Map<gpu.Shader, gpu.RenderPipeline> _maskPipelineCache = {};

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
  required gpu.HostBuffer transientsBuffer,
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
  commandBuffer.submit();
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
  final gpu.HostBuffer _transientsBuffer;
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
    final pipeline = _maskPipelineCache[item.geometry.vertexShader] ??= gpu
        .gpuContext
        .createRenderPipeline(
          item.geometry.vertexShader,
          _maskShader,
          vertexLayout: item.geometry.instancedVertexLayout,
        );
    if (!identical(_boundPipeline, pipeline)) {
      _renderPass.bindPipeline(pipeline);
      _boundPipeline = pipeline;
    }
    _renderPass.setPrimitiveType(item.geometry.primitiveType);
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

    final instances = item.instanceTransforms;
    if (instances != null) {
      if (item.geometry.instancedVertexLayout == null) {
        for (final instanceTransform in instances) {
          item.geometry.bind(
            _renderPass,
            _transientsBuffer,
            item.worldTransform * instanceTransform,
            _cameraTransform,
            _cameraPosition,
          );
          final flip =
              item.windingFlipped != (instanceTransform.determinant() < 0);
          _renderPass.setWindingOrder(
            flip
                ? gpu.WindingOrder.clockwise
                : gpu.WindingOrder.counterClockwise,
          );
          item.geometry.draw(_renderPass);
        }
        return;
      }
      item.geometry.bind(
        _renderPass,
        _transientsBuffer,
        item.worldTransform,
        _cameraTransform,
        _cameraPosition,
      );
      final packed = packInstanceTransforms(
        item.worldTransform,
        instances,
        nodeWindingFlipped: item.windingFlipped,
      );
      if (packed.ccwCount > 0) {
        bindInstanceTransforms(_renderPass, packed.ccw);
        _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
        item.geometry.draw(_renderPass, instanceCount: packed.ccwCount);
      }
      if (packed.cwCount > 0) {
        bindInstanceTransforms(_renderPass, packed.cw);
        _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
        item.geometry.draw(_renderPass, instanceCount: packed.cwCount);
      }
      return;
    }

    item.geometry.bind(
      _renderPass,
      _transientsBuffer,
      item.worldTransform,
      _cameraTransform,
      _cameraPosition,
    );
    if (item.geometry.instancedVertexLayout != null) {
      bindSingleInstanceTransform(_renderPass, item.worldTransform);
    }
    _renderPass.setWindingOrder(
      item.windingFlipped
          ? gpu.WindingOrder.clockwise
          : gpu.WindingOrder.counterClockwise,
    );
    item.geometry.draw(_renderPass);
  }
}
