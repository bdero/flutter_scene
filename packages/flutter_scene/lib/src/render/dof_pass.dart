import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/depth_of_field.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;

const gpu.PixelFormat _hdrFormat = gpu.PixelFormat.r16g16b16a16Float;

/// Applies depth of field to the linear HDR scene color: a half-resolution
/// CoC/downsample, near-field CoC dilation, a bokeh gather over a
/// CPU-precomputed aperture kernel, an optional noise postfilter, and a
/// full-resolution composite. Reads the scene color and the camera linear
/// depth from the blackboard and republishes the composited scene color, so
/// bloom and the resolve see the defocused image (bokeh highlights still
/// bloom). Fragment passes only; see `notes/rendering/depth_of_field_design.md`
/// in the development root for the design and survey behind it.
class DofPass extends RenderGraphPass {
  DofPass({
    required DepthOfField settings,
    required ui.Size dimensions,
    required double fovRadiansY,
  }) : _settings = settings,
       _dimensions = dimensions,
       _fovRadiansY = fovRadiansY;

  final DepthOfField _settings;
  final ui.Size _dimensions;
  final double _fovRadiansY;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _cocShader = baseShaderLibrary['DofCocFragment']!;
  static final gpu.Shader _dilateShader =
      baseShaderLibrary['DofDilateFragment']!;
  static final gpu.Shader _gatherShader =
      baseShaderLibrary['DofGatherFragment']!;
  static final gpu.Shader _postFilterShader =
      baseShaderLibrary['DofPostFilterFragment']!;
  static final gpu.Shader _compositeShader =
      baseShaderLibrary['DofCompositeFragment']!;

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
  String get name => 'DofPass';

  @override
  void execute(RenderGraphContext context) {
    final scene = context.blackboard.require<gpu.Texture>(
      kSceneColorBlackboardKey,
    );
    final depth = context.blackboard.require<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );

    final fullWidth = _dimensions.width.toInt();
    final fullHeight = _dimensions.height.toInt();
    final halfWidth = math.max(1, fullWidth ~/ 2);
    final halfHeight = math.max(1, fullHeight ~/ 2);

    gpu.Texture acquire(String debugName, {bool half = true}) =>
        context.texturePool.acquire(
          TransientTextureDescriptor.color(
            width: half ? halfWidth : fullWidth,
            height: half ? halfHeight : fullHeight,
            format: _hdrFormat,
            debugName: debugName,
          ),
        );

    // 1. Half-res downsample + signed CoC (in half-res pixel radii).
    final cocColor = acquire('dof_coc_color');
    final cocInfo = Float32List(8)
      ..[0] = _settings.cocScale(_fovRadiansY, halfHeight.toDouble())
      ..[1] = _settings.focusDistance
      ..[2] = _settings.maxForegroundBlur
      ..[3] = _settings.maxBackgroundBlur
      ..[4] = 1.0 / fullWidth
      ..[5] = 1.0 / fullHeight;
    _draw(
      context,
      _cocShader,
      target: cocColor,
      uniforms: {'CocInfo': cocInfo},
      textures: {'scene_color': scene, 'linear_depth': depth},
    );

    // 2. Near-field CoC dilation, so foreground blur crosses silhouettes.
    final nearCoc = acquire('dof_near_coc');
    final dilateInfo = Float32List(4)
      ..[0] = _settings.maxForegroundBlur * 0.5
      ..[1] = 1.0 / halfWidth
      ..[2] = 1.0 / halfHeight;
    _draw(
      context,
      _dilateShader,
      target: nearCoc,
      uniforms: {'DilateInfo': dilateInfo},
      textures: {'coc_color': cocColor},
    );

    // 3. The bokeh gather. The kernel block is memoized on the settings
    // object against the shape parameters (this pass is rebuilt every frame),
    // so per frame this is one transient upload.
    final gathered = acquire('dof_gather');
    _draw(
      context,
      _gatherShader,
      target: gathered,
      uniforms: {
        'GatherInfo': _settings.gatherInfoBlock(halfWidth, halfHeight),
      },
      textures: {'coc_color': cocColor, 'near_coc': nearCoc},
    );

    // 4. Postfilter (skipped on the low tier).
    var dof = gathered;
    if (_settings.usePostFilter) {
      final filtered = acquire('dof_postfilter');
      final postInfo = Float32List(4)
        ..[0] = 1.0 / halfWidth
        ..[1] = 1.0 / halfHeight;
      _draw(
        context,
        _postFilterShader,
        target: filtered,
        uniforms: {'PostFilterInfo': postInfo},
        textures: {'dof_texture': dof},
      );
      dof = filtered;
    }

    // 5. Full-res composite over the sharp scene, republished as the scene
    // color for bloom and the resolve.
    final output = acquire('dof_output', half: false);
    _draw(
      context,
      _compositeShader,
      target: output,
      textures: {'scene_color': scene, 'dof_texture': dof},
    );
    context.blackboard.set(kSceneColorBlackboardKey, output);
  }

  /// One fullscreen fragment pass into [target].
  void _draw(
    RenderGraphContext context,
    gpu.Shader fragment, {
    required gpu.Texture target,
    Map<String, Float32List> uniforms = const {},
    Map<String, gpu.Texture> textures = const {},
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    final pipeline = resolvePipeline(_vertexShader, fragment);
    renderPass.bindPipeline(pipeline);
    renderPass.setColorBlendEnable(false);
    renderPass.setCullMode(gpu.CullMode.none);
    bindVertexBufferCompat(renderPass, _quadView, 6);
    for (final entry in uniforms.entries) {
      renderPass.bindUniform(
        fragment.getUniformSlot(entry.key),
        context.transientsBuffer.emplace(ByteData.sublistView(entry.value)),
      );
    }
    for (final entry in textures.entries) {
      renderPass.bindTexture(
        fragment.getUniformSlot(entry.key),
        entry.value,
        sampler: _linearClamp,
      );
    }
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }
}
