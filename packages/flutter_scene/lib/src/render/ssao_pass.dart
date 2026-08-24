import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/ambient_occlusion.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/scene_pass.dart'
    show kSceneColorBlackboardKey;
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:vector_math/vector_math.dart';

/// Render-graph blackboard key under which [SsaoBlurPass] publishes the
/// final ambient-occlusion texture (occlusion factor in `.r`, 1 =
/// unoccluded). The scene pass reads it to modulate indirect lighting.
const String kSsaoTextureBlackboardKey = 'ssao_texture';

// Intermediate key: the raw (unblurred) occlusion [SsaoPass] hands to
// [SsaoBlurPass].
const String _kSsaoRawBlackboardKey = 'ssao_raw';

// Intermediate key: the 1:1 base depth [SsaoPass] uses for occlusion and
// hands to [SsaoBlurPass].
const String _kSsaoDepthBlackboardKey = 'ssao_depth';

// The pass stores one scalar visibility value per pixel.
// Impeller's GLES backend only supports RGBA8 for this color attachment.
// TODO(ssao-format): use R8 once it is renderable on Impeller GLES.
const gpu.PixelFormat _aoFormat = gpu.PixelFormat.r8g8b8a8UNormInt;

/// The render size of the ambient-occlusion chain for a full-resolution
/// target of [dimensions], halved (floored, minimum 1) when
/// [AmbientOcclusionSettings.halfResolution] is set.
///
/// The depth prepass, occlusion pass, and blur all run at this resolution so
/// the depth texture is sampled 1:1 (sampling a full-resolution depth from a
/// half-resolution pass would alias on detailed geometry).
/// Whether the occlusion chain computes bent normals and packs them into the
/// occlusion texture's gba channels. Requires the ground-truth method's
/// horizon mode; the bitmask and obscurance estimators have no bent normal.
bool ambientOcclusionCarriesBentNormals(AmbientOcclusionSettings settings) =>
    settings.method == AmbientOcclusionMethod.groundTruth &&
    !settings.visibilityBitmask &&
    settings.bentNormals;

/// Whether the occlusion chain gathers screen-space indirect light, which
/// switches its targets to half-float with radiance in rgb and visibility
/// in a. Requires the ground-truth method's visibility bitmask.
bool ambientOcclusionCarriesIndirectLight(AmbientOcclusionSettings settings) =>
    settings.enabled &&
    settings.method == AmbientOcclusionMethod.groundTruth &&
    settings.visibilityBitmask &&
    settings.indirectLight > 0.0;

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

/// Evaluates screen-space ambient occlusion over the camera linear-depth
/// target and publishes the raw (unblurred) occlusion for [SsaoBlurPass].
///
/// A single full-screen fragment pass, no compute. The fragment shader is
/// selected by [AmbientOcclusionSettings.method]; see
/// `flutter_scene_ssao.frag` and `flutter_scene_gtao.frag` for the
/// algorithms.
class SsaoPass extends RenderGraphPass {
  SsaoPass({
    required ui.Size dimensions,
    required AmbientOcclusionSettings settings,
    required double fovRadiansY,
    required double near,
    required double far,
    Vector3? contactDirectionView,
    double contactDistance = 0.0,
    gpu.Texture? sceneRadiance,
    Matrix4? ssgiReprojection,
  }) : _dimensions = dimensions,
       _settings = settings,
       _fovRadiansY = fovRadiansY,
       _near = near,
       _far = far,
       _contactDirectionView = contactDirectionView,
       _contactDistance = contactDistance,
       _sceneRadiance = sceneRadiance,
       _ssgiReprojection = ssgiReprojection;

  final ui.Size _dimensions;
  final AmbientOcclusionSettings _settings;
  final double _fovRadiansY;
  final double _near;
  final double _far;

  // View-space direction toward the sun and the march distance for the
  // contact-shadow term; distance 0 leaves it off.
  final Vector3? _contactDirectionView;
  final double _contactDistance;

  // Last frame's scene color for the indirect-light gather, or null on the
  // first frame (a black placeholder stands in).
  final gpu.Texture? _sceneRadiance;

  // Maps the gather's view-space positions to the radiance history's clip
  // space (last frame's view-projection times the current view-to-world).
  final Matrix4? _ssgiReprojection;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _obscuranceShader =
      baseShaderLibrary['SsaoFragment']!;
  static final gpu.Shader _groundTruthShader =
      baseShaderLibrary['GtaoFragment']!;
  static final gpu.Shader _downsampleShader =
      baseShaderLibrary['DepthDownsampleFragment']!;

  // The depth mip chain matches the fp32 linear-depth prepass format.
  static const gpu.PixelFormat _depthFormat = gpu.PixelFormat.r32g32b32a32Float;

  @override
  String get name => 'SsaoPass';

  // Downsamples [source] into a half-size (rounded down) depth level via the
  // depth-downsample shader (rotated-grid subsample). Used to build the chain.
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
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _downsampleShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);
    renderPass.bindTexture(
      _downsampleShader.getUniformSlot('source'),
      source,
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
    return target;
  }

  @override
  void execute(RenderGraphContext context) {
    final linearDepth = context.blackboard.require<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );

    final aoSize = ambientOcclusionTargetSize(_dimensions, _settings);
    final aoWidth = aoSize.width.toInt();
    final aoHeight = aoSize.height.toInt();

    // The base depth for the occlusion pass must match the pass resolution
    // (aoWidth x aoHeight) 1:1. When the depth prepass runs at full resolution
    // (e.g. for TAA, SSR, or irradiance fields), downsample it to the pass size so
    // nearest-filtered lookups land on exact texel centers instead of texel
    // seams between adjacent fragments.
    final baseDepth =
        (linearDepth.width == aoWidth && linearDepth.height == aoHeight)
        ? linearDepth
        : _downsampleDepth(context, linearDepth, aoWidth, aoHeight);

    // Build the depth mip chain from baseDepth so the occlusion samples a
    // coarser level the further each tap reaches. When disabled the three slots
    // reuse baseDepth and the shader stays at level 0.
    var mip1 = baseDepth;
    var mip2 = baseDepth;
    var mip3 = baseDepth;
    var mipLevels = 1;
    if (_settings.depthMipChain) {
      mip1 = _downsampleDepth(
        context,
        baseDepth,
        math.max(1, aoWidth ~/ 2),
        math.max(1, aoHeight ~/ 2),
      );
      mip2 = _downsampleDepth(
        context,
        mip1,
        math.max(1, aoWidth ~/ 4),
        math.max(1, aoHeight ~/ 4),
      );
      mip3 = _downsampleDepth(
        context,
        mip2,
        math.max(1, aoWidth ~/ 8),
        math.max(1, aoHeight ~/ 8),
      );
      mipLevels = 4;
    }
    final indirect = ambientOcclusionCarriesIndirectLight(_settings);
    final occlusion = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: aoWidth,
        height: aoHeight,
        format: indirect ? gpu.PixelFormat.r16g16b16a16Float : _aoFormat,
        debugName: 'ssao_raw',
      ),
    );

    final aoActive = _settings.enabled;
    final groundTruth =
        aoActive && _settings.method == AmbientOcclusionMethod.groundTruth;
    final fragmentShader = groundTruth ? _groundTruthShader : _obscuranceShader;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: occlusion)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, fragmentShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);

    final tanHalfFovY = math.tan(_fovRadiansY * 0.5);
    final aspect = _dimensions.width / _dimensions.height;
    final tanHalfFovX = tanHalfFovY * aspect;
    // Pixels per world unit at depth 1, used to project the world radius to a
    // screen-space disk. Based on the occlusion target's own height.
    final projScale = aoHeight / (2.0 * tanHalfFovY);

    // The ground-truth path appends the mat4 reprojection for the
    // indirect-light history sample; the obscurance struct stays 6 vec4s.
    final info = Float32List(groundTruth ? 40 : 24)
      ..[0] = aoWidth.toDouble()
      ..[1] = aoHeight.toDouble()
      ..[2] = 1.0 / aoWidth
      ..[3] = 1.0 / aoHeight
      ..[4] = tanHalfFovX
      ..[5] = tanHalfFovY
      ..[6] = _near
      ..[7] = _far;
    if (groundTruth) {
      // Must match the GtaoInfo layout in flutter_scene_gtao.frag.
      info
        ..[8] = _settings.radius
        ..[9] = _settings.intensity
        ..[10] = _settings.power
        ..[11] = projScale
        ..[12] = _settings.sliceCount.clamp(1, 8).toDouble()
        ..[13] = _settings.stepsPerSlice.clamp(1, 8).toDouble()
        ..[14] = mipLevels.toDouble()
        ..[15] = _settings.thicknessHeuristic.clamp(0.0, 1.0)
        ..[16] = _settings.visibilityBitmask ? 1.0 : 0.0
        ..[17] = _settings.thickness
        ..[18] = ambientOcclusionCarriesBentNormals(_settings) ? 1.0 : 0.0
        ..[19] = indirect ? _settings.indirectLight : 0.0;
    } else {
      // Must match the SsaoInfo layout in flutter_scene_ssao.frag. With
      // occlusion disabled (a contact-shadow-only chain) the sampling zeroes
      // out and the shader returns full visibility.
      info
        ..[8] = _settings.radius
        ..[9] = _settings.bias
        ..[10] = aoActive ? _settings.intensity : 0.0
        ..[11] = projScale
        ..[12] = aoActive ? _settings.sampleCount.toDouble() : 0.0
        ..[13] = mipLevels.toDouble()
        ..[14] = _settings.horizonAngle
        ..[15] = _settings.power
        ..[16] = aoActive ? _settings.detail : 0.0;
    }
    final contactDirection = _contactDirectionView;
    if (contactDirection != null && _contactDistance > 0.0) {
      info
        ..[20] = contactDirection.x
        ..[21] = contactDirection.y
        ..[22] = contactDirection.z
        ..[23] = _contactDistance;
    }
    if (groundTruth) {
      // Identity reprojects nothing sensible, but the history is a black
      // placeholder whenever the matrix is absent, so the sample is moot.
      (_ssgiReprojection ?? Matrix4.identity()).copyIntoArray(info, 24);
    }
    renderPass.bindUniform(
      fragmentShader.getUniformSlot(groundTruth ? 'GtaoInfo' : 'SsaoInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      fragmentShader.getUniformSlot('depth_mip1'),
      mip1,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      fragmentShader.getUniformSlot('depth_mip2'),
      mip2,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      fragmentShader.getUniformSlot('depth_mip3'),
      mip3,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      fragmentShader.getUniformSlot('linear_depth'),
      baseDepth,
      sampler: _nearestClamp,
    );
    if (groundTruth) {
      renderPass.bindTexture(
        fragmentShader.getUniformSlot('scene_radiance'),
        _sceneRadiance ?? Material.getBlackPlaceholderTexture(),
        sampler: _linearClamp,
      );
    }
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);

    context.blackboard.set(_kSsaoDepthBlackboardKey, baseDepth);
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
    final linearDepth =
        context.blackboard.get<gpu.Texture>(_kSsaoDepthBlackboardKey) ??
        context.blackboard.require<gpu.Texture>(kLinearDepthBlackboardKey);

    final aoSize = ambientOcclusionTargetSize(_dimensions, _settings);
    final aoWidth = aoSize.width.toInt();
    final aoHeight = aoSize.height.toInt();
    final blurFormat = ambientOcclusionCarriesIndirectLight(_settings)
        ? gpu.PixelFormat.r16g16b16a16Float
        : _aoFormat;

    // The plane-aware filter removes the local slope before this threshold is
    // applied, so it can reject real depth steps much more tightly.
    final depthScale = math.max(_settings.radius * 0.05, 1e-3);

    gpu.Texture blur(
      gpu.Texture source,
      double axisX,
      double axisY, {
      required bool finalPass,
      required String debugName,
    }) {
      final target = context.texturePool.acquire(
        TransientTextureDescriptor.color(
          width: aoWidth,
          height: aoHeight,
          format: blurFormat,
          debugName: debugName,
        ),
      );
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      final renderPass = commandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
      );
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _fragmentShader));
      renderPass.setColorBlendEnable(false);
      bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);

      final info = Float32List(8)
        ..[0] = 1.0 / aoWidth
        ..[1] = 1.0 / aoHeight
        ..[2] = depthScale
        ..[3] = finalPass ? 1.0 : 0.0
        ..[4] = axisX
        ..[5] = axisY
        ..[6] = ambientOcclusionCarriesBentNormals(_settings) ? 1.0 : 0.0;
      renderPass.bindUniform(
        _fragmentShader.getUniformSlot('BlurInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
      renderPass.bindTexture(
        _fragmentShader.getUniformSlot('ao_texture'),
        source,
        sampler: _linearClamp,
      );
      renderPass.bindTexture(
        _fragmentShader.getUniformSlot('linear_depth'),
        linearDepth,
        sampler: _nearestClamp,
      );
      drawCompat(renderPass, 6);
      rendererSubmissions.submit(commandBuffer);
      return target;
    }

    final horizontal = blur(
      raw,
      1.0,
      0.0,
      finalPass: false,
      debugName: 'ssao_blurred_horizontal',
    );
    final blurred = blur(
      horizontal,
      0.0,
      1.0,
      finalPass: true,
      debugName: 'ssao_blurred',
    );

    context.blackboard.set(kSsaoTextureBlackboardKey, blurred);
  }
}

/// Copies the frame's scene color into a scene-owned history texture for
/// next frame's indirect-light gather. The target is owned by the caller
/// (not the transient pool), so holding it across frames is safe.
class SceneColorHistoryPass extends RenderGraphPass {
  SceneColorHistoryPass({required this.current, required this.store});

  /// The history texture from previous frames, reused when sizes match.
  final gpu.Texture? current;

  /// Receives the texture holding this frame's color.
  final void Function(gpu.Texture) store;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _copyShader = baseShaderLibrary['CopyFragment']!;

  @override
  String get name => 'SceneColorHistoryPass';

  @override
  void execute(RenderGraphContext context) {
    final source = context.blackboard.get<gpu.Texture>(
      kSceneColorBlackboardKey,
    );
    if (source == null) {
      return;
    }
    var target = current;
    if (target == null ||
        target.width != source.width ||
        target.height != source.height) {
      target = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        source.width,
        source.height,
        format: gpu.PixelFormat.r16g16b16a16Float,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
    }
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _copyShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);
    renderPass.bindTexture(
      _copyShader.getUniformSlot('source_texture'),
      source,
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
    store(target);
  }
}
