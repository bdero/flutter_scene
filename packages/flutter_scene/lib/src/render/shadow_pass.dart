import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/shadow_encoder.dart';

/// Render-graph blackboard key under which [ShadowPass] publishes the
/// directional shadow map (a depth-in-`.r` fp16 texture). The downstream
/// scene pass reads it from here.
const String kShadowMapBlackboardKey = 'directional_shadow_map';

/// Renders the scene's depth from a directional light into an offscreen
/// shadow map and publishes it on the render-graph blackboard.
///
/// The shadow map is an fp16 color attachment with the window-space depth
/// in its red channel (a transient depth attachment backs the depth
/// test). Cleared to 1.0 so texels no caster covers read as "lit".
class ShadowPass extends RenderGraphPass {
  ShadowPass({
    required Node root,
    required Matrix4 lightSpaceMatrix,
    required int resolution,
  }) : _root = root,
       _lightSpaceMatrix = lightSpaceMatrix,
       _resolution = resolution;

  final Node _root;
  final Matrix4 _lightSpaceMatrix;
  final int _resolution;

  @override
  String get name => 'ShadowPass';

  @override
  void execute(RenderGraphContext context) {
    final color = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: _resolution,
        height: _resolution,
        format: gpu.PixelFormat.r16g16b16a16Float,
        debugName: 'directional_shadow_map',
      ),
    );
    final depth = context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: _resolution,
        height: _resolution,
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
    final encoder = ShadowEncoder(
      renderPass,
      context.transientsBuffer,
      _lightSpaceMatrix,
    );
    _root.render(encoder, Matrix4.identity());
    commandBuffer.submit();
    context.blackboard.set(kShadowMapBlackboardKey, color);
  }
}
