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

/// Draws the scene graph (opaque, then depth-sorted translucent) into one
/// color/depth render target.
///
/// For now this is the final pass in the [RenderGraph] and it targets the
/// swapchain render target directly. Once the HDR pipeline lands it will
/// target an offscreen HDR color buffer instead, with a tone-mapping pass
/// downstream. If a [ShadowPass] ran earlier this frame, its shadow map
/// is picked up from the render-graph blackboard and threaded into the
/// per-draw [Lighting].
class ScenePass extends RenderGraphPass {
  ScenePass({
    required gpu.RenderTarget target,
    required Camera camera,
    required Node root,
    required ui.Size dimensions,
    required Environment environment,
    DirectionalLight? directionalLight,
    Matrix4? lightSpaceMatrix,
  }) : _target = target,
       _camera = camera,
       _root = root,
       _dimensions = dimensions,
       _environment = environment,
       _directionalLight = directionalLight,
       _lightSpaceMatrix = lightSpaceMatrix;

  final gpu.RenderTarget _target;
  final Camera _camera;
  final Node _root;
  final ui.Size _dimensions;
  final Environment _environment;
  final DirectionalLight? _directionalLight;
  final Matrix4? _lightSpaceMatrix;

  @override
  String get name => 'ScenePass';

  @override
  void execute(RenderGraphContext context) {
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
    final renderPass = commandBuffer.createRenderPass(_target);
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
  }
}
