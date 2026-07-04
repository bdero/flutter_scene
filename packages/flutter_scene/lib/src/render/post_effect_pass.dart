import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/post_process/post_effect.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Runs one custom [PostEffect] as a full-screen pass.
///
/// Reads the current color from [inputKey] on the blackboard, renders the
/// effect's shader into [output], and republishes the result under
/// [outputKey] so the next pass picks it up. The engine binds the input as
/// `input_color`; when [PostEffect.useFrameInfo] is set it also binds a
/// `PostFrameInfo` block.
class PostEffectPass extends RenderGraphPass {
  PostEffectPass({
    required PostEffect effect,
    required String inputKey,
    required String outputKey,
    required gpu.Texture output,
    required ui.Size dimensions,
    required double time,
  }) : _effect = effect,
       _inputKey = inputKey,
       _outputKey = outputKey,
       _output = output,
       _dimensions = dimensions,
       _time = time;

  final PostEffect _effect;
  final String _inputKey;
  final String _outputKey;
  final gpu.Texture _output;
  final ui.Size _dimensions;
  final double _time;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;

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
  String get name => 'PostEffectPass';

  @override
  void execute(RenderGraphContext context) {
    final input = context.blackboard.require<gpu.Texture>(_inputKey);
    final shader = _effect.fragmentShader;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _output)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, shader),
    );
    bindVertexBufferCompat(renderPass, _quadView, 6);

    renderPass.bindTexture(
      shader.getUniformSlot('input_color'),
      input,
      sampler: _linearClamp,
    );

    if (_effect.useFrameInfo) {
      // PostFrameInfo std140: { vec2 resolution; vec2 texel_size;
      // float time; float pad; }, padded to 32 bytes.
      final w = _dimensions.width;
      final h = _dimensions.height;
      final info = Float32List(8)
        ..[0] = w
        ..[1] = h
        ..[2] = w == 0 ? 0.0 : 1.0 / w
        ..[3] = h == 0 ? 0.0 : 1.0 / h
        ..[4] = _time;
      renderPass.bindUniform(
        shader.getUniformSlot('PostFrameInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
    }

    _effect.bindUniforms(renderPass, context.transientsBuffer);

    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);

    context.blackboard.set(_outputKey, _output);
  }
}
