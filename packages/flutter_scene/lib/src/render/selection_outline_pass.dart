import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render/object_filter.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/resolve_pass.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

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
    required gpu.PixelFormat colorFormat,
    int layerMask = kRenderLayerAll,
  }) : _camera = camera,
       _renderScene = renderScene,
       _dimensions = dimensions,
       _colorFormat = colorFormat,
       _layerMask = layerMask;

  final Camera _camera;
  final RenderScene _renderScene;
  final ui.Size _dimensions;
  final gpu.PixelFormat _colorFormat;
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
        format: _colorFormat,
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

    renderObjectMask(
      target: mask,
      depth: depth,
      clearColor: Vector4.zero(),
      cameraTransform: _camera.getViewTransform(_dimensions),
      cameraPosition: _camera.position,
      renderScene: _renderScene,
      transientsBuffer: context.transientsBuffer,
      layerMask: _layerMask,
      filter: NodeFilter.where((node) => (node as Node).highlightColor != null),
      colorOf: (item) => item.highlightColor!,
    );

    context.blackboard.set(kSelectionMaskBlackboardKey, mask);
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
    rendererSubmissions.submit(commandBuffer);

    context.blackboard.set(kDisplayColorBlackboardKey, _output);
  }
}
