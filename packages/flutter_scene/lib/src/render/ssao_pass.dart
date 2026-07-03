import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/ambient_occlusion.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Render-graph blackboard key under which [SsaoBlurPass] publishes the
/// final ambient-occlusion texture (occlusion factor in `.r`, 1 =
/// unoccluded). The scene pass reads it to modulate indirect lighting.
const String kSsaoTextureBlackboardKey = 'ssao_texture';

// Intermediate key: the raw (unblurred) occlusion [SsaoPass] hands to
// [SsaoBlurPass].
const String _kSsaoRawBlackboardKey = 'ssao_raw';

// Single-channel, filterable, and color-renderable on every backend, which
// is all the occlusion factor needs.
const gpu.PixelFormat _aoFormat = gpu.PixelFormat.r8UNormInt;

/// The render size of the ambient-occlusion chain for a full-resolution
/// target of [dimensions], halved (floored, minimum 1) when
/// [AmbientOcclusionSettings.halfResolution] is set.
///
/// The depth prepass, occlusion pass, and blur all run at this resolution so
/// the depth texture is sampled 1:1 (sampling a full-resolution depth from a
/// half-resolution pass would alias on detailed geometry).
ui.Size ambientOcclusionTargetSize(
  ui.Size dimensions,
  AmbientOcclusionSettings settings,
) {
  if (!settings.halfResolution) {
    return dimensions;
  }
  return ui.Size(
    math.max(1, (dimensions.width / 2).floor()).toDouble(),
    math.max(1, (dimensions.height / 2).floor()).toDouble(),
  );
}

// Two triangles of NDC positions covering the screen (6 vec2s), shared by
// the occlusion passes.
gpu.BufferView _fullscreenQuad() {
  return _quadView ??= () {
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 6 * 2 * 4);
  }();
}

gpu.BufferView? _quadView;

final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

// Linear depth is fp32. GLES / WebGL2 devices may not filter float textures
// (no OES_texture_float_linear), and depth must not be interpolated across
// edges anyway, so it is always sampled with nearest filtering.
final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// Evaluates Scalable Ambient Obscurance over the camera linear-depth
/// target and publishes the raw (unblurred) occlusion for [SsaoBlurPass].
///
/// A single full-screen fragment pass, no compute. See
/// `flutter_scene_ssao.frag` for the algorithm.
class SsaoPass extends RenderGraphPass {
  SsaoPass({
    required ui.Size dimensions,
    required AmbientOcclusionSettings settings,
    required double fovRadiansY,
    required double near,
    required double far,
  }) : _dimensions = dimensions,
       _settings = settings,
       _fovRadiansY = fovRadiansY,
       _near = near,
       _far = far;

  final ui.Size _dimensions;
  final AmbientOcclusionSettings _settings;
  final double _fovRadiansY;
  final double _near;
  final double _far;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader = baseShaderLibrary['SsaoFragment']!;
  static final gpu.Shader _downsampleShader =
      baseShaderLibrary['DepthDownsampleFragment']!;

  // The depth mip chain matches the fp32 linear-depth prepass format.
  static const gpu.PixelFormat _depthFormat = gpu.PixelFormat.r32g32b32a32Float;

  @override
  String get name => 'SsaoPass';

  // Downsamples [source] into a half-size (rounded down) depth level via the
  // depth-downsample shader (nearest 2x2 minimum). Used to build the SAO chain.
  gpu.Texture _downsampleDepth(
    RenderGraphContext context,
    gpu.Texture source,
    int width,
    int height,
  ) {
    final target = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: _depthFormat,
        debugName: 'depth_mip',
      ),
    );
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _downsampleShader),
    );
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);
    renderPass.bindTexture(
      _downsampleShader.getUniformSlot('source'),
      source,
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    commandBuffer.submit();
    return target;
  }

  @override
  void execute(RenderGraphContext context) {
    final linearDepth = context.blackboard.require<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );

    // Build the depth mip chain from the (full-resolution) linear depth so the
    // occlusion samples a coarser level the further each tap reaches. When
    // disabled the three slots reuse the base depth and the shader stays at
    // level 0, so behaviour is unchanged.
    var mip1 = linearDepth;
    var mip2 = linearDepth;
    var mip3 = linearDepth;
    var mipLevels = 1;
    if (_settings.depthMipChain) {
      final fw = _dimensions.width.toInt();
      final fh = _dimensions.height.toInt();
      mip1 = _downsampleDepth(
        context,
        linearDepth,
        math.max(1, fw ~/ 2),
        math.max(1, fh ~/ 2),
      );
      mip2 = _downsampleDepth(
        context,
        mip1,
        math.max(1, fw ~/ 4),
        math.max(1, fh ~/ 4),
      );
      mip3 = _downsampleDepth(
        context,
        mip2,
        math.max(1, fw ~/ 8),
        math.max(1, fh ~/ 8),
      );
      mipLevels = 4;
    }

    final aoSize = ambientOcclusionTargetSize(_dimensions, _settings);
    final aoWidth = aoSize.width.toInt();
    final aoHeight = aoSize.height.toInt();
    final occlusion = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: aoWidth,
        height: aoHeight,
        format: _aoFormat,
        debugName: 'ssao_raw',
      ),
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: occlusion)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _fragmentShader),
    );
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);

    final tanHalfFovY = math.tan(_fovRadiansY * 0.5);
    final aspect = _dimensions.width / _dimensions.height;
    final tanHalfFovX = tanHalfFovY * aspect;
    // Pixels per world unit at depth 1, used to project the world radius to a
    // screen-space disk. Based on the occlusion target's own height.
    final projScale = aoHeight / (2.0 * tanHalfFovY);

    final info = Float32List(16)
      ..[0] = aoWidth.toDouble()
      ..[1] = aoHeight.toDouble()
      ..[2] = 1.0 / aoWidth
      ..[3] = 1.0 / aoHeight
      ..[4] = tanHalfFovX
      ..[5] = tanHalfFovY
      ..[6] = _near
      ..[7] = _far
      ..[8] = _settings.radius
      ..[9] = _settings.bias
      ..[10] = _settings.intensity
      ..[11] = projScale
      ..[12] = _settings.sampleCount.toDouble()
      ..[13] = mipLevels.toDouble();
    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('SsaoInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('depth_mip1'),
      mip1,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('depth_mip2'),
      mip2,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('depth_mip3'),
      mip3,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('linear_depth'),
      linearDepth,
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    commandBuffer.submit();

    context.blackboard.set(_kSsaoRawBlackboardKey, occlusion);
  }
}

/// Denoises the raw occlusion with a 2D depth-aware (bilateral) blur and
/// publishes the result under [kSsaoTextureBlackboardKey].
///
/// See `flutter_scene_ssao_blur.frag`.
class SsaoBlurPass extends RenderGraphPass {
  SsaoBlurPass({
    required ui.Size dimensions,
    required AmbientOcclusionSettings settings,
  }) : _dimensions = dimensions,
       _settings = settings;

  final ui.Size _dimensions;
  final AmbientOcclusionSettings _settings;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader =
      baseShaderLibrary['SsaoBlurFragment']!;

  @override
  String get name => 'SsaoBlurPass';

  @override
  void execute(RenderGraphContext context) {
    final raw = context.blackboard.require<gpu.Texture>(_kSsaoRawBlackboardKey);
    final linearDepth = context.blackboard.require<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );

    final aoSize = ambientOcclusionTargetSize(_dimensions, _settings);
    final aoWidth = aoSize.width.toInt();
    final aoHeight = aoSize.height.toInt();

    // The bilateral depth weight falls off over roughly the occlusion radius,
    // so neighbours on the same (even steeply slanted) surface still average
    // while a real depth step at a silhouette, far larger than the radius,
    // cuts the blur.
    final depthScale = math.max(_settings.radius, 1e-3);

    final blurred = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: aoWidth,
        height: aoHeight,
        format: _aoFormat,
        debugName: 'ssao_blurred',
      ),
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: blurred)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _fragmentShader),
    );
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);

    final info = Float32List(4)
      ..[0] = 1.0 / aoWidth
      ..[1] = 1.0 / aoHeight
      ..[2] = depthScale;
    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('BlurInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('ao_texture'),
      raw,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('linear_depth'),
      linearDepth,
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    commandBuffer.submit();

    context.blackboard.set(kSsaoTextureBlackboardKey, blurred);
  }
}
