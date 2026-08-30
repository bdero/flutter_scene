import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/resolve_pass.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

/// Quality settings for SMAA anti-aliasing. Active when
/// `Scene.antiAliasingMode` is `AntiAliasingMode.smaa`. The defaults mirror
/// the reference implementation's high preset.
/// {@category Rendering}
class SmaaSettings {
  SmaaSettings({
    this.threshold = 0.1,
    this.maxSearchSteps = 16,
    this.maxDiagonalSearchSteps = 8,
    this.cornerRounding = 25.0,
  });

  /// Luma contrast an edge must exceed to be detected. Lower values catch
  /// more edges (including texture detail) at more cost; the useful band is
  /// roughly 0.05 (overkill) to 0.2 (fast).
  double threshold;

  /// How far, in doubled pixels, the horizontal/vertical line search walks
  /// each direction. Caps the length of a line the pass can reconstruct.
  int maxSearchSteps;

  /// How far, in pixels, the diagonal line search walks each direction.
  int maxDiagonalSearchSteps;

  /// How much sharp geometric corners are kept (0 fully smoothed, 100 fully
  /// kept), as a percentage.
  double cornerRounding;
}

/// Anti-aliases the display-referred image with enhanced subpixel
/// morphological antialiasing (SMAA 1x): a luma edge-detection pass, a
/// blending-weight pass over the precomputed area/search textures, and a
/// neighborhood-blending resolve. Reads the resolve output from the
/// blackboard, writes [_output], and republishes it, exactly like
/// [FxaaPass] one shader earlier in the file order.
///
/// The algorithm and the two lookup textures come from Jimenez et al.,
/// "SMAA: Enhanced Subpixel Morphological Antialiasing" (Eurographics
/// 2012), via the reference implementation at https://github.com/iryoku/smaa
/// (MIT-style license; the required copyright notice is carried in
/// shaders/smaa.glsl). The port notes live in that file too.
class SmaaPass extends RenderGraphPass {
  SmaaPass({
    required gpu.Texture output,
    required ui.Size dimensions,
    SmaaSettings? settings,
  }) : _output = output,
       _dimensions = dimensions,
       _settings = settings ?? SmaaSettings();

  final gpu.Texture _output;
  final ui.Size _dimensions;
  final SmaaSettings _settings;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _edgesShader =
      baseShaderLibrary['SmaaEdgesFragment']!;
  static final gpu.Shader _weightsShader =
      baseShaderLibrary['SmaaWeightsFragment']!;
  static final gpu.Shader _blendShader =
      baseShaderLibrary['SmaaBlendFragment']!;

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

  static final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  static gpu.Texture? _areaTexture;
  static gpu.Texture? _searchTexture;

  /// Whether [initializeStaticResources] has completed. [SmaaPass] must not
  /// run before it has.
  static bool get isInitialized =>
      _areaTexture != null && _searchTexture != null;

  /// Loads the precomputed SMAA area and search textures. Called by
  /// `Scene.initializeStaticResources`, which rendering is gated on.
  static Future<void> initializeStaticResources() async {
    if (isInitialized) {
      return;
    }
    final area = await rootBundle.load(
      'packages/flutter_scene/assets/smaa_area.bin',
    );
    final search = await rootBundle.load(
      'packages/flutter_scene/assets/smaa_search.bin',
    );
    // Expanded to rgba8: two-channel formats are not in the Flutter GPU
    // format set.
    _areaTexture = _uploadExpanded(
      area.buffer.asUint8List(area.offsetInBytes, area.lengthInBytes),
      width: 160,
      height: 560,
      sourceChannels: 2,
    );
    _searchTexture = _uploadExpanded(
      search.buffer.asUint8List(search.offsetInBytes, search.lengthInBytes),
      width: 64,
      height: 16,
      sourceChannels: 1,
    );
  }

  static gpu.Texture _uploadExpanded(
    Uint8List source, {
    required int width,
    required int height,
    required int sourceChannels,
  }) {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      rgba[i * 4] = source[i * sourceChannels];
      if (sourceChannels > 1) {
        rgba[i * 4 + 1] = source[i * sourceChannels + 1];
      }
      rgba[i * 4 + 3] = 0xFF;
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
    );
    texture.overwrite(ByteData.sublistView(rgba));
    return texture;
  }

  @override
  String get name => 'SmaaPass';

  @override
  void execute(RenderGraphContext context) {
    final input = context.blackboard.require<gpu.Texture>(
      kDisplayColorBlackboardKey,
    );
    final width = _dimensions.width.toInt();
    final height = _dimensions.height.toInt();

    final info = Float32List(8)
      ..[0] = width == 0 ? 0.0 : 1.0 / width
      ..[1] = height == 0 ? 0.0 : 1.0 / height
      ..[2] = width.toDouble()
      ..[3] = height.toDouble()
      ..[4] = _settings.threshold
      ..[5] = _settings.maxSearchSteps.clamp(1, 112).toDouble()
      ..[6] = _settings.maxDiagonalSearchSteps.clamp(1, 20).toDouble()
      ..[7] = _settings.cornerRounding.clamp(0.0, 100.0);
    final infoView = context.transientsBuffer.emplace(
      ByteData.sublistView(info),
    );

    // Pass 1: edge detection. Non-edge texels discard, so the target must
    // clear to zero.
    final edges = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'smaa_edges',
      ),
    );
    {
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      final renderPass = commandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: edges,
            loadAction: gpu.LoadAction.clear,
            clearValue: Vector4.zero(),
          ),
        ),
      );
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _edgesShader));
      bindVertexBufferCompat(renderPass, _quadView, 6);
      renderPass.bindTexture(
        _edgesShader.getUniformSlot('scene_color'),
        input,
        sampler: _linearClamp,
      );
      renderPass.bindUniform(_edgesShader.getUniformSlot('SmaaInfo'), infoView);
      drawCompat(renderPass, 6);
      rendererSubmissions.submit(commandBuffer);
    }

    // Pass 2: blending weights from the edge, area, and search textures.
    final weights = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'smaa_weights',
      ),
    );
    {
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      final renderPass = commandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: weights,
            loadAction: gpu.LoadAction.clear,
            clearValue: Vector4.zero(),
          ),
        ),
      );
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _weightsShader));
      bindVertexBufferCompat(renderPass, _quadView, 6);
      renderPass.bindTexture(
        _weightsShader.getUniformSlot('edges_texture'),
        edges,
        sampler: _linearClamp,
      );
      renderPass.bindTexture(
        _weightsShader.getUniformSlot('area_texture'),
        _areaTexture!,
        sampler: _linearClamp,
      );
      renderPass.bindTexture(
        _weightsShader.getUniformSlot('search_texture'),
        _searchTexture!,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _weightsShader.getUniformSlot('SmaaInfo'),
        infoView,
      );
      drawCompat(renderPass, 6);
      rendererSubmissions.submit(commandBuffer);
    }

    // Pass 3: neighborhood blending into the output.
    {
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      final renderPass = commandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _output)),
      );
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _blendShader));
      bindVertexBufferCompat(renderPass, _quadView, 6);
      renderPass.bindTexture(
        _blendShader.getUniformSlot('scene_color'),
        input,
        sampler: _linearClamp,
      );
      renderPass.bindTexture(
        _blendShader.getUniformSlot('blend_texture'),
        weights,
        sampler: _linearClamp,
      );
      renderPass.bindUniform(_blendShader.getUniformSlot('SmaaInfo'), infoView);
      drawCompat(renderPass, 6);
      rendererSubmissions.submit(commandBuffer);
    }

    context.blackboard.set(kDisplayColorBlackboardKey, _output);
  }
}
