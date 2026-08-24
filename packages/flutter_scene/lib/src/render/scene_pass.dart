import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/fog.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_profile.dart';
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

const int _maxTransmissionFilterBands = 8;
bool _reportedSceneColorPassCap = false;

/// Number of half-resolution rough-transmission bands for a viewport.
int transmissionFilterBandCount(int width, int height) {
  var size = math.min(width, height);
  var bands = 0;
  while (size >= 2 && bands < _maxTransmissionFilterBands) {
    bands++;
    size >>= 1;
  }
  return bands;
}

/// Horizontal pixel offset of a rough-transmission atlas band.
int transmissionFilterBandOffset(int width, int level) {
  assert(level >= 1);
  final divisor = 1 << (level - 1);
  return width - (width + divisor - 1) ~/ divisor;
}

/// Draws the scene's render items (opaque, then depth-sorted
/// translucent) into a floating-point HDR color target, publishing it on
/// the render-graph blackboard for the resolve pass to read. If a
/// [ShadowPass] ran earlier this frame its shadow map is picked up from
/// the blackboard and threaded into the per-draw [Lighting].
class ScenePass extends RenderGraphPass {
  static final RenderProfileAccumulator _profile = RenderProfileAccumulator();

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
    double ssaoDirectLightAffect = 0.0,
    double ssaoMultiBounce = 0.0,
    bool ssaoBentNormals = false,
    bool ssaoContactShadows = false,
    bool ssaoIndirectLight = false,
    IrradianceFieldBinding? irradianceField,
    int layerMask = kRenderLayerAll,
    Fog? fog,
    bool captureOpaqueColor = false,
    bool bindSceneDepth = false,
    double time = 0.0,
    List<Plane> cullingPlanes = const [],
    bool includeOffscreen = false,
    bool suppressPlanarReflections = false,
    Matrix4? cameraTransform,
  }) : _captureOpaqueColor = captureOpaqueColor,
       _suppressPlanarReflections = suppressPlanarReflections,
       _bindSceneDepth = bindSceneDepth,
       _time = time,
       _camera = camera,
       _cameraTransform = cameraTransform,
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
       _ssaoDirectLightAffect = ssaoDirectLightAffect,
       _ssaoMultiBounce = ssaoMultiBounce,
       _ssaoBentNormals = ssaoBentNormals,
       _ssaoContactShadows = ssaoContactShadows,
       _ssaoIndirectLight = ssaoIndirectLight,
       _irradianceField = irradianceField,
       _fog = fog,
       _cullingPlanes = cullingPlanes,
       _includeOffscreen = includeOffscreen;

  final Camera _camera;
  final Matrix4? _cameraTransform;
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
  final double _ssaoDirectLightAffect;
  final double _ssaoMultiBounce;
  final bool _ssaoBentNormals;
  final bool _ssaoContactShadows;
  final bool _ssaoIndirectLight;
  final IrradianceFieldBinding? _irradianceField;
  final Fog? _fog;

  // Material scene inputs (see Material.sceneInputs): whether to capture
  // accumulated scene color, whether to hand materials the prepass linear
  // depth, and the engine time for material animation.
  final bool _captureOpaqueColor;
  final bool _bindSceneDepth;
  final bool _suppressPlanarReflections;
  final double _time;
  final List<Plane> _cullingPlanes;
  final bool _includeOffscreen;

  static const gpu.PixelFormat _hdrFormat = gpu.PixelFormat.r16g16b16a16Float;

  @override
  String get name => 'ScenePass';

  /// Whether draws in this pass suppress planar reflection sampling (the
  /// pass is itself a planar capture, which must not recurse).
  @visibleForTesting
  bool get debugSuppressesPlanarReflections => _suppressPlanarReflections;

  /// The node-layer mask this pass draws.
  @visibleForTesting
  int get debugLayerMask => _layerMask;

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
    // Depth must survive from the opaque pass into the translucent pass, so it
    // cannot be tile-transient when scene color is captured.
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
    // Screen-reading translucent batches alternate between these targets so
    // each batch can sample the fully composed color behind it.
    final alternateColor = capture
        ? context.texturePool.acquire(
            TransientTextureDescriptor.color(
              width: width,
              height: height,
              format: _hdrFormat,
              debugName: 'alternate_scene_color',
            ),
          )
        : null;
    // Split passes seed this attachment from resolved scene color instead of
    // relying on multisample contents surviving between render passes.
    gpu.Texture? msaaColor;
    if (_enableMsaa) {
      msaaColor = context.texturePool.acquire(
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
    }

    final colorAttachment = gpu.ColorAttachment(texture: msaaColor ?? hdrColor);
    if (_enableMsaa) {
      colorAttachment.texture = msaaColor!;
      colorAttachment.resolveTexture = hdrColor;
      colorAttachment.storeAction = gpu.StoreAction.multisampleResolve;
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
    final cameraForward = camera.forward.normalized();
    final cameraRight = camera.up.cross(cameraForward)..normalize();
    final cameraUp = cameraForward.cross(cameraRight)..normalize();
    final projection = camera.projection;
    final tanHalfFovY = projection is PerspectiveProjection
        ? math.tan(projection.fovRadiansY / 2.0)
        : 0.0;
    final tanHalfFovX = height > 0 ? tanHalfFovY * width / height : 0.0;
    final lighting = Lighting(
      environmentMap: _environmentMap,
      environmentMapB: _environmentMapB,
      diffuseShTexture: shComposite,
      irradianceField: _irradianceField,
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
      ssaoDirectLightAffect: ssaoMap == null ? 0.0 : _ssaoDirectLightAffect,
      ssaoMultiBounce: ssaoMap == null ? 0.0 : _ssaoMultiBounce,
      ssaoBentNormals: ssaoMap != null && _ssaoBentNormals,
      ssaoContactShadows: ssaoMap != null && _ssaoContactShadows,
      ssaoIndirectLight: ssaoMap != null && _ssaoIndirectLight,
      viewportSize: _dimensions,
      fog: _fog,
      sceneDepthLinear: _bindSceneDepth
          ? context.blackboard.get<gpu.Texture>(kLinearDepthBlackboardKey)
          : null,
      cameraPosition: camera.position,
      cameraForward: cameraForward,
      cameraRight: cameraRight,
      cameraUp: cameraUp,
      tanHalfFovX: tanHalfFovX,
      tanHalfFovY: tanHalfFovY,
      time: _time,
      planarReflectionsSuppressed: _suppressPlanarReflections,
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
      _cullingPlanes,
      !_includeOffscreen,
      cameraTransform: _cameraTransform,
    );
    final cullWatch = profileRendering ? (Stopwatch()..start()) : null;
    if (_includeOffscreen) {
      for (final item in _renderScene.items) {
        encoder.submit(item);
      }
    } else {
      _renderScene.cull(
        encoder.frustum,
        encoder.submit,
        additionalPlanes: _cullingPlanes,
      );
    }
    cullWatch?.stop();

    if (!capture || !encoder.hasPendingSceneColorReaders) {
      final flushWatch = profileRendering ? (Stopwatch()..start()) : null;
      encoder.flush();
      flushWatch?.stop();
      if (profileRendering) {
        _recordProfile(
          cullWatch!.elapsedMicroseconds,
          flushWatch!.elapsedMicroseconds,
        );
      }
      rendererSubmissions.submit(commandBuffer);
      context.blackboard.set(kSceneColorBlackboardKey, hdrColor);
      return;
    }

    final flushWatch = profileRendering ? (Stopwatch()..start()) : null;
    // Finish opaque draws and the backmost ordinary translucent run in the
    // initial target. Later screen-reading batches alternate targets. Readers
    // with disjoint projected bounds share a capture, while overlapping
    // readers get the accumulated color produced by the preceding batch.
    encoder.flushOpaque();
    if (encoder.hasPendingTranslucent &&
        !encoder.nextTranslucentBatchReadsSceneColor) {
      encoder.flushNextTranslucentBatch();
    }
    rendererSubmissions.submit(commandBuffer);

    var currentColor = hdrColor;
    var nextColor = alternateColor!;
    gpu.Texture? transmissionAtlas;
    List<gpu.Texture>? transmissionMips;
    var captureBatch = 0;
    while (encoder.hasPendingTranslucent) {
      assert(encoder.nextTranslucentBatchReadsSceneColor);
      final shareFinalSnapshot =
          captureBatch == maxSceneColorCaptureBatches - 1 &&
          encoder.pendingSceneColorReaderCount > 1;
      if (shareFinalSnapshot && !_reportedSceneColorPassCap) {
        _reportedSceneColorPassCap = true;
        debugPrint(
          'Scene color readers exceeded $maxSceneColorCaptureBatches '
          'overlap-safe batches. Remaining layers share the final snapshot.',
        );
      }
      lighting.opaqueSceneColor = currentColor;
      lighting.filteredSceneColor = null;
      lighting.transmissionFilterBandCount = 0;
      final readsFilteredSceneColor = shareFinalSnapshot
          ? encoder.pendingTranslucentReadsFilteredSceneColor
          : encoder.nextSceneColorBatchReadsFilteredSceneColor;
      if (readsFilteredSceneColor) {
        final bands = transmissionFilterBandCount(width, height);
        if (bands > 0) {
          transmissionAtlas ??= context.texturePool.acquire(
            TransientTextureDescriptor.color(
              width: width,
              height: math.max(1, height >> 1),
              format: _hdrFormat,
              debugName: 'filtered_scene_color',
            ),
          );
          transmissionMips ??= <gpu.Texture>[
            for (var level = 1; level <= bands; level++)
              context.texturePool.acquire(
                TransientTextureDescriptor.color(
                  width: math.max(1, width >> level),
                  height: math.max(1, height >> level),
                  format: _hdrFormat,
                  debugName: 'transmission_filter_$level',
                ),
              ),
          ];
          _encodeTransmissionFilter(
            context,
            currentColor,
            transmissionAtlas,
            transmissionMips,
          );
          lighting.filteredSceneColor = transmissionAtlas;
          lighting.transmissionFilterBandCount = bands;
        }
      }

      final attachment = gpu.ColorAttachment(
        texture: _enableMsaa ? msaaColor! : nextColor,
      );
      if (_enableMsaa) {
        attachment.resolveTexture = nextColor;
        attachment.storeAction = gpu.StoreAction.multisampleResolve;
      }
      final translucentTarget = gpu.RenderTarget.singleColor(
        attachment,
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: depth,
          depthLoadAction: gpu.LoadAction.load,
          depthStoreAction: gpu.StoreAction.store,
          depthClearValue: 1.0,
        ),
      );
      final translucentCommands = gpu.gpuContext.createCommandBuffer();
      final translucentPass = translucentCommands.createRenderPass(
        translucentTarget,
      );
      _encodeCopy(translucentPass, currentColor);
      if (shareFinalSnapshot) {
        // TODO(transmission-batching): replace the shared tail with a bounded
        // per-pixel resolve that preserves every overlapping layer.
        encoder.flushTranslucent(translucentPass: translucentPass);
      } else {
        encoder.flushNextSceneColorBatch(translucentPass: translucentPass);
      }
      rendererSubmissions.submit(translucentCommands);

      final completedColor = nextColor;
      nextColor = currentColor;
      currentColor = completedColor;
      captureBatch++;
    }

    context.blackboard.set(kSceneColorBlackboardKey, currentColor);
    flushWatch?.stop();
    if (profileRendering) {
      _recordProfile(
        cullWatch?.elapsedMicroseconds ?? 0,
        flushWatch?.elapsedMicroseconds ?? 0,
      );
    }
  }

  static void _recordProfile(int cullMicros, int flushMicros) {
    _profile.add('cull', cullMicros, trackMax: true);
    _profile.add('flush', flushMicros, trackMax: true);
    final snapshot = _profile.endSample();
    if (snapshot == null) return;
    // ignore: avoid_print
    print(
      'FLUTTER_SCENE_PROFILE_DETAIL '
      'cull_mean_us=${snapshot.mean('cull')} '
      'cull_max_us=${snapshot.max('cull')} '
      'flush_mean_us=${snapshot.mean('flush')} '
      'flush_max_us=${snapshot.max('flush')}',
    );
  }

  static final gpu.Shader _copyVertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _copyFragmentShader =
      baseShaderLibrary['CopyFragment']!;
  static final gpu.Shader _transmissionFilterShader =
      baseShaderLibrary['BloomDownsampleFragment']!;

  static final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    mipFilter: gpu.MipFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

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

  /// Copies [source] over a whole color target.
  void _encodeCopy(gpu.RenderPass pass, gpu.Texture source) {
    final pipeline = resolvePipeline(_copyVertexShader, _copyFragmentShader);
    pass.bindPipeline(pipeline);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);
    pass.setColorBlendEnable(false);
    pass.setCullMode(gpu.CullMode.none);
    bindVertexBufferCompat(pass, _quadView, 6);
    pass.bindTexture(
      _copyFragmentShader.getUniformSlot('source_texture'),
      source,
    );
    drawCompat(pass, 6);
  }

  /// Builds a compact horizontal atlas of recursively filtered scene color.
  void _encodeTransmissionFilter(
    RenderGraphContext context,
    gpu.Texture source,
    gpu.Texture atlas,
    List<gpu.Texture> mips,
  ) {
    var previous = source;
    for (final mip in mips) {
      _encodeTransmissionDownsample(context, previous, mip);
      previous = mip;
    }

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: atlas)),
    );
    pass.bindPipeline(resolvePipeline(_copyVertexShader, _copyFragmentShader));
    pass.setColorBlendEnable(false);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);
    pass.setCullMode(gpu.CullMode.none);
    bindVertexBufferCompat(pass, _quadView, 6);

    for (var index = 0; index < mips.length; index++) {
      final level = index + 1;
      final mip = mips[index];
      pass.setViewport(
        gpu.Viewport(
          x: transmissionFilterBandOffset(source.width, level),
          y: 0,
          width: mip.width,
          height: mip.height,
        ),
      );
      pass.bindTexture(
        _copyFragmentShader.getUniformSlot('source_texture'),
        mip,
        sampler: _linearClamp,
      );
      drawCompat(pass, 6);
    }
    rendererSubmissions.submit(commandBuffer);
  }

  void _encodeTransmissionDownsample(
    RenderGraphContext context,
    gpu.Texture source,
    gpu.Texture target,
  ) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    pass.bindPipeline(
      resolvePipeline(_copyVertexShader, _transmissionFilterShader),
    );
    pass.setColorBlendEnable(false);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);
    pass.setCullMode(gpu.CullMode.none);
    bindVertexBufferCompat(pass, _quadView, 6);
    pass.bindTexture(
      _transmissionFilterShader.getUniformSlot('source'),
      source,
      sampler: _linearClamp,
    );
    final filterInfo = Float32List(4)
      ..[0] = 1.0 / source.width
      ..[1] = 1.0 / source.height;
    pass.bindUniform(
      _transmissionFilterShader.getUniformSlot('BloomFilterInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(filterInfo)),
    );
    drawCompat(pass, 6);
    rendererSubmissions.submit(commandBuffer);
  }
}
