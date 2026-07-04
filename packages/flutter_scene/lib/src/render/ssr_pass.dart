import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/screen_space_reflections.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

// Two triangles of NDC positions covering the screen (6 vec2s).
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
// edges anyway, so it is always sampled with nearest filtering. Mirrors the
// occlusion pass.
final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// Adds screen-space reflections to the linear HDR scene color and
/// republishes the result under [kSceneColorBlackboardKey].
///
/// Two full-screen fragment draws, no compute: a trace at the (possibly
/// reduced) reflection resolution that writes a reflection buffer
/// (`flutter_scene_ssr.frag`), then a full-resolution composite that
/// bilinear-upscales and blends it over the scene color
/// (`flutter_scene_ssr_composite.frag`).
class SsrPass extends RenderGraphPass {
  SsrPass({
    required ui.Size dimensions,
    required ScreenSpaceReflectionsSettings settings,
    required double fovRadiansY,
    required double near,
    required double far,
  }) : _dimensions = dimensions,
       _settings = settings,
       _fovRadiansY = fovRadiansY,
       _near = near,
       _far = far;

  final ui.Size _dimensions;
  final ScreenSpaceReflectionsSettings _settings;
  final double _fovRadiansY;
  final double _near;
  final double _far;

  // The shader's constant march-loop bound; user step counts clamp to this.
  static const int _maxStepCeiling = 256;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader = baseShaderLibrary['SsrFragment']!;
  static final gpu.Shader _compositeShader =
      baseShaderLibrary['SsrCompositeFragment']!;

  @override
  String get name => 'SsrPass';

  @override
  void execute(RenderGraphContext context) {
    final sceneColor = context.blackboard.require<gpu.Texture>(
      kSceneColorBlackboardKey,
    );
    final linearDepth = context.blackboard.require<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );

    final width = _dimensions.width.toInt();
    final height = _dimensions.height.toInt();

    // The reflection is traced at a (possibly reduced) resolution and
    // bilinear-upscaled by the composite, so the reflection layer scales
    // cheaply while the scene image stays full resolution.
    final scale = _settings.resolutionScale.clamp(0.1, 1.0);
    final traceWidth = math.max(1, (width * scale).round());
    final traceHeight = math.max(1, (height * scale).round());
    final reflection = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: traceWidth,
        height: traceHeight,
        format: gpu.PixelFormat.r16g16b16a16Float,
        debugName: 'ssr_reflection',
      ),
    );

    final tanHalfFovY = math.tan(_fovRadiansY * 0.5);
    final aspect = _dimensions.width / _dimensions.height;
    final tanHalfFovX = tanHalfFovY * aspect;

    final maxSteps = _settings.maxSteps.clamp(1, _maxStepCeiling);
    final maxDistance = _settings.maxDistance;
    final thickness = _settings.thickness;
    // A small offset off the surface to avoid self-intersection at the first
    // sample. Kept independent of thickness (a scale-relative fraction of the
    // march distance) so thickness only controls hit acceptance and does not
    // shift the reflection geometry.
    final startBias = maxDistance * 0.003;
    final debugView = _settings.debugView.index.toDouble();

    // Trace: the viewport is the reduced trace resolution, so the pixel-space
    // march (stride, step budget) is measured in trace pixels.
    final info = Float32List(20)
      ..[0] = traceWidth.toDouble()
      ..[1] = traceHeight.toDouble()
      ..[2] = 1.0 / traceWidth
      ..[3] = 1.0 / traceHeight
      ..[4] = tanHalfFovX
      ..[5] = tanHalfFovY
      ..[6] = _near
      ..[7] = _far
      ..[8] = maxDistance
      ..[9] = thickness
      ..[10] = startBias
      ..[11] = maxSteps.toDouble()
      ..[12] = _settings.intensity
      ..[13] = debugView
      ..[14] = _settings.blur
      ..[15] = _settings.stride
      ..[16] = _settings.distanceFadeStart;

    final traceCmd = gpu.gpuContext.createCommandBuffer();
    final tracePass = traceCmd.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: reflection)),
    );
    tracePass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _fragmentShader),
    );
    tracePass.setColorBlendEnable(false);
    bindVertexBufferCompat(tracePass, _fullscreenQuad(), 6);
    tracePass.bindUniform(
      _fragmentShader.getUniformSlot('SsrInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    tracePass.bindTexture(
      _fragmentShader.getUniformSlot('input_color'),
      sceneColor,
      sampler: _linearClamp,
    );
    tracePass.bindTexture(
      _fragmentShader.getUniformSlot('linear_depth'),
      linearDepth,
      sampler: _nearestClamp,
    );
    drawCompat(tracePass, 6);
    rendererSubmissions.submit(traceCmd);

    // Composite: bilinear-upscale the reflection and blend it over the
    // full-resolution scene color.
    final output = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: gpu.PixelFormat.r16g16b16a16Float,
        debugName: 'ssr_scene_color',
      ),
    );
    final compositeInfo = Float32List(4)..[0] = debugView;
    final compositeCmd = gpu.gpuContext.createCommandBuffer();
    final compositePass = compositeCmd.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: output)),
    );
    compositePass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _compositeShader),
    );
    compositePass.setColorBlendEnable(false);
    bindVertexBufferCompat(compositePass, _fullscreenQuad(), 6);
    compositePass.bindUniform(
      _compositeShader.getUniformSlot('CompositeInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(compositeInfo)),
    );
    compositePass.bindTexture(
      _compositeShader.getUniformSlot('input_color'),
      sceneColor,
      sampler: _linearClamp,
    );
    compositePass.bindTexture(
      _compositeShader.getUniformSlot('ssr_reflection'),
      reflection,
      sampler: _linearClamp,
    );
    drawCompat(compositePass, 6);
    rendererSubmissions.submit(compositeCmd);

    context.blackboard.set(kSceneColorBlackboardKey, output);
  }
}
