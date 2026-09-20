import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/resolve_pass.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;

/// Render-graph blackboard key for the display-referred layer [ScenePass]
/// draws, which [DisplayReferredCompositePass] blends onto the resolved image.
const String kDisplayReferredBlackboardKey = 'display_referred_color';

/// Whether the scene holds a visible display-referred surface (see
/// [Material.displayReferred]), which the frame pays the extra layer for.
bool sceneHasDisplayReferred(RenderScene renderScene) {
  for (final item in renderScene.items) {
    if (!item.visible) continue;
    if (item.material.displayReferred) return true;
    // The encoder draws the selected level's material, not the item's, so a
    // level that opts in has to activate the layer even when the fallback
    // does not. Which level the view selects is not known here, so any level
    // counts: over-activating costs an unused layer, while under-activating
    // would route the draw out of both scene buckets and drop it.
    final lod = item.lod;
    if (lod == null) continue;
    for (final level in lod.levels) {
      if (level.material.displayReferred) return true;
    }
  }
  return false;
}

/// Blends the display-referred layer over the resolved display image.
///
/// Both are display-encoded and premultiplied, so this is a source-over with
/// no color transform. Under MSAA it runs after anti-aliasing, since the
/// layer's silhouette is already multisampled and crisp UI is better left
/// unresampled. Without MSAA it runs before FXAA/SMAA instead, which is the
/// only thing that would smooth that silhouette.
class DisplayReferredCompositePass extends RenderGraphPass {
  DisplayReferredCompositePass({required gpu.Texture output})
    : _output = output;

  final gpu.Texture _output;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader =
      baseShaderLibrary['DisplayReferredCompositeFragment']!;

  // Two triangles of NDC positions covering the screen (6 vec2s).
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
  String get name => 'DisplayReferredCompositePass';

  @override
  void execute(RenderGraphContext context) {
    final display = context.blackboard.require<gpu.Texture>(
      kDisplayColorBlackboardKey,
    );
    // Absent when everything in the layer was culled; the white placeholder
    // would composite as opaque white, so fall back to copying the display
    // image through instead.
    final layer = context.blackboard.get<gpu.Texture>(
      kDisplayReferredBlackboardKey,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _output)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _fragmentShader));
    bindVertexBufferCompat(renderPass, _quadView, 6);
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('display_color'),
      display,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('display_referred_color'),
      layer ?? Material.getTransparentPlaceholderTexture(),
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);

    context.blackboard.set(kDisplayColorBlackboardKey, _output);
  }
}
