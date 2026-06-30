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

/// Traces the camera linear-depth target to composite screen-space
/// reflections onto the linear HDR scene color, then republishes the result
/// under [kSceneColorBlackboardKey] for the rest of the pipeline.
///
/// A single full-screen fragment pass, no compute. See
/// `flutter_scene_ssr.frag` for the algorithm.
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
  static const int _maxStepCeiling = 96;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader = baseShaderLibrary['SsrFragment']!;

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
    final output = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: gpu.PixelFormat.r16g16b16a16Float,
        debugName: 'ssr_scene_color',
      ),
    );

    final tanHalfFovY = math.tan(_fovRadiansY * 0.5);
    final aspect = _dimensions.width / _dimensions.height;
    final tanHalfFovX = tanHalfFovY * aspect;

    final stepCount = _settings.maxSteps.clamp(1, _maxStepCeiling);
    final maxDistance = _settings.maxDistance;
    final thickness = _settings.thickness;
    // Start the ray off the surface by a fraction of a step to avoid
    // self-intersection.
    final startBias = (maxDistance / stepCount) * 0.5;

    final info = Float32List(16)
      ..[0] = width.toDouble()
      ..[1] = height.toDouble()
      ..[2] = 1.0 / width
      ..[3] = 1.0 / height
      ..[4] = tanHalfFovX
      ..[5] = tanHalfFovY
      ..[6] = _near
      ..[7] = _far
      ..[8] = maxDistance
      ..[9] = thickness
      ..[10] = startBias
      ..[11] = stepCount.toDouble()
      ..[12] = _settings.intensity
      ..[13] = _settings.debugView.index.toDouble()
      ..[14] = _settings.blur;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: output)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, _fragmentShader),
    );
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _fullscreenQuad(), 6);

    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('SsrInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('input_color'),
      sceneColor,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('linear_depth'),
      linearDepth,
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    commandBuffer.submit();

    context.blackboard.set(kSceneColorBlackboardKey, output);
  }
}
