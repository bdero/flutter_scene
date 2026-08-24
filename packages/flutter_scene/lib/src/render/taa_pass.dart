import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart'
    show kLinearDepthBlackboardKey;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart'
    show kSceneColorBlackboardKey;
import 'package:flutter_scene/src/render/temporal_anti_aliasing.dart';
import 'package:flutter_scene/src/render/velocity_pass.dart'
    show kVelocityBlackboardKey;
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';

final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

// Fullscreen NDC triangles for the TAA resolve.
final gpu.DeviceBuffer _taaFullscreenBuffer = gpu.gpuContext
    .createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );
final gpu.BufferView _taaFullscreenView = gpu.BufferView(
  _taaFullscreenBuffer,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

/// Persistent state of the temporal anti-aliasing history across frames.
class TaaHistoryState {
  gpu.Texture? _historyA;
  gpu.Texture? _historyB;
  gpu.Texture? _previousLinearDepth;
  bool _historyIsA = true;
  int _width = 0;
  int _height = 0;
  bool _hasHistory = false;

  Matrix4? previousViewTransform;
  Vector2 previousJitterNdc = Vector2.zero();
  Vector2 previousJitterUv = Vector2.zero();

  gpu.Texture get currentHistory => _historyIsA ? _historyA! : _historyB!;
  gpu.Texture get writeHistory => _historyIsA ? _historyB! : _historyA!;
  gpu.Texture? get previousLinearDepth => _previousLinearDepth;
  bool get hasHistory => _hasHistory;

  void ensureSize(int width, int height) {
    if (_width == width && _height == height && _historyA != null) return;
    _width = width;
    _height = height;
    _historyA = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    _historyB = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    _previousLinearDepth = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    _historyIsA = true;
    _hasHistory = false;
  }

  void finishResolve() {
    _historyIsA = !_historyIsA;
    _hasHistory = true;
  }

  void invalidate() {
    _hasHistory = false;
  }

  void dispose() {
    _historyA = null;
    _historyB = null;
    _previousLinearDepth = null;
    _hasHistory = false;
    _width = 0;
    _height = 0;
  }
}

/// Render-graph pass resolving temporal anti-aliasing on HDR scene color.
class TaaPass extends RenderGraphPass {
  TaaPass({
    required this.dimensions,
    required this.settings,
    required this.state,
    required this.currentToPreviousViewProjection,
    required this.cameraPosition,
    required this.tanHalfFovX,
    required this.tanHalfFovY,
    required this.far,
    required this.near,
    required this.currentJitterNdc,
    required this.previousJitterNdc,
  });

  final ui.Size dimensions;
  final TemporalAntiAliasingSettings settings;
  final TaaHistoryState state;
  final Matrix4 currentToPreviousViewProjection;
  final Vector3 cameraPosition;
  final double tanHalfFovX;
  final double tanHalfFovY;
  final double far;
  final double near;
  final Vector2 currentJitterNdc;
  final Vector2 previousJitterNdc;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader = baseShaderLibrary['TaaFragment']!;

  @override
  String get name => 'TaaPass';

  @override
  void execute(RenderGraphContext context) {
    final currentColor = context.blackboard.get<gpu.Texture>(
      kSceneColorBlackboardKey,
    );
    final depthNormal = context.blackboard.get<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );
    if (currentColor == null || depthNormal == null) return;

    final width = dimensions.width.toInt();
    final height = dimensions.height.toInt();
    state.ensureSize(width, height);

    final velocity =
        context.blackboard.get<gpu.Texture>(kVelocityBlackboardKey) ??
        depthNormal;

    final writeHistory = state.writeHistory;
    final readHistory = state.hasHistory ? state.currentHistory : currentColor;
    final prevDepth = state.previousLinearDepth ?? depthNormal;

    final targetTexture = writeHistory;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: targetTexture,
          loadAction: gpu.LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ),
    );

    renderPass.setColorBlendEnable(false);
    renderPass.setCullMode(gpu.CullMode.none);
    renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _fragmentShader));
    bindVertexBufferCompat(renderPass, _taaFullscreenView, 6);

    final infoData = Float32List(40);
    infoData.setRange(0, 16, currentToPreviousViewProjection.storage);
    infoData[16] = cameraPosition.x;
    infoData[17] = cameraPosition.y;
    infoData[18] = cameraPosition.z;
    infoData[19] = 1.0;
    infoData[20] = tanHalfFovX;
    infoData[21] = tanHalfFovY;
    infoData[22] = far;
    infoData[23] = near;
    infoData[24] = currentJitterNdc.x;
    infoData[25] = currentJitterNdc.y;
    infoData[26] = previousJitterNdc.x;
    infoData[27] = previousJitterNdc.y;
    infoData[28] = state.hasHistory ? settings.minimumCurrentWeight : 1.0;
    infoData[29] = settings.varianceGamma;
    infoData[30] = settings.sharpness;
    infoData[31] = settings.objectMotion ? 1.0 : 0.0;
    infoData[32] = width.toDouble();
    infoData[33] = height.toDouble();
    infoData[34] = 1.0 / width;
    infoData[35] = 1.0 / height;

    renderPass.bindUniform(
      _fragmentShader.getUniformSlot('TaaInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(infoData)),
    );

    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('current_color'),
      currentColor,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('history_color'),
      readHistory,
      sampler: _linearClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('velocity_texture'),
      velocity,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('current_depth'),
      depthNormal,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.getUniformSlot('previous_depth'),
      prevDepth,
      sampler: _nearestClamp,
    );

    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);

    final prevDepthTexture = state.previousLinearDepth;
    if (prevDepthTexture != null) {
      final depthCopyCmd = gpu.gpuContext.createCommandBuffer();
      final depthCopyPass = depthCopyCmd.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: prevDepthTexture,
            loadAction: gpu.LoadAction.clear,
            clearValue: Vector4.zero(),
          ),
        ),
      );
      depthCopyPass.setColorBlendEnable(false);
      depthCopyPass.setCullMode(gpu.CullMode.none);
      depthCopyPass.setPrimitiveType(gpu.PrimitiveType.triangle);
      final copyPipeline = resolvePipeline(
        _vertexShader,
        baseShaderLibrary['CopyFragment']!,
      );
      depthCopyPass.bindPipeline(copyPipeline);
      bindVertexBufferCompat(depthCopyPass, _taaFullscreenView, 6);
      depthCopyPass.bindTexture(
        baseShaderLibrary['CopyFragment']!.getUniformSlot('source_texture'),
        depthNormal,
        sampler: _nearestClamp,
      );
      drawCompat(depthCopyPass, 6);
      rendererSubmissions.submit(depthCopyCmd);
    }

    state.finishResolve();
    context.blackboard.set(kSceneColorBlackboardKey, targetTexture);
  }
}
