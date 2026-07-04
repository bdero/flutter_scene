import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/light.dart' show ShadowCasterFaces;
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_encoder.dart';

/// The most spot lights that can cast a shadow at once. Each takes a tile in
/// the spot-shadow atlas and a perspective depth pass, so the count is capped;
/// spots past the budget shade unshadowed. Kept small deliberately (shadowed
/// local lights are expensive, especially on mobile).
const int kMaxSpotShadows = 4;

/// Render-graph blackboard key under which [SpotShadowPass] publishes the
/// spot-shadow atlas (a depth-in-`.r` fp32 texture, one tile per shadow-casting
/// spot). The scene pass reads it from here.
const String kSpotShadowMapBlackboardKey = 'spot_shadow_map';

/// The shadow-casting spots selected for a frame, in slot order (a spot's slot
/// is its index here, matching its atlas tile and matrix row). All tiles share
/// one resolution and bias, taken from the first caster (per-spot shadow
/// parameters are a future refinement).
class SpotShadowFrame {
  SpotShadowFrame({
    required this.casters,
    required this.matrices,
    required this.tileResolution,
    required this.depthBias,
    required this.normalBias,
    required this.softness,
  });

  /// The shadow-casting spot components, index = slot.
  final List<SpotLightComponent> casters;

  /// World -> spot-clip matrix per caster (parallel to [casters]).
  final List<Matrix4> matrices;

  final int tileResolution;
  final double depthBias;
  final double normalBias;
  final double softness;

  /// The slot assigned to [component] (its atlas tile and matrix row), or -1
  /// when it is not a shadow caster this frame.
  int slotOf(SpotLightComponent component) => casters.indexOf(component);
}

/// Selects up to [kMaxSpotShadows] shadow-casting spots from [spots] and
/// computes their world -> spot-clip matrices, or null when none cast a shadow.
SpotShadowFrame? collectSpotShadows(List<SpotLightComponent> spots) {
  final casters = <SpotLightComponent>[];
  for (final spot in spots) {
    if (!spot.light.castsShadow) continue;
    casters.add(spot);
    if (casters.length >= kMaxSpotShadows) break;
  }
  if (casters.isEmpty) return null;

  final matrices = [
    for (final caster in casters)
      caster.light.shadowViewProjection(
        caster.worldPosition,
        caster.worldDirection,
      ),
  ];
  final first = casters.first.light;
  return SpotShadowFrame(
    casters: casters,
    matrices: matrices,
    tileResolution: first.shadowMapResolution,
    depthBias: first.shadowDepthBias,
    normalBias: first.shadowNormalBias,
    softness: first.shadowSoftness,
  );
}

/// Renders each shadow-casting spot's depth into a tile of the spot-shadow
/// atlas (one square [SpotShadowFrame.tileResolution] tile per caster, laid out
/// as a horizontal strip) and publishes it on the blackboard. Mirrors the
/// directional `ShadowPass`, reusing [ShadowEncoder] with the spot's
/// perspective matrix in place of an orthographic cascade matrix.
class SpotShadowPass extends RenderGraphPass {
  SpotShadowPass({
    required RenderScene renderScene,
    required SpotShadowFrame frame,
    required Vector3 cameraPosition,
  }) : _renderScene = renderScene,
       _frame = frame,
       _cameraPosition = cameraPosition;

  final RenderScene _renderScene;
  final SpotShadowFrame _frame;
  final Vector3 _cameraPosition;

  @override
  String get name => 'SpotShadowPass';

  @override
  void execute(RenderGraphContext context) {
    final tile = _frame.tileResolution;
    final atlasWidth = tile * _frame.matrices.length;
    final color = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: atlasWidth,
        height: tile,
        format: gpu.PixelFormat.r32g32b32a32Float,
        debugName: 'spot_shadow_map',
      ),
    );
    final depth = context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: atlasWidth,
        height: tile,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        debugName: 'spot_shadow_map_depth',
      ),
    );
    final target = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: color,
        // White = depth 1.0 in .r, so texels no caster covers read as lit.
        clearValue: Vector4(1.0, 1.0, 1.0, 1.0),
      ),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthClearValue: 1.0,
      ),
    );
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(target);

    for (var slot = 0; slot < _frame.matrices.length; slot++) {
      renderPass.setViewport(
        gpu.Viewport(x: slot * tile, y: 0, width: tile, height: tile),
      );
      final encoder = ShadowEncoder(
        renderPass,
        context.transientsBuffer,
        _frame.matrices[slot],
        _cameraPosition,
        // Front faces cast (general-purpose); a spot lights closed and open
        // meshes alike, so keep the default rather than second-depth.
        ShadowCasterFaces.front,
      );
      _renderScene.cull(encoder.frustum, encoder.submit);
    }

    commandBuffer.submit();
    context.blackboard.set(kSpotShadowMapBlackboardKey, color);
  }
}
