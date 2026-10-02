import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/post_process/post_process.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/render/uniform_slots.dart';

/// Render-graph blackboard key for the bloom texture [BloomPass] produces.
/// The resolve pass reads it and adds it to the HDR scene color.
const String kBloomTextureBlackboardKey = 'bloom_texture';

// Number of mip levels in the bloom chain, starting at the (capped) base.
const int _kMipCount = 6;

/// Most prefilter taps per axis, matching kMaxTaps in the threshold shader.
/// A box spans up to one more texel than its footprint, so one pass covers a
/// footprint up to one less than this.
@visibleForTesting
const int kMaxBloomThresholdTaps = 16;

// Scatter at which every mip contributes equally.
const double _kNeutralScatter = 0.7;

/// Weight of each coarser bloom mip relative to the one above it.
@visibleForTesting
double bloomLevelWeight(double scatter) => math
    .pow(2.0, (scatter.clamp(0.0, 1.0) - _kNeutralScatter) * 2.5)
    .toDouble();

/// How many times larger than the first bloom mip the prefilter's
/// intermediate target is, or 1 when a [footprint] fits the tap budget in one
/// pass.
@visibleForTesting
int bloomPrefilterScale(double footprint) =>
    (footprint / (kMaxBloomThresholdTaps - 1)).ceil().clamp(
      1,
      kMaxBloomThresholdTaps - 1,
    );

/// Weights the upsample writing mip [level] of [levels] gives the blurred
/// coarser mip ([source]) and this level's downsample ([base]).
///
/// Each intermediate mip is a weighted average of its inputs, so half-float
/// storage cannot overflow at high scatter. The finest level scales back to
/// the brightness of the equal-weight chain.
@visibleForTesting
({double source, double base}) bloomUpsampleWeights(
  double levelWeight,
  int level,
  int levels,
) {
  // Combined weight of the coarser mips, relative to this level's.
  var coarser = 0.0;
  for (var j = levels - level - 2; j >= 0; j--) {
    coarser = 1.0 + levelWeight * coarser;
  }
  coarser *= levelWeight;
  final scale = level == 0 ? levels / (1.0 + coarser) : 1.0 / (1.0 + coarser);
  return (source: coarser * scale, base: scale);
}

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

    _drawPrefilter(context, scene, down[0], sizes[0]);

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
    //
    // Scatter weights each coarser (wider) mip by levelWeight relative to the
    // one above it (see bloomUpsampleWeights).
    final levelWeight = bloomLevelWeight(_settings.scatter);

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
        weights: bloomUpsampleWeights(levelWeight, i, down.length),
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
      // up[2] averages its levels; scale it to their equal-weight sum.
      _drawLensFlare(
        context,
        sourceScale: (down.length - 2).toDouble(),
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
    required double sourceScale,
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
      ..[0] = flare.intensity * sourceScale
      ..[1] = flare.ghostCount.clamp(0, 8).toDouble()
      ..[2] = flare.ghostSpacing
      ..[3] = flare.chromaticAberration
      ..[4] = flare.haloRadius
      ..[5] = flare.haloIntensity
      ..[6] = targetSize.height == 0
          ? 1.0
          : targetSize.width / targetSize.height;
    renderPass.bindUniform(
      _lensFlareShader.cachedUniformSlot('LensFlareInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _lensFlareShader.cachedUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _lensFlareShader.cachedUniformSlot('base'),
      base,
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }

  // Thresholds [source] into the first mip. A source too large for the tap
  // budget thresholds into an integer multiple of the mip first, which a
  // one-tap-per-texel box pass then reduces exactly.
  void _drawPrefilter(
    RenderGraphContext context,
    gpu.Texture source,
    gpu.Texture target,
    ui.Size targetSize,
  ) {
    final scale = bloomPrefilterScale(
      math.max(
        source.width / targetSize.width,
        source.height / targetSize.height,
      ),
    );
    if (scale == 1) {
      _drawThreshold(context, source, target, targetSize, threshold: true);
      return;
    }
    final size = targetSize * scale.toDouble();
    final intermediate = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: size.width.toInt(),
        height: size.height.toInt(),
        format: _hdrFormat,
        debugName: 'bloom_prefilter',
      ),
    );
    _drawThreshold(context, source, intermediate, size, threshold: true);
    _drawThreshold(context, intermediate, target, targetSize, threshold: false);
  }

  void _drawThreshold(
    RenderGraphContext context,
    gpu.Texture source,
    gpu.Texture target,
    ui.Size targetSize, {
    required bool threshold,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _thresholdShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _quadView, 6);

    final knee = _settings.threshold * 0.5 + 1e-4;
    final info = Float32List(8)
      ..[0] = _settings.threshold
      ..[1] = knee
      ..[2] = threshold ? 1.0 : 0.0
      ..[4] = source.width / targetSize.width
      ..[5] = source.height / targetSize.height
      ..[6] = source.width.toDouble()
      ..[7] = source.height.toDouble();
    renderPass.bindUniform(
      _thresholdShader.cachedUniformSlot('BloomThresholdInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _thresholdShader.cachedUniformSlot('source'),
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
      _downsampleShader.cachedUniformSlot('BloomFilterInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _downsampleShader.cachedUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }

  // Tent-blurs [source] (the smaller mip) and adds [base] (the downsample one
  // size larger) in the shader, each scaled by [weights], writing a cleared
  // target. No loaded attachment, so backends that re-clear a reload cannot
  // drop the accumulation.
  void _drawUpsample(
    RenderGraphContext context, {
    required gpu.Texture source,
    required ui.Size sourceSize,
    required gpu.Texture base,
    required gpu.Texture target,
    required ({double source, double base}) weights,
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
      ..[2] = weights.source
      ..[3] = weights.base;
    renderPass.bindUniform(
      _upsampleShader.cachedUniformSlot('BloomUpsampleInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _upsampleShader.cachedUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _upsampleShader.cachedUniformSlot('base'),
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
