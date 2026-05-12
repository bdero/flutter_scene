import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Resolves the linear HDR scene color (a floating-point render target
/// produced by [ScenePass], read from the blackboard) into the
/// display-referred swapchain image: applies exposure, the tone mapping
/// operator, and the display EOTF as a single full-screen pass.
class TonemapPass extends RenderGraphPass {
  TonemapPass({
    required gpu.RenderTarget target,
    required double exposure,
    required ToneMappingMode toneMappingMode,
  }) : _target = target,
       _exposure = exposure,
       _toneMappingMode = toneMappingMode;

  final gpu.RenderTarget _target;
  final double _exposure;
  final ToneMappingMode _toneMappingMode;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader =
      baseShaderLibrary['TonemapFragment']!;

  // Two triangles of NDC positions covering the screen (6 vec2s).
  static final gpu.DeviceBuffer _quadBuffer =
      gpu.gpuContext.createDeviceBufferWithCopy(
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
  String get name => 'TonemapPass';

  @override
  void execute(RenderGraphContext context) {
    final hdrColor = context.blackboard.require<gpu.Texture>(
      kHdrColorBlackboardKey,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(_target);
    final pipeline = gpu.gpuContext.createRenderPipeline(
      _vertexShader,
      _fragmentShader,
    );
    renderPass.bindPipeline(pipeline);
    renderPass.bindVertexBuffer(_quadView, 6);

    // TonemapInfo std140: { float exposure; float tone_mapping_mode; }
    // padded to 16 bytes.
    final info = Float32List(4);
    info[0] = _exposure;
    info[1] = _toneMappingMode.index.toDouble();
    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('TonemapInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('hdr_color'),
      hdrColor,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    renderPass.draw();
    commandBuffer.submit();
  }
}
