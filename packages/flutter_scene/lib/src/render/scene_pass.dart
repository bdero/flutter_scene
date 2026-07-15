import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/fog.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_pass.dart';
import 'package:flutter_scene/src/render/sh_composite.dart';
import 'package:flutter_scene/src/render/skybox_encoder.dart';
import 'package:flutter_scene/src/render/ssao_pass.dart';
import 'package:flutter_scene/src/scene_encoder.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Render-graph blackboard key for the current scene-color texture.
///
/// [ScenePass] publishes the linear HDR scene color here. Post-processing
/// passes read it and republish their own output, so the resolve pass
/// reads whatever the last pass produced.
const String kSceneColorBlackboardKey = 'scene_color';

/// Render-graph blackboard key for the opaque-phase color snapshot, published
/// by [ScenePass] only when a visible material declares
/// `RenderInput.opaqueSceneColor` (see `Material.sceneInputs`).
const String kOpaqueSceneColorBlackboardKey = 'opaque_scene_color';

/// Draws the scene's render items (opaque, then depth-sorted
/// translucent) into a floating-point HDR color target, publishing it on
/// the render-graph blackboard for the resolve pass to read. If a
/// [ShadowPass] ran earlier this frame its shadow map is picked up from
/// the blackboard and threaded into the per-draw [Lighting].
class ScenePass extends RenderGraphPass {
  ScenePass({
    required Camera camera,
    required RenderScene renderScene,
    required ui.Size dimensions,
    required EnvironmentMap environmentMap,
    EnvironmentMap? environmentMapB,
    double environmentBlend = 0.0,
    required double environmentIntensity,
    Matrix3? environmentTransform,
    Skybox? skybox,
    required bool enableMsaa,
    DirectionalLight? directionalLight,
    Vector3? directionalLightDirection,
    PunctualLighting punctualLighting = const PunctualLighting.empty(),
    List<ShadowCascade> cascades = const [],
    double specularOcclusionMode = 0.0,
    int layerMask = kRenderLayerAll,
    Fog? fog,
    bool captureOpaqueColor = false,
    bool bindSceneDepth = false,
    double time = 0.0,
  }) : _captureOpaqueColor = captureOpaqueColor,
       _bindSceneDepth = bindSceneDepth,
       _time = time,
       _camera = camera,
       _layerMask = layerMask,
       _renderScene = renderScene,
       _dimensions = dimensions,
       _environmentMap = environmentMap,
       _environmentMapB = environmentMapB,
       _environmentBlend = environmentBlend,
       _environmentIntensity = environmentIntensity,
       _environmentTransform = environmentTransform,
       _skybox = skybox,
       _enableMsaa = enableMsaa,
       _directionalLight = directionalLight,
       _directionalLightDirection = directionalLightDirection,
       _punctualLighting = punctualLighting,
       _cascades = cascades,
       _specularOcclusionMode = specularOcclusionMode,
       _fog = fog;

  final Camera _camera;
  final RenderScene _renderScene;
  final ui.Size _dimensions;
  final EnvironmentMap _environmentMap;
  final EnvironmentMap? _environmentMapB;
  final double _environmentBlend;
  final double _environmentIntensity;
  final Matrix3? _environmentTransform;
  final Skybox? _skybox;
  final bool _enableMsaa;
  final DirectionalLight? _directionalLight;
  final Vector3? _directionalLightDirection;
  final PunctualLighting _punctualLighting;
  final int _layerMask;
  final List<ShadowCascade> _cascades;
  final double _specularOcclusionMode;
  final Fog? _fog;

  // Material scene inputs (see Material.sceneInputs): whether to split the
  // pass and snapshot the opaque color, whether to hand materials the
  // prepass linear depth, and the engine time for material animation.
  final bool _captureOpaqueColor;
  final bool _bindSceneDepth;
  final double _time;

  static const gpu.PixelFormat _hdrFormat = gpu.PixelFormat.r16g16b16a16Float;

  @override
  String get name => 'ScenePass';

  @override
  void execute(RenderGraphContext context) {
    final width = _dimensions.width.toInt();
    final height = _dimensions.height.toInt();

    final capture = _captureOpaqueColor;
    final hdrColor = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: _hdrFormat,
        debugName: 'hdr_scene_color',
      ),
    );
    // The split's depth must survive across the two passes, so it cannot be
    // tile-transient there.
    final depth = context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: width,
        height: height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        sampleCount: _enableMsaa ? 4 : 1,
        shaderReadable: capture,
        debugName: 'scene_depth',
      ),
    );
    // The opaque-phase snapshot translucent materials sample (refraction).
    final opaqueColor = capture
        ? context.texturePool.acquire(
            TransientTextureDescriptor.color(
              width: width,
              height: height,
              format: _hdrFormat,
              debugName: 'opaque_scene_color',
            ),
          )
        : null;
    // The multisample color target. Tile-transient normally; when the pass
    // splits it must be stored and reloaded, so it becomes device-resident
    // (a cost paid only when a material requests the snapshot).
    gpu.Texture? msaaColor;
    if (_enableMsaa) {
      msaaColor = context.texturePool.acquire(
        TransientTextureDescriptor(
          width: width,
          height: height,
          format: _hdrFormat,
          sampleCount: 4,
          storageMode: capture
              ? gpu.StorageMode.devicePrivate
              : gpu.StorageMode.deviceTransient,
          enableShaderReadUsage: false,
          debugName: 'hdr_scene_color_msaa',
        ),
      );
    }

    final colorAttachment = gpu.ColorAttachment(
      texture: capture ? (msaaColor ?? opaqueColor!) : hdrColor,
    );
    if (_enableMsaa) {
      colorAttachment.texture = msaaColor!;
      if (capture) {
        // Resolve the opaque phase into the snapshot while keeping the
        // multisample contents for the translucent pass to continue on.
        colorAttachment.resolveTexture = opaqueColor;
        colorAttachment.storeAction =
            gpu.StoreAction.storeAndMultisampleResolve;
      } else {
        colorAttachment.resolveTexture = hdrColor;
        colorAttachment.storeAction = gpu.StoreAction.multisampleResolve;
      }
    }
    final target = gpu.RenderTarget.singleColor(
      colorAttachment,
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthClearValue: 1.0,
        depthStoreAction: capture
            ? gpu.StoreAction.store
            : gpu.StoreAction.dontCare,
      ),
    );

    final shadowMap = context.blackboard.get<gpu.Texture>(
      kShadowMapBlackboardKey,
    );
    final ssaoMap = context.blackboard.get<gpu.Texture>(
      kSsaoTextureBlackboardKey,
    );
    // During an environment cross-fade, copy both environments' diffuse-SH
    // coefficients into one 9x2 composite so the lit shader reads them
    // through a single sampler. Without a cross-fade the primary's own 9x1
    // texture is bound directly (both shader row coordinates land on its
    // single row).
    final envB = _environmentMapB;
    gpu.Texture? shComposite;
    if (envB != null) {
      shComposite = context.texturePool.acquire(
        const TransientTextureDescriptor.color(
          width: 9,
          height: 2,
          format: gpu.PixelFormat.r16g16b16a16Float,
          debugName: 'sh_composite',
        ),
      );
      encodeShComposite(
        shComposite,
        _environmentMap.diffuseShTexture,
        envB.diffuseShTexture,
      );
    }
    final camera = _camera;
    final projection = camera.projection;
    final tanHalfFovY = projection is PerspectiveProjection
        ? math.tan(projection.fovRadiansY / 2.0)
        : 0.0;
    final tanHalfFovX = height > 0 ? tanHalfFovY * width / height : 0.0;
    final lighting = Lighting(
      environmentMap: _environmentMap,
      environmentMapB: _environmentMapB,
      diffuseShTexture: shComposite,
      environmentBlend: _environmentBlend,
      environmentIntensity: _environmentIntensity,
      environmentTransform: _environmentTransform,
      directionalLight: _directionalLight,
      directionalLightDirection: _directionalLightDirection,
      punctualParamsTexture: _punctualLighting.paramsTexture,
      punctualIndexTexture: _punctualLighting.indexTexture,
      punctualParamsCount: _punctualLighting.paramsCount,
      punctualIndexWidth: _punctualLighting.indexWidth,
      punctualIndexHeight: _punctualLighting.indexHeight,
      // Spot shadows share the atlas, so only sample them when it was produced.
      spotShadowCount: shadowMap == null
          ? 0
          : _punctualLighting.spotShadowCount,
      spotShadowDepthBias: _punctualLighting.spotShadowDepthBias,
      spotShadowNormalBias: _punctualLighting.spotShadowNormalBias,
      spotShadowSoftness: _punctualLighting.spotShadowSoftness,
      shadowMap: shadowMap,
      cascades: shadowMap == null ? const [] : _cascades,
      ssaoMap: ssaoMap,
      specularOcclusionMode: ssaoMap == null ? 0.0 : _specularOcclusionMode,
      viewportSize: _dimensions,
      fog: _fog,
      sceneDepthLinear: _bindSceneDepth
          ? context.blackboard.get<gpu.Texture>(kLinearDepthBlackboardKey)
          : null,
      cameraPosition: camera.position,
      cameraForward: camera.forward.normalized(),
      tanHalfFovX: tanHalfFovX,
      tanHalfFovY: tanHalfFovY,
      time: _time,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(target);

    // Draw the background first, behind the geometry. It writes no depth, so
    // the opaque phase (depth-tested against the cleared far value) draws
    // over it; the encoder constructor below re-asserts the opaque state.
    final skybox = _skybox;
    if (skybox != null) {
      encodeSkybox(
        renderPass,
        context.transientsBuffer,
        skybox,
        _environmentMap,
        _environmentIntensity,
        _environmentTransform,
        _camera,
        _dimensions,
        environmentMapB: _environmentMapB,
        environmentBlend: _environmentBlend,
      );
    }

    final encoder = SceneEncoder(
      renderPass,
      context.transientsBuffer,
      _camera,
      _dimensions,
      lighting,
      _layerMask,
    );
    _renderScene.cull(encoder.frustum, encoder.submit);

    if (!capture) {
      encoder.flush();
      rendererSubmissions.submit(commandBuffer);
      context.blackboard.set(kSceneColorBlackboardKey, hdrColor);
      return;
    }

    // Split path: finish the opaque phase (pass 1 resolves/stores the
    // snapshot), then draw translucents in a second pass that can sample it.
    encoder.flushOpaque();
    rendererSubmissions.submit(commandBuffer);
    lighting.opaqueSceneColor = opaqueColor;

    final translucentAttachment = gpu.ColorAttachment(
      texture: _enableMsaa ? msaaColor! : hdrColor,
      loadAction: _enableMsaa ? gpu.LoadAction.load : gpu.LoadAction.dontCare,
    );
    if (_enableMsaa) {
      translucentAttachment.resolveTexture = hdrColor;
      translucentAttachment.storeAction = gpu.StoreAction.multisampleResolve;
    }
    final translucentTarget = gpu.RenderTarget.singleColor(
      translucentAttachment,
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthLoadAction: gpu.LoadAction.load,
        depthClearValue: 1.0,
      ),
    );
    final translucentCommands = gpu.gpuContext.createCommandBuffer();
    final translucentPass = translucentCommands.createRenderPass(
      translucentTarget,
    );
    if (!_enableMsaa) {
      // Without a multisample attachment to carry across the split, replay
      // the snapshot into the final HDR target before drawing over it.
      _encodeCopy(translucentPass, opaqueColor!);
    }
    encoder.flushTranslucent(translucentPass: translucentPass);
    rendererSubmissions.submit(translucentCommands);

    context.blackboard.set(kOpaqueSceneColorBlackboardKey, opaqueColor!);
    context.blackboard.set(kSceneColorBlackboardKey, hdrColor);
  }

  static final gpu.Shader _copyVertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _copyFragmentShader =
      baseShaderLibrary['CopyFragment']!;

  // Two triangles of NDC positions covering the screen (6 vec2s).
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

  /// Replays [source] over the whole target: the first draw of the split's
  /// translucent pass on the non-MSAA path. Depth writes/tests off so it
  /// composites under nothing and disturbs no depth.
  void _encodeCopy(gpu.RenderPass pass, gpu.Texture source) {
    final pipeline = gpu.gpuContext.createRenderPipeline(
      _copyVertexShader,
      _copyFragmentShader,
    );
    pass.bindPipeline(pipeline);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);
    bindVertexBufferCompat(pass, _quadView, 6);
    pass.bindTexture(
      _copyFragmentShader.getUniformSlot('source_texture'),
      source,
    );
    drawCompat(pass, 6);
  }
}
