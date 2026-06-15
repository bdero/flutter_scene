import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/resolve_pass.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Render-graph blackboard key for the selection mask: highlighted objects
/// drawn flat in their highlight color (coverage in alpha), everything else 0.
const String kSelectionMaskBlackboardKey = 'selection_mask';

/// How the selection outline (around nodes with a `Node.highlightColor`) is
/// drawn. Reachable through `Scene.highlightStyle`.
/// {@category Rendering}
class HighlightStyle {
  /// Outline width in screen pixels.
  double thickness = 3.0;
}

/// Whether [renderScene] has any visible highlighted item, i.e. whether the
/// selection-outline passes have anything to draw this frame.
bool sceneHasHighlights(RenderScene renderScene) {
  for (final item in renderScene.items) {
    if (item.visible && item.highlightColor != null) return true;
  }
  return false;
}

/// Process-lifetime cache of mask pipelines, keyed by vertex shader (skinned vs
/// unskinned). The fragment shader is constant, so at most two pipelines exist.
final Map<gpu.Shader, gpu.RenderPipeline> _maskPipelineCache = {};

/// Draws the highlighted objects' silhouettes flat into an offscreen mask,
/// published on the blackboard for [SelectionOutlinePass]. The mask has its own
/// cleared depth buffer (so a highlighted object self-occludes correctly) but
/// is not occluded by the rest of the scene, so the outline reads as a
/// selection highlight that shows through other geometry.
class SelectionMaskPass extends RenderGraphPass {
  SelectionMaskPass({
    required Camera camera,
    required RenderScene renderScene,
    required ui.Size dimensions,
    int layerMask = kRenderLayerAll,
  }) : _camera = camera,
       _renderScene = renderScene,
       _dimensions = dimensions,
       _layerMask = layerMask;

  final Camera _camera;
  final RenderScene _renderScene;
  final ui.Size _dimensions;
  final int _layerMask;

  @override
  String get name => 'SelectionMaskPass';

  @override
  void execute(RenderGraphContext context) {
    final width = _dimensions.width.toInt();
    final height = _dimensions.height.toInt();

    final mask = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: gpu.gpuContext.defaultColorFormat,
        debugName: 'selection_mask',
      ),
    );
    final depth = context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: width,
        height: height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        debugName: 'selection_mask_depth',
      ),
    );
    final target = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: mask, clearValue: Vector4.zero()),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthClearValue: 1.0,
      ),
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(target);
    final encoder = _MaskEncoder(
      renderPass,
      context.transientsBuffer,
      _camera.getViewTransform(_dimensions),
      _camera.position,
      _layerMask,
    );
    _renderScene.cull(encoder.frustum, encoder.submit);
    commandBuffer.submit();

    context.blackboard.set(kSelectionMaskBlackboardKey, mask);
  }
}

/// Records each highlighted item's geometry into the mask with the node's
/// highlight color. Mirrors the depth-prepass encoder (standard vertex shaders,
/// instancing/skinning, winding), paired with the flat `MaskFragment`.
class _MaskEncoder {
  _MaskEncoder(
    this._renderPass,
    this._transientsBuffer,
    this._cameraTransform,
    this._cameraPosition,
    this._layerMask,
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

  static final gpu.Shader _maskShader = baseShaderLibrary['MaskFragment']!;

  late final Frustum frustum;
  final Aabb3 cullScratchAabb = Aabb3();
  gpu.RenderPipeline? _boundPipeline;

  void submit(RenderItem item) {
    if (!item.visible) return;
    final highlight = item.highlightColor;
    if (highlight == null) return;
    if ((item.layers & _layerMask) == 0) return;
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

/// Composites a uniform-width outline around the selection mask onto the
/// display-referred image. Reads the display color and the mask from the
/// blackboard, writes [_output], and republishes the display color.
class SelectionOutlinePass extends RenderGraphPass {
  SelectionOutlinePass({
    required gpu.Texture output,
    required ui.Size dimensions,
    required double thickness,
  }) : _output = output,
       _dimensions = dimensions,
       _thickness = thickness;

  final gpu.Texture _output;
  final ui.Size _dimensions;
  final double _thickness;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader =
      baseShaderLibrary['OutlineFragment']!;

  static final gpu.DeviceBuffer _quadBuffer = gpu.gpuContext
      .createDeviceBufferWithCopy(
        ByteData.sublistView(
          Float32List.fromList(<double>[
            -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
            -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
          ]),
        ),
      );
  static final gpu.BufferView _quadView = gpu.BufferView(
    _quadBuffer,
    offsetInBytes: 0,
    lengthInBytes: 6 * 2 * 4,
  );

  static final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  @override
  String get name => 'SelectionOutlinePass';

  @override
  void execute(RenderGraphContext context) {
    final sceneColor = context.blackboard.require<gpu.Texture>(
      kDisplayColorBlackboardKey,
    );
    final mask = context.blackboard.require<gpu.Texture>(
      kSelectionMaskBlackboardKey,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _output)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _fragmentShader),
    );
    bindVertexBufferCompat(renderPass, _quadView, 6);

    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('scene_color'),
      sceneColor,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('selection_mask'),
      mask,
      sampler: _linearClamp,
    );

    // OutlineInfo std140: { vec2 texel_size; float thickness; float _pad; }.
    final w = _dimensions.width;
    final h = _dimensions.height;
    final info = Float32List(4)
      ..[0] = w == 0 ? 0.0 : 1.0 / w
      ..[1] = h == 0 ? 0.0 : 1.0 / h
      ..[2] = _thickness;
    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('OutlineInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );

    drawCompat(renderPass, 6);
    commandBuffer.submit();

    context.blackboard.set(kDisplayColorBlackboardKey, _output);
  }
}
