import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/shadow_catcher_material.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_pass.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';

/// Refreshes the footprint shadow caches of baked-mode [ShadowCatcherMaterial]
/// items, right after the shadow atlas renders so the scene pass samples a
/// current cache in the same frame.
///
/// Per material: the catcher mesh is drawn from a local-space orthographic
/// top-down projection over its XZ footprint, with its own fragment shader in
/// bake mode (raw atlas visibility out), into a low-resolution target sized
/// by the catcher's softness; a separable Gaussian then blurs it into a
/// persistent cache texture the material samples from then on. The catcher's
/// softness rides this blur (the bake draw keeps the scene's atlas softness),
/// so softer shadows bake at lower resolution and cost less, not more.
class ShadowCatcherBakePass extends RenderGraphPass {
  ShadowCatcherBakePass({
    required List<RenderItem> items,
    required EnvironmentMap environmentMap,
    DirectionalLight? directionalLight,
    Vector3? directionalLightDirection,
    PunctualLighting punctualLighting = const PunctualLighting.empty(),
    List<ShadowCascade> cascades = const [],
  }) : _items = items,
       _environmentMap = environmentMap,
       _directionalLight = directionalLight,
       _directionalLightDirection = directionalLightDirection,
       _punctualLighting = punctualLighting,
       _cascades = cascades;

  final List<RenderItem> _items;
  final EnvironmentMap _environmentMap;
  final DirectionalLight? _directionalLight;
  final Vector3? _directionalLightDirection;
  final PunctualLighting _punctualLighting;
  final List<ShadowCascade> _cascades;

  /// The fixed separable-blur radius in cache texels; the bake resolution is
  /// chosen so this spans the catcher's softness in world units.
  static const int _blurRadiusTexels = 4;
  static const int _minResolution = 16;
  static const int _maxResolution = 1024;
  static const int _defaultResolution = 256;

  static final gpu.Shader _blurVertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _blurFragmentShader =
      baseShaderLibrary['ShadowCatcherBlurFragment']!;

  // Two triangles of NDC positions covering the viewport (6 vec2s).
  static final gpu.DeviceBuffer _quadBuffer = gpu.gpuContext
      .createDeviceBufferWithCopy(
        ByteData.sublistView(
          Float32List.fromList(<double>[
            -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
            -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
          ]),
        ),
      );
  static final gpu.BufferView _quadView = gpu.BufferView(
    _quadBuffer,
    offsetInBytes: 0,
    lengthInBytes: 6 * 2 * 4,
  );

  static final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  @override
  String get name => 'ShadowCatcherBakePass';

  @override
  void execute(RenderGraphContext context) {
    final shadowMap = context.blackboard.get<gpu.Texture>(
      kShadowMapBlackboardKey,
    );
    // Materials can be shared by several items; each bakes once, from the
    // first item's transform and footprint.
    final baked = <ShadowCatcherMaterial>{};
    for (final item in _items) {
      final material = item.material;
      if (material is! ShadowCatcherMaterial || !baked.add(material)) continue;
      _bake(context, item, material, shadowMap);
    }
  }

  /// The cache resolution for [material] over a footprint of [footprintWorld]
  /// world units: sized so the fixed blur kernel spans the softness.
  static int bakeResolution(double footprintWorld, double softness) {
    if (softness <= 0.0 || footprintWorld <= 0.0) return _defaultResolution;
    return (footprintWorld / softness * _blurRadiusTexels).ceil().clamp(
      _minResolution,
      _maxResolution,
    );
  }

  void _bake(
    RenderGraphContext context,
    RenderItem item,
    ShadowCatcherMaterial material,
    gpu.Texture? shadowMap,
  ) {
    final geometry = item.geometry;
    final bounds = geometry.localBounds;
    if (bounds == null) return;
    final sizeX = math.max(bounds.max.x - bounds.min.x, 1e-6);
    final sizeZ = math.max(bounds.max.z - bounds.min.z, 1e-6);
    final centerX = (bounds.min.x + bounds.max.x) * 0.5;
    final centerZ = (bounds.min.z + bounds.max.z) * 0.5;

    // The catcher's world-space footprint scale, for the softness-derived
    // resolution (softness is a world-space radius).
    // TODO(shadow-catcher-instances): an instanced catcher bakes one cache
    // from the item transform; per-instance shadows need per-instance bakes.
    final world = item.worldTransform;
    final scaleX = Vector3(world[0], world[1], world[2]).length;
    final scaleZ = Vector3(world[8], world[9], world[10]).length;
    final footprintWorld = math.max(sizeX * scaleX, sizeZ * scaleZ);
    final resolution = bakeResolution(footprintWorld, material.softness);

    // Maps local space to clip space: local XZ spans NDC, local Y is flat.
    // gl_Position = bakeTransform * world, so fold the inverse model in.
    final localToNdc = Matrix4.zero()
      ..setEntry(0, 0, 2.0 / sizeX)
      ..setEntry(0, 3, -2.0 * centerX / sizeX)
      ..setEntry(1, 2, 2.0 / sizeZ)
      ..setEntry(1, 3, -2.0 * centerZ / sizeZ)
      ..setEntry(3, 3, 1.0);
    final worldInverse = Matrix4.copy(world);
    if (worldInverse.invert() == 0.0) return;
    final bakeTransform = (localToNdc * worldInverse) as Matrix4;
    // Only feeds v_viewvector, which the bake output never reads.
    final bakeCameraPosition = world.getTranslation() + Vector3(0.0, 1.0, 0.0);

    final lighting = Lighting(
      environmentMap: _environmentMap,
      directionalLight: _directionalLight,
      directionalLightDirection: _directionalLightDirection,
      punctualParamsTexture: _punctualLighting.paramsTexture,
      punctualIndexTexture: _punctualLighting.indexTexture,
      punctualParamsCount: _punctualLighting.paramsCount,
      punctualIndexWidth: _punctualLighting.indexWidth,
      punctualIndexHeight: _punctualLighting.indexHeight,
      spotShadowCount: shadowMap == null
          ? 0
          : _punctualLighting.spotShadowCount,
      pointShadowTileCount: shadowMap == null
          ? 0
          : _punctualLighting.pointShadowTileCount,
      spotShadowDepthBias: _punctualLighting.spotShadowDepthBias,
      spotShadowNormalBias: _punctualLighting.spotShadowNormalBias,
      spotShadowSoftness: _punctualLighting.spotShadowSoftness,
      shadowMap: shadowMap,
      cascades: shadowMap == null ? const [] : _cascades,
      viewportSize: ui.Size(resolution.toDouble(), resolution.toDouble()),
    );

    // Footprint render: the catcher mesh with its bake-mode fragment shader,
    // cleared to fully lit so texels outside the mesh read as no shadow.
    final footprint = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: resolution,
        height: resolution,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'shadow_catcher_bake',
      ),
    );
    {
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      final pass = commandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: footprint,
            clearValue: Vector4(1.0, 1.0, 1.0, 1.0),
          ),
        ),
      );
      item.applyJointsTexture(geometry);
      final materialVertex = material.materialVertexShader(
        geometry.materialVertexVariant,
      );
      final fragmentShader = material.fragmentShaderForLighting(lighting);
      final pipeline = resolvePipeline(
        materialVertex ?? geometry.vertexShader,
        fragmentShader,
        vertexLayout: geometry.instancedVertexLayout,
      );
      pass.bindPipeline(pipeline);
      material
        ..lightListOffset = item.lightListOffset
        ..lightListCount = item.lightListCount;
      try {
        material.bindForBake(pass, context.transientsBuffer, lighting);
        // The bake projects the plane flat, so both faces are equivalent; no
        // culling keeps a flipped or bottom-viewed plane baking identically.
        pass.setCullMode(gpu.CullMode.none);
        pass.setColorBlendEnable(false);
        pass.setDepthWriteEnable(false);
        pass.setDepthCompareOperation(gpu.CompareFunction.always);
        geometry.bind(
          pass,
          context.transientsBuffer,
          item.worldTransform,
          bakeTransform,
          bakeCameraPosition,
          shaderOverride: materialVertex,
        );
        if (materialVertex != null) {
          material.bindVertexStage(
            pass,
            materialVertex,
            context.transientsBuffer,
          );
        }
        if (geometry.instancedVertexLayout != null &&
            geometry.bindsModelTransformInstance) {
          bindSingleInstanceData(
            pass,
            item.worldTransform,
            slot: geometry.vertexStreamCount,
          );
        }
        geometry.draw(pass);
      } finally {
        material.finishBakeBind();
      }
      rendererSubmissions.submit(commandBuffer);
    }

    // Separable blur into the persistent cache: horizontal into a pooled
    // intermediate, vertical into the cache the material samples per frame.
    final intermediate = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: resolution,
        height: resolution,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'shadow_catcher_blur',
      ),
    );
    final cache = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      resolution,
      resolution,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
    );
    _encodeBlur(context, footprint, intermediate, Vector2(1.0, 0.0));
    _encodeBlur(context, intermediate, cache, Vector2(0.0, 1.0));

    material.completeBake(
      cache,
      Vector4(bounds.min.x, bounds.max.z, 1.0 / sizeX, 1.0 / sizeZ),
    );
  }

  void _encodeBlur(
    RenderGraphContext context,
    gpu.Texture source,
    gpu.Texture target,
    Vector2 axis,
  ) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    pass.bindPipeline(resolvePipeline(_blurVertexShader, _blurFragmentShader));
    pass.setColorBlendEnable(false);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);
    pass.setCullMode(gpu.CullMode.none);
    bindVertexBufferCompat(pass, _quadView, 6);
    pass.bindTexture(
      _blurFragmentShader.getUniformSlot('source_texture'),
      source,
      sampler: _linearClamp,
    );
    final info = Float32List(4)
      ..[0] = axis.x / source.width
      ..[1] = axis.y / source.height;
    pass.bindUniform(
      _blurFragmentShader.getUniformSlot('CatcherBlurInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    drawCompat(pass, 6);
    rendererSubmissions.submit(commandBuffer);
  }
}
