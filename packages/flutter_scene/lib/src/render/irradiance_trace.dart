import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/global_illumination.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/engine_compute_shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/gi_scene.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';
import 'package:flutter_scene/src/render/irradiance_pass.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';

/// How many times each frame's trace is dispatched, so a test can read its
/// GPU cost off the difference in completion times.
@visibleForTesting
int debugTraceRepeats = 1;

/// How many times each frame's gathers are dispatched, as [debugTraceRepeats]
/// is for the trace.
@visibleForTesting
int debugGatherRepeats = 1;

/// Called with the wall time from each trace submission to its completion.
@visibleForTesting
void Function(Duration elapsed)? debugOnTraceCompleted;

/// Rays each probe traces per frame.
const int kTracedRaysPerProbe = 64;

const int _workgroupSize = 64;

// Each frame rewrites its uploads, so one set per frame in flight.
const int _ringSize = 3;

// The roughness band a miss reads the sky at. A probe ray stands for about
// a 64th of the sphere, so a blurred band keeps the sky from aliasing.
const double _skyRoughness = 0.35;

/// The traced feed's scene, shaders, and buffers, owned by the scene beside
/// its [IrradianceFieldState].
class IrradianceTraceState {
  _Shaders? _shaders;
  bool _failed = false;

  final GiScene _scene = GiScene();

  IrradianceFieldLayout? _layout;
  gpu.DeviceBuffer? _rays;
  gpu.DeviceBuffer? _irradianceTexels;
  gpu.DeviceBuffer? _depthTexels;
  gpu.DeviceBuffer? _probeStates;
  gpu.DeviceBuffer? _stateTexels;
  bool _bounceReady = false;
  bool _resetStates = true;

  final _Ring _tlas = _Ring();
  final _Ring _instances = _Ring();
  final _Ring _materials = _Ring();
  final _Ring _lights = _Ring();
  final _Ring _tileInfo = _Ring();
  final _Ring _directions = _Ring();
  int _frame = 0;
  final math.Random _random = math.Random(1);

  /// Whether this frame can feed the field by tracing with [settings], which
  /// starts loading the compute shaders the first time it is asked.
  bool availableFor(GlobalIlluminationSettings settings) {
    if (_failed) return false;
    if (settings.feed != IrradianceFeed.rayTraced) return false;
    return _readyShaders() != null;
  }

  /// Drops the accumulated bounce and probe offsets, for when the field
  /// resets.
  void invalidate() {
    _bounceReady = false;
    _resetStates = true;
  }

  _Shaders? _readyShaders() {
    final shaders = _shaders;
    if (shaders != null) return shaders;
    final library = EngineComputeShaders.request();
    if (library == null) return null;
    try {
      return _shaders = _Shaders(library);
    } catch (error, stack) {
      _fail(error, stack, 'while preparing the traced irradiance shaders');
      return null;
    }
  }

  void _fail(Object error, StackTrace stack, String context) {
    _failed = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'flutter_scene',
        context: ErrorDescription(
          '$context. The irradiance field falls back to its screen-space feed',
        ),
      ),
    );
  }

  void _allocate(IrradianceFieldLayout layout) {
    if (_layout == layout && _rays != null) return;
    _layout = layout;
    _bounceReady = false;
    _resetStates = true;
    gpu.DeviceBuffer zeroed(int bytes) =>
        gpu.gpuContext.createDeviceBufferWithCopy(ByteData(bytes));
    _rays = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      layout.probeCount * kTracedRaysPerProbe * 16,
    );
    // Rows a budget leaves unscheduled are copied too, so start them zeroed.
    _irradianceTexels = zeroed(
      layout.injectionIrradianceWidth * layout.injectionIrradianceHeight * 8,
    );
    _depthTexels = zeroed(
      layout.injectionDepthWidth * layout.injectionDepthHeight * 8,
    );
    _probeStates = zeroed(layout.probeCount * 32);
    _stateTexels = zeroed(layout.tilesPerRow * layout.tileRows * 8);
  }
}

final class _Shaders {
  _Shaders(gpu.ShaderLibrary library)
    : trace = _entry(library, 'GiTrace'),
      traceCube = _entry(library, 'GiTraceCube'),
      gather = _entry(library, 'GiGather'),
      probeState = _entry(library, 'GiProbeState'),
      skinTriangles = _entry(library, 'GiSkinTriangles'),
      refit = _entry(library, 'GiRefit'),
      materialTile = _entry(library, 'GiMaterialTileFragment') {
    tracePipeline = gpu.createComputePipeline(trace);
    traceCubePipeline = gpu.createComputePipeline(traceCube);
    gatherPipeline = gpu.createComputePipeline(gather);
    probeStatePipeline = gpu.createComputePipeline(probeState);
    skinTrianglesPipeline = gpu.createComputePipeline(skinTriangles);
    refitPipeline = gpu.createComputePipeline(refit);
  }

  static gpu.Shader _entry(gpu.ShaderLibrary library, String name) =>
      library[name] ??
      (throw StateError('The compute bundle has no $name entry.'));

  final gpu.Shader trace;
  final gpu.Shader traceCube;
  final gpu.Shader gather;
  final gpu.Shader probeState;
  final gpu.Shader skinTriangles;
  final gpu.Shader refit;
  final gpu.Shader materialTile;
  late final gpu.GpuComputePipeline tracePipeline;
  late final gpu.GpuComputePipeline traceCubePipeline;
  late final gpu.GpuComputePipeline gatherPipeline;
  late final gpu.GpuComputePipeline probeStatePipeline;
  late final gpu.GpuComputePipeline skinTrianglesPipeline;
  late final gpu.GpuComputePipeline refitPipeline;

  gpu.GpuStorageBufferSlot slot(gpu.Shader shader, String name) =>
      gpu.getStorageBufferSlot(shader, name);
}

// A host-visible upload per frame in flight, grown as needed.
final class _Ring {
  final List<gpu.DeviceBuffer?> _buffers = List.filled(_ringSize, null);

  gpu.BufferView upload(int frame, TypedData data) {
    final slot = frame % _ringSize;
    var buffer = _buffers[slot];
    if (buffer == null || buffer.sizeInBytes < data.lengthInBytes) {
      buffer = _buffers[slot] = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        math.max(256, data.lengthInBytes * 2),
      );
    }
    buffer.overwrite(ByteData.sublistView(data));
    return gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: data.lengthInBytes,
    );
  }
}

final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);
final gpu.SamplerOptions _mipLinearClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  mipFilter: gpu.MipFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);
final gpu.SamplerOptions _equirect = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  mipFilter: gpu.MipFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.repeat,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);
final gpu.SamplerOptions _materialSource = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  mipFilter: gpu.MipFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.repeat,
  heightAddressMode: gpu.SamplerAddressMode.repeat,
);

final gpu.DeviceBuffer _fullscreenBuffer = gpu.gpuContext
    .createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );

/// Feeds the irradiance field by tracing: each scheduled probe shoots
/// [kTracedRaysPerProbe] rays against the scene in a compute pass, a probe
/// pass relocates and classifies the probes from them, a gather turns them
/// into the same weighted sums the screen-space scatter produces, and copies
/// land those in the field's accumulators and its probe state rows, so the
/// blend, filter, and receiver run unchanged.
class IrradianceTracePass extends RenderGraphPass {
  IrradianceTracePass({
    required this.field,
    required this.trace,
    required this.settings,
    required this.renderScene,
    required this.environment,
    required this.environmentTransform,
    required this.environmentIntensity,
  });

  final IrradianceFieldState field;
  final IrradianceTraceState trace;
  final GlobalIlluminationSettings settings;
  final RenderScene renderScene;
  final EnvironmentMap environment;
  final Matrix3 environmentTransform;
  final double environmentIntensity;

  @override
  String get name => 'IrradianceTracePass';

  @override
  void execute(RenderGraphContext context) {
    final layout = field.layout;
    final placement = field.placement;
    final irradianceTarget = field.irradianceAccumulator;
    final depthTarget = field.depthAccumulator;
    final atlas = field.sampledAtlas;
    final shaders = trace._shaders;
    if (layout == null ||
        placement == null ||
        irradianceTarget == null ||
        depthTarget == null ||
        atlas == null ||
        shaders == null) {
      return;
    }
    try {
      _encode(
        context,
        shaders,
        layout,
        placement,
        irradianceTarget,
        depthTarget,
        atlas,
      );
    } catch (error, stack) {
      field.traceOwnsProbeState = false;
      trace._fail(error, stack, 'while tracing the irradiance field');
    }
  }

  void _encode(
    RenderGraphContext context,
    _Shaders shaders,
    IrradianceFieldLayout layout,
    IrradianceGridPlacement placement,
    gpu.Texture irradianceTarget,
    gpu.Texture depthTarget,
    gpu.Texture atlas,
  ) {
    trace._allocate(layout);
    if (field.resetPending) trace.invalidate();
    final frame = ++trace._frame;
    final scene = trace._scene.prepare(
      renderScene,
      emissiveBoost: settings.emissiveGiBoost,
    );
    _renderMaterialAtlas(shaders, frame);

    final (rowStart, rowEnd) = field.peekScheduleRows(field.probeUpdateBudget);
    final probeCount = layout.probeCount;
    final firstProbe = math.min(probeCount, rowStart * layout.tilesPerRow);
    final scheduledProbes =
        math.min(probeCount, rowEnd * layout.tilesPerRow) - firstProbe;

    final rotation = Matrix4.identity()
      ..setRotation(Quaternion.random(trace._random).asRotationMatrix());
    final directions = trace._directions.upload(
      frame,
      _rayDirections(rotation),
    );
    final sun = renderScene.primaryDirectionalLight;
    final spacing = placement.spacing;
    final anchor = placement.anchor;
    final counts = layout.resolution;
    final (lights, lightCount) = GiScene.packLights(renderScene);
    final atlasTexture =
        trace._scene.atlas.texture ?? Material.getWhitePlaceholderTexture();

    final info = Float32List(64);
    info.setAll(0, rotation.storage);
    final environmentMatrix = Matrix4.identity()
      ..setRotation(environmentTransform);
    info.setAll(16, environmentMatrix.storage);
    info
      ..[32] = spacing.x
      ..[33] = spacing.y
      ..[34] = spacing.z
      ..[35] = placement.maxProbeDistance
      ..[36] = anchor.x
      ..[37] = anchor.y
      ..[38] = anchor.z
      ..[39] = kTracedRaysPerProbe.toDouble()
      ..[40] = counts.x
      ..[41] = counts.y
      ..[42] = counts.z
      ..[43] = layout.tilesPerRow.toDouble();
    if (sun != null) {
      final towardSun = -sun.worldDirection.normalized();
      final light = sun.light;
      info
        ..[44] = towardSun.x
        ..[45] = towardSun.y
        ..[46] = towardSun.z
        ..[47] = 1.0
        ..[48] = light.color.x * light.intensity
        ..[49] = light.color.y * light.intensity
        ..[50] = light.color.z * light.intensity;
    }
    info
      ..[51] = settings.fireflyClamp
      ..[52] = environmentIntensity
      ..[53] = scene.tlasNodeCount.toDouble()
      ..[54] = trace._bounceReady ? 1.0 : 0.0
      ..[55] = scheduledProbes.toDouble()
      ..[56] = firstProbe.toDouble()
      ..[57] = lightCount.toDouble()
      ..[58] = scene.boundedCount.toDouble()
      ..[59] = scene.instanceCount.toDouble()
      ..[60] = 1.0 / atlasTexture.width
      ..[61] = 1.0 / atlasTexture.height
      ..[62] = GiMaterialAtlas.tileEdge.toDouble()
      ..[63] = _skyRoughness;

    // The receiver's inputs, as the lit shader gets them, at unit intensity.
    final fieldInfo = Float32List(20)
      ..[0] = spacing.x
      ..[1] = spacing.y
      ..[2] = spacing.z
      ..[3] = 1.0
      ..[4] = anchor.x
      ..[5] = anchor.y
      ..[6] = anchor.z
      ..[7] = settings.shadowBias
      ..[8] = counts.x
      ..[9] = counts.y
      ..[10] = counts.z
      ..[11] = layout.tilesPerRow.toDouble()
      ..[12] = layout.irradianceOriginY.toDouble()
      ..[13] = layout.depthOriginY.toDouble()
      ..[14] = 1.0 / layout.atlasWidth
      ..[15] = 1.0 / layout.atlasHeight
      ..[16] = settings.visibility.clamp(0.0, 1.0)
      ..[17] = settings.visibilityBias * placement.minCellEdge
      ..[18] = placement.maxProbeDistance
      ..[19] = IrradianceFieldBinding.boundaryFadeCells;

    gpu.BufferView whole(gpu.DeviceBuffer buffer) => gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
    );
    final rays = whole(trace._rays!);
    final probeStates = whole(trace._probeStates!);
    final stateTexels = whole(trace._stateTexels!);
    final irradianceTexels = whole(trace._irradianceTexels!);
    final depthTexels = whole(trace._depthTexels!);
    final blasNodes = whole(trace._scene.blasNodes!);
    final blasTriangles = whole(trace._scene.blasTriangles!);
    final transients = context.transientsBuffer;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = gpu.createComputePass(commandBuffer);

    // Skinned meshes: rebuild each one's triangles from this frame's skinned
    // vertices, then refit its tree a level at a time, deepest first.
    // TODO(gi-trace-dynamic): batch every skinned mesh's level into one
    // dispatch instead of one per mesh per level.
    for (final (vertices, region) in scene.skinned) {
      final skin = shaders.skinTriangles;
      pass
        ..clearBindings()
        ..bindPipeline(shaders.skinTrianglesPipeline)
        ..bindStorageBuffer(shaders.slot(skin, 'Vertices'), vertices)
        ..bindStorageBuffer(
          shaders.slot(skin, 'Corners'),
          whole(trace._scene.corners!),
        )
        ..bindStorageBuffer(shaders.slot(skin, 'Triangles'), blasTriangles)
        ..bindUniform(
          skin.cachedUniformSlot('SkinTriangleInfo'),
          transients.emplace(
            ByteData.sublistView(
              Float32List.fromList([
                region.triangleBase.toDouble(),
                region.triangleCount.toDouble(),
                region.cornerBase.toDouble(),
                0,
              ]),
            ),
          ),
        )
        ..dispatch(_groups(region.triangleCount));
      final refit = shaders.refit;
      pass
        ..clearBindings()
        ..bindPipeline(shaders.refitPipeline)
        ..bindStorageBuffer(shaders.slot(refit, 'Nodes'), blasNodes)
        ..bindStorageBuffer(shaders.slot(refit, 'Triangles'), blasTriangles)
        ..bindStorageBuffer(
          shaders.slot(refit, 'Order'),
          whole(trace._scene.refitOrder!),
        );
      final starts = region.levelStarts;
      for (var level = 0; level + 1 < starts.length; level++) {
        final count = starts[level + 1] - starts[level];
        if (count == 0) continue;
        pass
          ..bindUniform(
            refit.cachedUniformSlot('RefitInfo'),
            transients.emplace(
              ByteData.sublistView(
                Float32List.fromList([
                  region.nodeBase.toDouble(),
                  region.triangleBase.toDouble(),
                  (region.orderBase + starts[level]).toDouble(),
                  count.toDouble(),
                ]),
              ),
            ),
          )
          ..dispatch(_groups(count));
      }
    }

    // The trace.
    final cube = environment.usesCubeRadianceLayout;
    final traceShader = cube ? shaders.traceCube : shaders.trace;
    pass
      ..clearBindings()
      ..bindPipeline(cube ? shaders.traceCubePipeline : shaders.tracePipeline)
      ..bindStorageBuffer(shaders.slot(traceShader, 'BlasNodes'), blasNodes)
      ..bindStorageBuffer(
        shaders.slot(traceShader, 'BlasTriangles'),
        blasTriangles,
      )
      ..bindStorageBuffer(
        shaders.slot(traceShader, 'TlasNodes'),
        trace._tlas.upload(frame, scene.tlasNodes),
      )
      ..bindStorageBuffer(
        shaders.slot(traceShader, 'Instances'),
        trace._instances.upload(frame, scene.instances),
      )
      ..bindStorageBuffer(
        shaders.slot(traceShader, 'Materials'),
        trace._materials.upload(frame, scene.materials),
      )
      ..bindStorageBuffer(
        shaders.slot(traceShader, 'Lights'),
        trace._lights.upload(frame, lights),
      )
      ..bindStorageBuffer(shaders.slot(traceShader, 'ProbeStates'), probeStates)
      ..bindStorageBuffer(shaders.slot(traceShader, 'Rays'), rays)
      ..bindUniform(
        traceShader.cachedUniformSlot('TraceInfo'),
        transients.emplace(ByteData.sublistView(info)),
      )
      ..bindUniform(
        traceShader.cachedUniformSlot('FieldInfo'),
        transients.emplace(ByteData.sublistView(fieldInfo)),
      )
      ..bindTexture(
        traceShader.cachedUniformSlot('irradiance_field'),
        atlas,
        sampler: _linearClamp,
      )
      ..bindTexture(
        traceShader.cachedUniformSlot('material_atlas'),
        atlasTexture,
        sampler: _linearClamp,
      )
      ..bindTexture(
        traceShader.cachedUniformSlot('prefiltered_radiance'),
        environment.prefilteredRadiance,
        sampler: cube ? _mipLinearClamp : _equirect,
      );
    if (!cube) {
      pass.bindUniform(
        traceShader.cachedUniformSlot('RadianceLayoutInfo'),
        transients.emplace(
          ByteData.sublistView(
            Float32List(4)..[0] = environment.usesMipRadianceLayout ? 1.0 : 0.0,
          ),
        ),
      );
    }
    for (var i = 0; i < debugTraceRepeats; i++) {
      pass.dispatch(_groups(scheduledProbes * kTracedRaysPerProbe));
    }

    // Relocate and classify the probes from their rays.
    final stateInfo = Float32List(16)
      ..[0] = spacing.x
      ..[1] = spacing.y
      ..[2] = spacing.z
      ..[3] = placement.minCellEdge * 0.2
      ..[4] = anchor.x
      ..[5] = anchor.y
      ..[6] = anchor.z
      ..[7] = kTracedRaysPerProbe.toDouble()
      ..[8] = counts.x
      ..[9] = counts.y
      ..[10] = counts.z
      ..[12] = firstProbe.toDouble()
      ..[13] = scheduledProbes.toDouble()
      ..[14] = trace._resetStates ? 1.0 : 0.0;
    final state = shaders.probeState;
    pass
      ..clearBindings()
      ..bindPipeline(shaders.probeStatePipeline)
      ..bindStorageBuffer(shaders.slot(state, 'Rays'), rays)
      ..bindStorageBuffer(shaders.slot(state, 'ProbeStates'), probeStates)
      ..bindStorageBuffer(shaders.slot(state, 'StateTexels'), stateTexels)
      ..bindStorageBuffer(shaders.slot(state, 'Directions'), directions)
      ..bindUniform(
        state.cachedUniformSlot('StateInfo'),
        transients.emplace(ByteData.sublistView(stateInfo)),
      )
      ..dispatch(_groups(scheduledProbes));

    void gather(
      gpu.BufferView texels,
      int width,
      int height,
      int tile,
      int interior,
      bool depth,
    ) {
      final texelCount = width * height;
      final first = math.min(texelCount, rowStart * tile * width);
      final count = math.min(texelCount, rowEnd * tile * width) - first;
      final gatherInfo = Float32List(12)
        ..[0] = tile.toDouble()
        ..[1] = interior.toDouble()
        ..[2] = layout.tilesPerRow.toDouble()
        ..[3] = depth ? 1.0 : 0.0
        ..[4] = probeCount.toDouble()
        ..[5] = kTracedRaysPerProbe.toDouble()
        ..[6] = width.toDouble()
        ..[7] = texelCount.toDouble()
        ..[8] = placement.maxProbeDistance
        ..[9] = first.toDouble()
        ..[10] = count.toDouble();
      // The trace's bindings use the same binding numbers for other
      // resources, so they must not carry over.
      pass
        ..clearBindings()
        ..bindPipeline(shaders.gatherPipeline)
        ..bindStorageBuffer(shaders.slot(shaders.gather, 'Rays'), rays)
        ..bindStorageBuffer(shaders.slot(shaders.gather, 'Texels'), texels)
        ..bindStorageBuffer(
          shaders.slot(shaders.gather, 'Directions'),
          directions,
        )
        ..bindUniform(
          shaders.gather.cachedUniformSlot('GatherInfo'),
          transients.emplace(ByteData.sublistView(gatherInfo)),
        );
      for (var i = 0; i < debugGatherRepeats; i++) {
        pass.dispatch(_groups(count));
      }
    }

    gather(
      irradianceTexels,
      layout.injectionIrradianceWidth,
      layout.injectionIrradianceHeight,
      IrradianceFieldLayout.irradianceTile,
      kIrradianceInterior,
      false,
    );
    gather(
      depthTexels,
      layout.injectionDepthWidth,
      layout.injectionDepthHeight,
      IrradianceFieldLayout.depthTile,
      kDepthMomentInterior,
      true,
    );
    pass.end();
    commandBuffer
      ..copyBufferToTexture(
        irradianceTexels,
        gpu.TextureRegion(irradianceTarget),
      )
      ..copyBufferToTexture(depthTexels, gpu.TextureRegion(depthTarget))
      ..copyBufferToTexture(
        stateTexels,
        gpu.TextureRegion(
          atlas,
          y: IrradianceFieldLayout.stateOriginY,
          width: layout.tilesPerRow,
          height: layout.tileRows,
        ),
      );
    final onCompleted = debugOnTraceCompleted;
    final watch = onCompleted == null ? null : (Stopwatch()..start());
    rendererSubmissions.submit(
      commandBuffer,
      onCompleted: watch == null ? null : () => onCompleted!(watch.elapsed),
    );
    field.traceOwnsProbeState = true;
    trace._bounceReady = true;
    trace._resetStates = false;
  }

  // Renders the material atlas when the set of textures changed.
  void _renderMaterialAtlas(_Shaders shaders, int frame) {
    final atlas = trace._scene.atlas;
    final changed = atlas.takeChanged();
    if (changed == null) return;
    if (changed.isEmpty) {
      atlas.texture = null;
      return;
    }
    final height = atlas.heightFor(changed.length);
    var target = atlas.texture;
    if (target == null || target.height != height) {
      target = atlas.texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        atlas.width,
        height,
        format: gpu.PixelFormat.r16g16b16a16Float,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
    }
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          loadAction: gpu.LoadAction.clear,
          clearValue: Vector4(1, 1, 1, 1),
        ),
      ),
    );
    renderPass
      ..setColorBlendEnable(false)
      ..setCullMode(gpu.CullMode.none)
      ..setPrimitiveType(gpu.PrimitiveType.triangle);
    final vertex = baseShaderLibrary['FullscreenVertex']!;
    final view = gpu.BufferView(
      _fullscreenBuffer,
      offsetInBytes: 0,
      lengthInBytes: 6 * 2 * 4,
    );
    const edge = GiMaterialAtlas.tileEdge;
    // One uniform block per tile, uploaded together.
    final tileInfo = Float32List(changed.length * 64);
    for (var i = 0; i < changed.length; i++) {
      final source = changed[i];
      final size = math.max(source.width, source.height);
      tileInfo
        ..[i * 64] = ((i % GiMaterialAtlas.tilesPerRow) * edge).toDouble()
        ..[i * 64 + 1] = ((i ~/ GiMaterialAtlas.tilesPerRow) * edge).toDouble()
        ..[i * 64 + 2] = edge.toDouble()
        ..[i * 64 + 3] = math.max(0.0, math.log(size / edge) / math.ln2);
    }
    final infoView = trace._tileInfo.upload(frame, tileInfo);
    for (var i = 0; i < changed.length; i++) {
      renderPass
        ..clearBindings()
        ..bindPipeline(resolvePipeline(vertex, shaders.materialTile));
      bindVertexBufferCompat(renderPass, view, 6);
      renderPass
        ..bindTexture(
          shaders.materialTile.cachedUniformSlot('source'),
          changed[i],
          sampler: _materialSource,
        )
        ..bindUniform(
          shaders.materialTile.cachedUniformSlot('TileInfo'),
          gpu.BufferView(
            infoView.buffer,
            offsetInBytes: i * 256,
            lengthInBytes: 16,
          ),
        );
      drawCompat(renderPass, 6);
    }
    rendererSubmissions.submit(commandBuffer);
  }

  // The rays ProbeRayDirection (irradiance_rays.glsl) gives the trace, so
  // the gathers and the probe pass read them instead of recomputing them for
  // every texel.
  static Float32List _rayDirections(Matrix4 rotation) {
    const goldenAngle = 2.399963229728653;
    const n = kTracedRaysPerProbe;
    final out = Float32List(n * 4);
    final v = Vector3.zero();
    for (var i = 0; i < n; i++) {
      final cosTheta = 1.0 - (2.0 * i + 1.0) / n;
      final sinTheta = math.sqrt(math.max(0.0, 1.0 - cosTheta * cosTheta));
      final phi = goldenAngle * i;
      v.setValues(math.cos(phi) * sinTheta, math.sin(phi) * sinTheta, cosTheta);
      rotation.rotate3(v);
      out
        ..[i * 4] = v.x
        ..[i * 4 + 1] = v.y
        ..[i * 4 + 2] = v.z;
    }
    return out;
  }

  static int _groups(int invocations) =>
      math.max(1, (invocations + _workgroupSize - 1) ~/ _workgroupSize);
}
