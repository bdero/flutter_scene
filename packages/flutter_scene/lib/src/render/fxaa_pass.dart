import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/resolve_pass.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;

/// Anti-aliases the display-referred image as a single full-screen FXAA
/// pass. Reads the resolve output from the blackboard, writes [_output],
/// and republishes it so after-tone-mapping effects receive the
/// anti-aliased image.
class FxaaPass extends RenderGraphPass {
  FxaaPass({required gpu.Texture output, required ui.Size dimensions})
    : _output = output,
      _dimensions = dimensions;

  final gpu.Texture _output;
  final ui.Size _dimensions;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader = baseShaderLibrary['FxaaFragment']!;

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
  String get name => 'FxaaPass';

  @override
  void execute(RenderGraphContext context) {
    final input = context.blackboard.require<gpu.Texture>(
      kDisplayColorBlackboardKey,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _output)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _fragmentShader));
    bindVertexBufferCompat(renderPass, _quadView, 6);

    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('scene_color'),
      input,
      sampler: _linearClamp,
    );

    // FxaaInfo std140: { vec2 inv_target_size; vec2 pad; }, 16 bytes.
    final w = _dimensions.width;
    final h = _dimensions.height;
    final info = Float32List(4)
      ..[0] = w == 0 ? 0.0 : 1.0 / w
      ..[1] = h == 0 ? 0.0 : 1.0 / h;
    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('FxaaInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );

    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);

    context.blackboard.set(kDisplayColorBlackboardKey, _output);
  }
}
