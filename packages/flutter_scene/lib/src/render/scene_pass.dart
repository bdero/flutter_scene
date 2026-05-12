import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/scene_encoder.dart';

/// Draws the scene graph (opaque, then depth-sorted translucent) into one
/// color/depth render target.
///
/// For now this is the only pass in the [RenderGraph] and it targets the
/// swapchain render target directly. Once the HDR pipeline lands it will
/// target an offscreen HDR color buffer instead, with a tone-mapping pass
/// downstream.
class ScenePass extends RenderGraphPass {
  ScenePass({
    required gpu.RenderTarget target,
    required Camera camera,
    required Node root,
    required ui.Size dimensions,
    required Environment environment,
  }) : _target = target,
       _camera = camera,
       _root = root,
       _dimensions = dimensions,
       _environment = environment;

  final gpu.RenderTarget _target;
  final Camera _camera;
  final Node _root;
  final ui.Size _dimensions;
  final Environment _environment;

  @override
  String get name => 'ScenePass';

  @override
  void execute(RenderGraphContext context) {
    final renderPass = context.commandBuffer.createRenderPass(_target);
    final encoder = SceneEncoder(
      renderPass,
      context.transientsBuffer,
      _camera,
      _dimensions,
      _environment,
    );
    _root.render(encoder, Matrix4.identity());
    encoder.flushTranslucent();
  }
}
