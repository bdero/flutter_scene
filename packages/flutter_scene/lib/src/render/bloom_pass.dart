import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/post_process/post_process.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Render-graph blackboard key for the bloom texture [BloomPass] produces.
/// The resolve pass reads it and adds it to the HDR scene color.
const String kBloomTextureBlackboardKey = 'bloom_texture';

// Number of mip levels in the bloom chain, starting at half resolution.
const int _kMipCount = 5;

const gpu.PixelFormat _hdrFormat = gpu.PixelFormat.r16g16b16a16Float;

/// Builds the bloom texture: a soft-knee threshold of the HDR scene color
/// blurred through a downsample/upsample mip chain. Reads the scene color
/// from the blackboard and publishes the result under
/// [kBloomTextureBlackboardKey] for [ResolvePass] to composite.
///
/// Each step is its own full-screen pass, so the chain needs no compute
/// shaders or mipmap generation and runs on the WebGL2 backend.
class BloomPass extends RenderGraphPass {
  BloomPass({required ui.Size dimensions, required BloomSettings settings})
    : _dimensions = dimensions,
      _settings = settings;

  final ui.Size _dimensions;
  final BloomSettings _settings;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _thresholdShader =
      baseShaderLibrary['BloomThresholdFragment']!;
  static final gpu.Shader _downsampleShader =
      baseShaderLibrary['BloomDownsampleFragment']!;
  static final gpu.Shader _upsampleShader =
      baseShaderLibrary['BloomUpsampleFragment']!;

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
  String get name => 'BloomPass';

  @override
  void execute(RenderGraphContext context) {
    final scene = context.blackboard.require<gpu.Texture>(
      kSceneColorBlackboardKey,
    );

    // Allocate the mip chain at successively halved resolutions.
    final mips = <gpu.Texture>[];
    final sizes = <ui.Size>[];
    var width = (_dimensions.width / 2).floor();
    var height = (_dimensions.height / 2).floor();
    for (var i = 0; i < _kMipCount; i++) {
      width = math.max(1, width);
      height = math.max(1, height);
      mips.add(
        context.texturePool.acquire(
          TransientTextureDescriptor.color(
            width: width,
            height: height,
            format: _hdrFormat,
            debugName: 'bloom_$i',
          ),
        ),
      );
      sizes.add(ui.Size(width.toDouble(), height.toDouble()));
      width = (width / 2).floor();
      height = (height / 2).floor();
    }

    // Threshold the scene into the first mip.
    _drawThreshold(context, scene, mips[0]);

    // Downsample down the chain.
    for (var i = 1; i < mips.length; i++) {
      _drawFilter(
        context,
        _downsampleShader,
        source: mips[i - 1],
        sourceSize: sizes[i - 1],
        target: mips[i],
        additive: false,
      );
    }

    // Upsample back up, adding each level into the next larger one.
    for (var i = mips.length - 2; i >= 0; i--) {
      _drawFilter(
        context,
        _upsampleShader,
        source: mips[i + 1],
        sourceSize: sizes[i + 1],
        target: mips[i],
        additive: true,
      );
    }

    context.blackboard.set(kBloomTextureBlackboardKey, mips[0]);
  }

  void _drawThreshold(
    RenderGraphContext context,
    gpu.Texture source,
    gpu.Texture target,
  ) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _thresholdShader),
    );
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _quadView, 6);

    final knee = _settings.threshold * 0.5 + 1e-4;
    final info = Float32List(4)
      ..[0] = _settings.threshold
      ..[1] = knee;
    renderPass.bindUniform(
      _thresholdShader.getUniformSlot('BloomThresholdInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _thresholdShader.getUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    commandBuffer.submit();
  }

  void _drawFilter(
    RenderGraphContext context,
    gpu.Shader shader, {
    required gpu.Texture source,
    required ui.Size sourceSize,
    required gpu.Texture target,
    required bool additive,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final attachment = gpu.ColorAttachment(
      texture: target,
      // Additive upsample preserves the downsample result already in the
      // target; threshold/downsample overwrite it.
      loadAction: additive ? gpu.LoadAction.load : gpu.LoadAction.clear,
    );
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(attachment),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, shader),
    );
    if (additive) {
      renderPass.setColorBlendEnable(true);
      renderPass.setColorBlendEquation(
        gpu.ColorBlendEquation(
          colorBlendOperation: gpu.BlendOperation.add,
          sourceColorBlendFactor: gpu.BlendFactor.one,
          destinationColorBlendFactor: gpu.BlendFactor.one,
          alphaBlendOperation: gpu.BlendOperation.add,
          sourceAlphaBlendFactor: gpu.BlendFactor.one,
          destinationAlphaBlendFactor: gpu.BlendFactor.one,
        ),
      );
    } else {
      renderPass.setColorBlendEnable(false);
    }
    bindVertexBufferCompat(renderPass, _quadView, 6);

    final info = Float32List(4)
      ..[0] = 1.0 / sourceSize.width
      ..[1] = 1.0 / sourceSize.height
      ..[2] = _settings.scatter;
    renderPass.bindUniform(
      shader.getUniformSlot('BloomFilterInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      shader.getUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    commandBuffer.submit();
  }

  static final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
}
