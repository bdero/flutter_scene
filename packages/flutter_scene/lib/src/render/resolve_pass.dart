import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/post_process/post_process.dart';
import 'package:flutter_scene/src/render/bloom_pass.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/resolve_info.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/tone_mapping.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Render-graph blackboard key for the display-referred color the resolve
/// pass produces. After-tone-mapping custom effects read it and republish
/// their own output.
const String kDisplayColorBlackboardKey = 'display_color';

/// Resolves the linear HDR scene color (a floating-point render target
/// produced by [ScenePass], read from the blackboard) into the
/// display-referred image: applies exposure, optional color grading, the
/// tone mapping operator, and display encoding as a single full-screen
/// pass. Writes into [outputColor] and publishes it on the blackboard.
class ResolvePass extends RenderGraphPass {
  ResolvePass({
    required gpu.Texture outputColor,
    required double exposure,
    required ToneMappingMode toneMappingMode,
    required PostProcessSettings postProcess,
  }) : _outputColor = outputColor,
       _exposure = exposure,
       _toneMappingMode = toneMappingMode,
       _postProcess = postProcess;

  final gpu.Texture _outputColor;
  final double _exposure;
  final ToneMappingMode _toneMappingMode;
  final PostProcessSettings _postProcess;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader =
      baseShaderLibrary['ResolveFragment']!;

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

  @override
  String get name => 'ResolvePass';

  @override
  void execute(RenderGraphContext context) {
    final hdrColor = context.blackboard.require<gpu.Texture>(
      kSceneColorBlackboardKey,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _outputColor)),
    );
    final pipeline = gpu.gpuContext.createRenderPipeline(
      _vertexShader,
      _fragmentShader,
    );
    renderPass.bindPipeline(pipeline);
    bindVertexBufferCompat(renderPass, _quadView, 6);

    // Wall-clock seconds (wrapped to keep float precision) drive the
    // animated film grain.
    final timeSeconds =
        DateTime.now().millisecondsSinceEpoch.remainder(100000) / 1000.0;
    // Render-to-texture content is stored top-down on every backend, so the
    // resolve samples without a fragment-stage V-flip (flipY is always false).
    final info = packResolveInfo(
      exposure: _exposure,
      toneMappingMode: _toneMappingMode,
      flipY: false,
      time: timeSeconds,
      settings: _postProcess,
    );
    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('ResolveInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('scene_color'),
      hdrColor,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    // Bloom is present only when BloomPass ran this frame; otherwise a
    // placeholder fills the slot and the resolve skips it (flag off).
    final bloomTexture =
        context.blackboard.get<gpu.Texture>(kBloomTextureBlackboardKey) ??
        Material.getWhitePlaceholderTexture();
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('bloom_color'),
      bloomTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);

    context.blackboard.set(kDisplayColorBlackboardKey, _outputColor);
  }
}
