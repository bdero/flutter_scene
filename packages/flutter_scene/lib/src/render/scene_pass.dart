import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/shadow_pass.dart';
import 'package:flutter_scene/src/scene_encoder.dart';

/// Render-graph blackboard key for the linear HDR scene-color texture
/// [ScenePass] produces. The downstream tone-mapping pass reads it.
const String kHdrColorBlackboardKey = 'hdr_scene_color';

/// Draws the scene graph (opaque, then depth-sorted translucent) into a
/// floating-point HDR color target, publishing it on the render-graph
/// blackboard for the tone-mapping pass to resolve. If a [ShadowPass] ran
/// earlier this frame its shadow map is picked up from the blackboard and
/// threaded into the per-draw [Lighting].
class ScenePass extends RenderGraphPass {
  ScenePass({
    required Camera camera,
    required Node root,
    required ui.Size dimensions,
    required Environment environment,
    required bool enableMsaa,
    DirectionalLight? directionalLight,
    Matrix4? lightSpaceMatrix,
  }) : _camera = camera,
       _root = root,
       _dimensions = dimensions,
       _environment = environment,
       _enableMsaa = enableMsaa,
       _directionalLight = directionalLight,
       _lightSpaceMatrix = lightSpaceMatrix;

  final Camera _camera;
  final Node _root;
  final ui.Size _dimensions;
  final Environment _environment;
  final bool _enableMsaa;
  final DirectionalLight? _directionalLight;
  final Matrix4? _lightSpaceMatrix;

  static const gpu.PixelFormat _hdrFormat = gpu.PixelFormat.r16g16b16a16Float;

  @override
  String get name => 'ScenePass';

  @override
  void execute(RenderGraphContext context) {
    final width = _dimensions.width.toInt();
    final height = _dimensions.height.toInt();

    final hdrColor = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: _hdrFormat,
        debugName: 'hdr_scene_color',
      ),
    );
    final depth = context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: width,
        height: height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        sampleCount: _enableMsaa ? 4 : 1,
        debugName: 'scene_depth',
      ),
    );
    final colorAttachment = gpu.ColorAttachment(texture: hdrColor);
    if (_enableMsaa) {
      final msaaColor = context.texturePool.acquire(
        TransientTextureDescriptor(
          width: width,
          height: height,
          format: _hdrFormat,
          sampleCount: 4,
          storageMode: gpu.StorageMode.deviceTransient,
          enableShaderReadUsage: false,
          debugName: 'hdr_scene_color_msaa',
        ),
      );
      colorAttachment.texture = msaaColor;
      colorAttachment.resolveTexture = hdrColor;
      colorAttachment.storeAction = gpu.StoreAction.multisampleResolve;
    }
    final target = gpu.RenderTarget.singleColor(
      colorAttachment,
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthClearValue: 1.0,
      ),
    );

    final shadowMap = context.blackboard.get<gpu.Texture>(
      kShadowMapBlackboardKey,
    );
    final lighting = Lighting(
      environment: _environment,
      directionalLight: _directionalLight,
      shadowMap: shadowMap,
      lightSpaceMatrix: shadowMap == null ? null : _lightSpaceMatrix,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(target);
    final encoder = SceneEncoder(
      renderPass,
      context.transientsBuffer,
      _camera,
      _dimensions,
      lighting,
    );
    _root.render(encoder, Matrix4.identity());
    encoder.flushTranslucent();
    commandBuffer.submit();

    context.blackboard.set(kHdrColorBlackboardKey, hdrColor);
  }
}
