import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_color_blit_pass.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/render/shadow_pass.dart';

/// Renders one planar reflection group's mirrored scene capture.
///
/// Runs inside the primary view's render graph, after the shadow pass (whose
/// atlas the capture reuses) and before the view's own scene work, so the
/// mirror surface samples this frame's capture. The capture is a bare scene
/// submission: the mirrored [ScenePass] (with planar reflections suppressed,
/// so captures never nest) followed by a blit of its linear HDR color into
/// the group's capture texture. No screen-space post-processing runs inside
/// a capture.
// TODO(planar-capture-inputs): captures produce no scene-color snapshot or
// depth prepass, so materials sampling those engine inputs read their inert
// fallbacks inside a mirror (refraction shows black, depth fades vanish).
class PlanarReflectionCapturePass extends RenderGraphPass {
  PlanarReflectionCapturePass({
    required ScenePass scenePass,
    required gpu.Texture output,
    required TransientTexturePool pool,
    required Object groupKey,
    required int layerMask,
    required ui.Size dimensions,
  }) : _scenePass = scenePass,
       _output = output,
       _pool = pool,
       _groupKey = groupKey,
       _layerMask = layerMask,
       _dimensions = dimensions;

  final ScenePass _scenePass;
  final gpu.Texture _output;
  final TransientTexturePool _pool;
  final Object _groupKey;
  final int _layerMask;
  final ui.Size _dimensions;

  /// The reflection group this capture serves (a shared group id, or the
  /// reflector component for an ungrouped one).
  @visibleForTesting
  Object get groupKey => _groupKey;

  /// The layer mask selecting what renders into the capture.
  @visibleForTesting
  int get layerMask => _layerMask;

  /// The capture resolution in pixels.
  @visibleForTesting
  ui.Size get dimensions => _dimensions;

  /// The texture the capture renders into (the texture mirror materials
  /// sample this frame).
  @visibleForTesting
  gpu.Texture get output => _output;

  /// The capture's inner scene pass.
  @visibleForTesting
  ScenePass get scenePass => _scenePass;

  @override
  String get name => 'PlanarReflectionCapturePass';

  @override
  void execute(RenderGraphContext context) {
    _pool.beginFrame();
    // The capture runs against its own blackboard (its scene color must not
    // clobber the view's), seeded with the frame's shadow atlas so shadows
    // are reused rather than re-rendered.
    final blackboard = Blackboard();
    final shadowMap = context.blackboard.get<gpu.Texture>(
      kShadowMapBlackboardKey,
    );
    if (shadowMap != null) {
      blackboard.set(kShadowMapBlackboardKey, shadowMap);
    }
    final inner = RenderGraphContext(
      transientsBuffer: context.transientsBuffer,
      texturePool: _pool,
      blackboard: blackboard,
    );
    _scenePass.execute(inner);
    SceneColorBlitPass(output: _output).execute(inner);
  }
}
