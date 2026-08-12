import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';

/// Copies the linear HDR scene color into [_output] verbatim, ending a
/// capture render (environment probes) before any post-processing or the
/// display-referred chain.
class SceneColorBlitPass extends RenderGraphPass {
  SceneColorBlitPass({required gpu.Texture output}) : _output = output;

  final gpu.Texture _output;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader = baseShaderLibrary['CopyFragment']!;

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

  static final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  @override
  String get name => 'SceneColorBlitPass';

  @override
  void execute(RenderGraphContext context) {
    final input = context.blackboard.require<gpu.Texture>(
      kSceneColorBlackboardKey,
    );
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _output)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _fragmentShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _quadView, 6);
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('source_texture'),
      input,
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }
}
