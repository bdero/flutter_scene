import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_encoder.dart';

/// Render-graph blackboard key under which [ShadowPass] publishes the
/// directional shadow map atlas (a depth-in-`.r` fp16 texture). The
/// downstream scene pass reads it from here.
const String kShadowMapBlackboardKey = 'directional_shadow_map';

/// Renders the scene's depth from a directional light into a cascaded
/// shadow map atlas and publishes it on the render-graph blackboard.
///
/// The atlas is one fp16 color texture holding the cascade tiles as a
/// horizontal strip, each [tileResolution] square; window-space depth
/// goes in the red channel (a transient depth attachment backs the
/// depth test). It is cleared to 1.0 so texels no caster covers read as
/// "lit". Each cascade renders into its own tile through a viewport.
class ShadowPass extends RenderGraphPass {
  ShadowPass({
    required RenderScene renderScene,
    required List<ShadowCascade> cascades,
    required int tileResolution,
  }) : _renderScene = renderScene,
       _cascades = cascades,
       _tileResolution = tileResolution;

  final RenderScene _renderScene;
  final List<ShadowCascade> _cascades;
  final int _tileResolution;

  @override
  String get name => 'ShadowPass';

  @override
  void execute(RenderGraphContext context) {
    final atlasWidth = _tileResolution * _cascades.length;
    final color = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: atlasWidth,
        height: _tileResolution,
        format: gpu.PixelFormat.r16g16b16a16Float,
        debugName: 'directional_shadow_map',
      ),
    );
    final depth = context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: atlasWidth,
        height: _tileResolution,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        debugName: 'directional_shadow_map_depth',
      ),
    );
    final target = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: color,
        // White = depth 1.0 in .r => fragments no caster covers are lit.
        clearValue: Vector4(1.0, 1.0, 1.0, 1.0),
      ),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthClearValue: 1.0,
      ),
    );
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(target);

    // Each cascade renders into its own tile of the strip. The viewport
    // restricts rasterization to the tile; the shared depth attachment
    // is cleared once for the whole atlas.
    for (var c = 0; c < _cascades.length; c++) {
      renderPass.setViewport(
        gpu.Viewport(
          x: c * _tileResolution,
          y: 0,
          width: _tileResolution,
          height: _tileResolution,
        ),
      );
      final encoder = ShadowEncoder(
        renderPass,
        context.transientsBuffer,
        _cascades[c].lightSpaceMatrix,
      );
      _renderScene.cull(encoder.frustum, encoder.submit);
    }

    commandBuffer.submit();
    context.blackboard.set(kShadowMapBlackboardKey, color);
  }
}
