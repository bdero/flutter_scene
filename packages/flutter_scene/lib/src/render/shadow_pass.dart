import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_encoder.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';

/// Render-graph blackboard key under which [ShadowPass] publishes the shadow
/// map atlas (a depth-in-`.r` fp32 texture). The downstream scene pass reads it
/// from here.
const String kShadowMapBlackboardKey = 'directional_shadow_map';

/// Render-graph blackboard key under which [ShadowPass] publishes the packed
/// shadow uniform (the `PostShadowInfo` std140 block: per-cascade world->light
/// matrices, split distances, the light direction + cascade count, and the
/// light color). A depth-aware custom pass reads it to sample the shadow map.
const String kShadowUniformBlackboardKey = 'shadow_uniform';

/// Renders the scene's depth into one shared shadow map atlas and publishes it
/// on the render-graph blackboard: the directional light's cascades first, then
/// each shadow-casting spot's cone.
///
/// The atlas is one fp32 color texture holding the tiles as a horizontal strip,
/// each [tileResolution] square (cascade tiles `0..cascades.length`, then spot
/// tiles); window-space depth goes in the red channel (a transient depth
/// attachment backs the depth test). It is cleared to 1.0 so texels no caster
/// covers read as "lit". Sharing one atlas keeps every shadow type on a single
/// sampler in the lit shader.
class ShadowPass extends RenderGraphPass {
  ShadowPass({
    required RenderScene renderScene,
    required int tileResolution,
    required Vector3 cameraPosition,
    List<ShadowCascade> cascades = const [],
    ShadowCasterFaces casterFaces = ShadowCasterFaces.front,
    SpotShadowFrame? spotShadows,
    ByteData? shadowUniform,
  }) : _renderScene = renderScene,
       _cascades = cascades,
       _tileResolution = tileResolution,
       _casterFaces = casterFaces,
       _cameraPosition = cameraPosition,
       _spotShadows = spotShadows,
       _shadowUniform = shadowUniform;

  final RenderScene _renderScene;
  final List<ShadowCascade> _cascades;
  final int _tileResolution;
  final ShadowCasterFaces _casterFaces;
  final SpotShadowFrame? _spotShadows;

  // The packed PostShadowInfo block, published for depth-aware custom passes.
  final ByteData? _shadowUniform;

  // Bound as FrameInfo.camera_position so a `vertex { }` material's
  // camera-relative displacement bends shadow casters the same way as the
  // color pass (see ShadowEncoder).
  final Vector3 _cameraPosition;

  @override
  String get name => 'ShadowPass';

  @override
  void execute(RenderGraphContext context) {
    final spotCount = _spotShadows?.matrices.length ?? 0;
    final totalTiles = _cascades.length + spotCount;
    final atlasWidth = _tileResolution * totalTiles;
    // fp32 (not fp16): the far cascade's orthographic depth range spans
    // hundreds of world units, and fp16's ~11-bit mantissa quantizes
    // window-space depth into steps coarser than the shadow depth bias.
    // That made the flat distant ground self-shadow in moire bands.
    //
    // TODO(bdero): Only the red channel is used. Add r32Float to Flutter
    // GPU and use it here instead.
    final color = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: atlasWidth,
        height: _tileResolution,
        format: gpu.PixelFormat.r32g32b32a32Float,
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

    // Each tile renders into its own slot of the strip. The viewport restricts
    // rasterization to the tile; the shared depth attachment is cleared once for
    // the whole atlas. Renders a tile from a light-space matrix.
    void renderTile(int tile, Matrix4 matrix, ShadowCasterFaces faces) {
      renderPass.setViewport(
        gpu.Viewport(
          x: tile * _tileResolution,
          y: 0,
          width: _tileResolution,
          height: _tileResolution,
        ),
      );
      final encoder = ShadowEncoder(
        renderPass,
        context.transientsBuffer,
        matrix,
        _cameraPosition,
        faces,
      );
      _renderScene.cull(encoder.frustum, encoder.submit);
    }

    // Cascade tiles first (0..cascades.length), then the spot cones.
    for (var c = 0; c < _cascades.length; c++) {
      renderTile(c, _cascades[c].lightSpaceMatrix, _casterFaces);
    }
    final spots = _spotShadows;
    if (spots != null) {
      for (var s = 0; s < spots.matrices.length; s++) {
        renderTile(_cascades.length + s, spots.matrices[s], spots.casterFaces);
      }
    }

    rendererSubmissions.submit(commandBuffer);
    context.blackboard.set(kShadowMapBlackboardKey, color);
    final shadowUniform = _shadowUniform;
    if (shadowUniform != null) {
      context.blackboard.set(kShadowUniformBlackboardKey, shadowUniform);
    }
  }
}
