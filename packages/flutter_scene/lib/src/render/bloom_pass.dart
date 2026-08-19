import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/post_process/post_process.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;

/// Render-graph blackboard key for the bloom texture [BloomPass] produces.
/// The resolve pass reads it and adds it to the HDR scene color.
const String kBloomTextureBlackboardKey = 'bloom_texture';

// Number of mip levels in the bloom chain, starting at the (capped) base.
const int _kMipCount = 5;

// Largest side (px) the first bloom mip is allowed to be. The mip chain
// starts at half the render resolution but is capped here, so the whole
// pyramid (and its blur kernels) covers the same fraction of the screen at
// any resolution. Without this the spread is a fixed pixel count that shrinks
// as the device pixel ratio grows, so bloom and any lens flare riding it look
// tight on a 3x display and wide on a 1x one. 256 keeps the common
// half-of-512 desktop case unchanged.
const double _kMaxBloomBaseSide = 256.0;

const gpu.PixelFormat _hdrFormat = gpu.PixelFormat.r16g16b16a16Float;

// The first bloom mip's size: half the render resolution, scaled down so its
// larger side is at most [_kMaxBloomBaseSide], preserving aspect.
ui.Size _bloomBaseSize(ui.Size dimension) {
  var width = dimension.width / 2.0;
  var height = dimension.height / 2.0;
  final larger = math.max(width, height);
  if (larger > _kMaxBloomBaseSide) {
    final scale = _kMaxBloomBaseSide / larger;
    width *= scale;
    height *= scale;
  }
  return ui.Size(width, height);
}

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
  static final gpu.Shader _lensFlareShader =
      baseShaderLibrary['LensFlareFragment']!;

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

    // Allocate the downsample chain at successively halved resolutions,
    // starting from a resolution-capped base so the bloom's on-screen spread
    // stays stable across device pixel ratios.
    final base = _bloomBaseSize(_dimensions);
    final down = <gpu.Texture>[];
    final sizes = <ui.Size>[];
    var width = base.width.floor();
    var height = base.height.floor();
    for (var i = 0; i < _kMipCount; i++) {
      width = math.max(1, width);
      height = math.max(1, height);
      down.add(
        context.texturePool.acquire(
          TransientTextureDescriptor.color(
            width: width,
            height: height,
            format: _hdrFormat,
            debugName: 'bloom_down_$i',
          ),
        ),
      );
      sizes.add(ui.Size(width.toDouble(), height.toDouble()));
      width = (width / 2).floor();
      height = (height / 2).floor();
    }

    // Threshold the scene into the first mip.
    _drawThreshold(context, scene, down[0]);

    // Downsample down the chain.
    for (var i = 1; i < down.length; i++) {
      _drawDownsample(
        context,
        source: down[i - 1],
        sourceSize: sizes[i - 1],
        target: down[i],
      );
    }

    // Upsample back up, tent-blurring each level and adding the downsample
    // one size larger. Every step writes a fresh cleared target and adds
    // its inputs in the shader instead of blending into a reloaded
    // attachment: some backends re-clear a loaded attachment across command
    // buffers, which silently drops the accumulation and leaves the bloom
    // (and any flare riding it) far dimmer than on backends that preserve
    // it. The coarsest level needs no pass; it is its own downsample mip.
    final up = List<gpu.Texture?>.filled(down.length, null);
    up[down.length - 1] = down[down.length - 1];
    for (var i = down.length - 2; i >= 0; i--) {
      final target = context.texturePool.acquire(
        TransientTextureDescriptor.color(
          width: sizes[i].width.toInt(),
          height: sizes[i].height.toInt(),
          format: _hdrFormat,
          debugName: 'bloom_up_$i',
        ),
      );
      _drawUpsample(
        context,
        source: up[i + 1]!,
        sourceSize: sizes[i + 1],
        base: down[i],
        target: target,
      );
      up[i] = target;
    }

    var result = up[0]!;

    // Lens flares generate from a well-blurred mip (up[2]) and composite over
    // the finished bloom into another fresh cleared target, for the same
    // write-once reason as the upsample. _kMipCount (>= 3) guarantees that
    // source mip exists.
    if (_settings.lensFlare.enabled) {
      final composite = context.texturePool.acquire(
        TransientTextureDescriptor.color(
          width: sizes[0].width.toInt(),
          height: sizes[0].height.toInt(),
          format: _hdrFormat,
          debugName: 'bloom_flare',
        ),
      );
      _drawLensFlare(
        context,
        source: up[2]!,
        base: result,
        target: composite,
        targetSize: sizes[0],
      );
      result = composite;
    }

    context.blackboard.set(kBloomTextureBlackboardKey, result);
  }

  void _drawLensFlare(
    RenderGraphContext context, {
    required gpu.Texture source,
    required gpu.Texture base,
    required gpu.Texture target,
    required ui.Size targetSize,
  }) {
    final flare = _settings.lensFlare;
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _lensFlareShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _quadView, 6);

    final info = Float32List(8)
      ..[0] = flare.intensity
      ..[1] = flare.ghostCount.clamp(0, 8).toDouble()
      ..[2] = flare.ghostSpacing
      ..[3] = flare.chromaticAberration
      ..[4] = flare.haloRadius
      ..[5] = flare.haloIntensity
      ..[6] = targetSize.height == 0
          ? 1.0
          : targetSize.width / targetSize.height;
    renderPass.bindUniform(
      _lensFlareShader.getUniformSlot('LensFlareInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _lensFlareShader.getUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _lensFlareShader.getUniformSlot('base'),
      base,
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
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
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _thresholdShader));
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
    rendererSubmissions.submit(commandBuffer);
  }

  void _drawDownsample(
    RenderGraphContext context, {
    required gpu.Texture source,
    required ui.Size sourceSize,
    required gpu.Texture target,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _downsampleShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _quadView, 6);

    final info = Float32List(4)
      ..[0] = 1.0 / sourceSize.width
      ..[1] = 1.0 / sourceSize.height
      ..[2] = _settings.scatter;
    renderPass.bindUniform(
      _downsampleShader.getUniformSlot('BloomFilterInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _downsampleShader.getUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }

  // Tent-blurs [source] (the smaller mip) and adds [base] (the downsample
  // one size larger) in the shader, writing a cleared target. No loaded
  // attachment, so backends that re-clear a reload cannot drop the
  // accumulation.
  void _drawUpsample(
    RenderGraphContext context, {
    required gpu.Texture source,
    required ui.Size sourceSize,
    required gpu.Texture base,
    required gpu.Texture target,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _upsampleShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _quadView, 6);

    final info = Float32List(4)
      ..[0] = 1.0 / sourceSize.width
      ..[1] = 1.0 / sourceSize.height
      ..[2] = _settings.scatter;
    renderPass.bindUniform(
      _upsampleShader.getUniformSlot('BloomFilterInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _upsampleShader.getUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _upsampleShader.getUniformSlot('base'),
      base,
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }

  static final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
}
