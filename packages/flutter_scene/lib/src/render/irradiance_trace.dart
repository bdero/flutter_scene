import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/global_illumination.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/render/engine_compute_shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/gi_bvh.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';
import 'package:flutter_scene/src/render/irradiance_pass.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';
import 'package:vector_math/vector_math.dart';

/// Whether the irradiance field is fed by tracing probe rays against the
/// scene in a compute pass, where the device supports compute, instead of by
/// scattering the visible screen.
///
/// TODO(gi-trace): promote to a [GlobalIlluminationSettings] option once the
/// traced feed covers dynamic meshes, textured albedo, and punctual lights.
@visibleForTesting
bool tracedIrradianceEnabled = false;

/// Rays each probe traces per frame.
const int kTracedRaysPerProbe = 64;

const int _workgroupSize = 64;

// Each frame rewrites the sky buffer, so one per frame in flight.
const int _ringSize = 3;

/// The traced feed's scene and buffers, owned by the scene beside its
/// [IrradianceFieldState].
///
/// Static meshes are gathered into a BVH whenever the set of them, their
/// transforms, or their materials change.
///
/// TODO(gi-trace-dynamic): skinned and morphed meshes are left out. Add them
/// as a second level (instanced BLASes under a TLAS) refit each frame, which
/// compute skinning's world-space output can feed.
/// TODO(gi-trace-build): the build runs on the UI thread. Move it to an
/// isolate for large scenes.
class IrradianceTraceState {
  _Shaders? _shaders;
  bool _failed = false;

  int _sceneSignature = 0;
  int _nodeCount = 0;
  gpu.DeviceBuffer? _nodes;
  gpu.DeviceBuffer? _triangles;
  gpu.DeviceBuffer? _materials;

  IrradianceFieldLayout? _layout;
  gpu.DeviceBuffer? _rays;
  gpu.DeviceBuffer? _irradianceTexels;
  gpu.DeviceBuffer? _depthTexels;
  bool _bounceReady = false;

  final List<gpu.DeviceBuffer?> _sky = List.filled(_ringSize, null);
  int _frame = 0;
  final math.Random _random = math.Random(1);

  /// Whether this frame can feed the field by tracing, which starts loading
  /// the compute shaders the first time it is asked.
  bool get available {
    if (!tracedIrradianceEnabled || _failed) return false;
    return _readyShaders() != null;
  }

  /// Drops the accumulated bounce, for when the field resets.
  void invalidate() => _bounceReady = false;

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

  // Rebuilds the BVH when the static scene changed since the last frame.
  void _prepareScene(RenderScene scene) {
    final included = <RenderItem>[];
    var signature = 17;
    for (final item in scene.items) {
      if (!_traceable(item)) continue;
      included.add(item);
      signature = Object.hash(
        signature,
        identityHashCode(item.geometry),
        item.geometry.localBoundsVersion,
        Object.hashAll(item.worldTransform.storage),
        _materialKey(item.material),
      );
    }
    if (_nodes != null && signature == _sceneSignature) return;
    _sceneSignature = signature;

    final positions = <double>[];
    final triangleMaterials = <int>[];
    final materialData = <double>[];
    final materialIndex = <Object, int>{};
    for (final item in included) {
      final mesh = item.geometry.extractMeshData();
      final material = materialIndex.putIfAbsent(
        _materialKey(item.material),
        () {
          materialData.addAll(_materialEntry(item.material));
          return materialData.length ~/ 8 - 1;
        },
      );
      final transform = item.worldTransform;
      // A mirroring transform flips the winding, so swap two corners to keep
      // front faces counter-clockwise.
      final order = transform.determinant() < 0
          ? const [0, 2, 1]
          : const [0, 1, 2];
      final source = mesh.positions;
      final indices = mesh.indices;
      final cornerCount = indices?.length ?? mesh.vertexCount;
      final corner = Vector3.zero();
      for (var c = 0; c + 2 < cornerCount; c += 3) {
        for (var k = 0; k < 3; k++) {
          final v = indices == null ? c + order[k] : indices[c + order[k]];
          corner.setValues(source[v * 3], source[v * 3 + 1], source[v * 3 + 2]);
          transform.transform3(corner);
          positions.addAll([corner.x, corner.y, corner.z]);
        }
        triangleMaterials.add(material);
      }
    }
    final bvh = GiBvh.build(Float32List.fromList(positions), triangleMaterials);
    _nodeCount = bvh.nodeCount;
    gpu.DeviceBuffer upload(Float32List data, int minimumFloats) =>
        gpu.gpuContext.createDeviceBufferWithCopy(
          ByteData.sublistView(
            data.length >= minimumFloats ? data : Float32List(minimumFloats),
          ),
        );
    // A storage binding cannot be empty, so an empty scene binds one zeroed
    // element of each, which the walk never reads.
    _nodes = upload(bvh.nodes, GiBvh.nodeStride);
    _triangles = upload(bvh.triangles, GiBvh.triangleStride);
    _materials = upload(Float32List.fromList(materialData), 8);
  }

  static bool _traceable(RenderItem item) {
    final geometry = item.geometry;
    return item.visible &&
        item.primitiveVisible &&
        item.jointsTexture == null &&
        item.morphWeights == null &&
        geometry.isReadable &&
        geometry.primitiveType == gpu.PrimitiveType.triangle;
  }

  static Object _materialKey(Material material) => switch (material) {
    PhysicallyBasedMaterial m => Object.hash(
      Object.hashAll(m.baseColorFactor.storage),
      m.metallicFactor,
      Object.hashAll(m.emissiveFactor.storage),
      m.emissiveStrength,
      m.doubleSided,
    ),
    UnlitMaterial m => Object.hash(
      Object.hashAll(m.baseColorFactor.storage),
      m.doubleSided,
    ),
    _ => Object.hash(material.runtimeType, material.doubleSided),
  };

  // Diffuse albedo with 1 in w when double-sided, then emission.
  // TODO(gi-trace-albedo): average the base color and emissive textures, and
  // read other material kinds, instead of the factors and a gray default.
  static List<double> _materialEntry(Material material) {
    final sides = material.doubleSided ? 1.0 : 0.0;
    switch (material) {
      case PhysicallyBasedMaterial m:
        final diffuse = 1.0 - m.metallicFactor.clamp(0.0, 1.0);
        final base = m.baseColorFactor;
        final emissive = m.emissiveFactor;
        return [
          base.x * diffuse, base.y * diffuse, base.z * diffuse, sides, //
          emissive.x * m.emissiveStrength,
          emissive.y * m.emissiveStrength,
          emissive.z * m.emissiveStrength,
          0,
        ];
      case UnlitMaterial m:
        // An unlit surface shows its color whatever lights it, so to the
        // field it is an emitter.
        final base = m.baseColorFactor;
        return [0, 0, 0, sides, base.x, base.y, base.z, 0];
      default:
        return [0.5, 0.5, 0.5, sides, 0, 0, 0, 0];
    }
  }

  void _allocate(IrradianceFieldLayout layout) {
    if (_layout == layout && _rays != null) return;
    _layout = layout;
    _bounceReady = false;
    final rayBytes = layout.probeCount * kTracedRaysPerProbe * 16;
    _rays = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      rayBytes,
    );
    // Read back as the bounce before the first gather writes it, so zeroed.
    _irradianceTexels = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData(
        layout.injectionIrradianceWidth * layout.injectionIrradianceHeight * 8,
      ),
    );
    _depthTexels = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      layout.injectionDepthWidth * layout.injectionDepthHeight * 8,
    );
  }

  gpu.BufferView _skyView(EnvironmentMap environment) {
    final slot = _frame % _ringSize;
    final buffer = _sky[slot] ??= gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      9 * 16,
    );
    final coefficients = environment.diffuseSphericalHarmonics;
    final data = Float32List(9 * 4);
    // TODO(gi-trace-sky): an environment baked from a sky keeps its
    // coefficients on the GPU only, so its misses read black. Copy them from
    // the coefficient texture instead.
    for (var i = 0; i < 9 && i < coefficients.length; i++) {
      data[i * 4] = coefficients[i].x;
      data[i * 4 + 1] = coefficients[i].y;
      data[i * 4 + 2] = coefficients[i].z;
    }
    buffer.overwrite(ByteData.sublistView(data));
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 9 * 16);
  }
}

final class _Shaders {
  _Shaders(gpu.ShaderLibrary library)
    : trace =
          library['GiTrace'] ??
          (throw StateError('The compute bundle has no GiTrace entry.')),
      gather =
          library['GiGather'] ??
          (throw StateError('The compute bundle has no GiGather entry.')) {
    tracePipeline = gpu.createComputePipeline(trace);
    gatherPipeline = gpu.createComputePipeline(gather);
    nodes = gpu.getStorageBufferSlot(trace, 'Nodes');
    triangles = gpu.getStorageBufferSlot(trace, 'Triangles');
    materials = gpu.getStorageBufferSlot(trace, 'Materials');
    sky = gpu.getStorageBufferSlot(trace, 'Sky');
    previous = gpu.getStorageBufferSlot(trace, 'Previous');
    traceRays = gpu.getStorageBufferSlot(trace, 'Rays');
    gatherRays = gpu.getStorageBufferSlot(gather, 'Rays');
    texels = gpu.getStorageBufferSlot(gather, 'Texels');
  }

  final gpu.Shader trace;
  final gpu.Shader gather;
  late final gpu.GpuComputePipeline tracePipeline;
  late final gpu.GpuComputePipeline gatherPipeline;
  late final gpu.GpuStorageBufferSlot nodes;
  late final gpu.GpuStorageBufferSlot triangles;
  late final gpu.GpuStorageBufferSlot materials;
  late final gpu.GpuStorageBufferSlot sky;
  late final gpu.GpuStorageBufferSlot previous;
  late final gpu.GpuStorageBufferSlot traceRays;
  late final gpu.GpuStorageBufferSlot gatherRays;
  late final gpu.GpuStorageBufferSlot texels;
}

/// Feeds the irradiance field by tracing: each probe shoots
/// [kTracedRaysPerProbe] rays against the static scene in a compute pass, a
/// second pass gathers them into the same weighted sums the screen-space
/// scatter produces, and copies land them in the field's accumulators, so
/// the blend, filter, and receiver run unchanged.
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
    final shaders = trace._shaders;
    if (layout == null ||
        placement == null ||
        irradianceTarget == null ||
        depthTarget == null ||
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
      );
    } catch (error, stack) {
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
  ) {
    trace._prepareScene(renderScene);
    trace._allocate(layout);
    trace._frame++;

    final rotation = Matrix4.identity()
      ..setRotation(Quaternion.random(trace._random).asRotationMatrix());
    final probeCount = layout.probeCount;
    final rayCount = probeCount * kTracedRaysPerProbe;
    final sun = renderScene.primaryDirectionalLight;
    final spacing = placement.spacing;
    final anchor = placement.anchor;
    final counts = layout.resolution;

    final info = Float32List(56);
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
      ..[53] = trace._nodeCount.toDouble()
      ..[54] = trace._bounceReady ? 1.0 : 0.0
      ..[55] = probeCount.toDouble();

    final rays = gpu.BufferView(
      trace._rays!,
      offsetInBytes: 0,
      lengthInBytes: rayCount * 16,
    );
    final irradianceTexelCount =
        layout.injectionIrradianceWidth * layout.injectionIrradianceHeight;
    final depthTexelCount =
        layout.injectionDepthWidth * layout.injectionDepthHeight;
    final irradianceTexels = gpu.BufferView(
      trace._irradianceTexels!,
      offsetInBytes: 0,
      lengthInBytes: irradianceTexelCount * 8,
    );
    final depthTexels = gpu.BufferView(
      trace._depthTexels!,
      offsetInBytes: 0,
      lengthInBytes: depthTexelCount * 8,
    );
    gpu.BufferView whole(gpu.DeviceBuffer buffer) => gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = gpu.createComputePass(commandBuffer)
      ..bindPipeline(shaders.tracePipeline)
      ..bindStorageBuffer(shaders.nodes, whole(trace._nodes!))
      ..bindStorageBuffer(shaders.triangles, whole(trace._triangles!))
      ..bindStorageBuffer(shaders.materials, whole(trace._materials!))
      ..bindStorageBuffer(shaders.sky, trace._skyView(environment))
      ..bindStorageBuffer(shaders.previous, irradianceTexels)
      ..bindStorageBuffer(shaders.traceRays, rays)
      ..bindUniform(
        shaders.trace.cachedUniformSlot('TraceInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      )
      ..dispatch(_groups(rayCount));

    void gather(gpu.BufferView texels, int texelCount, int width, bool depth) {
      final tile = depth
          ? IrradianceFieldLayout.depthTile
          : IrradianceFieldLayout.irradianceTile;
      final interior = depth ? kDepthMomentInterior : kIrradianceInterior;
      final gatherInfo = Float32List(28)
        ..setAll(0, rotation.storage)
        ..[16] = tile.toDouble()
        ..[17] = interior.toDouble()
        ..[18] = layout.tilesPerRow.toDouble()
        ..[19] = depth ? 1.0 : 0.0
        ..[20] = probeCount.toDouble()
        ..[21] = kTracedRaysPerProbe.toDouble()
        ..[22] = width.toDouble()
        ..[23] = texelCount.toDouble()
        ..[24] = placement.maxProbeDistance;
      // The trace's bindings use the same binding numbers for other
      // resources, so they must not carry over.
      pass
        ..clearBindings()
        ..bindPipeline(shaders.gatherPipeline)
        ..bindStorageBuffer(shaders.gatherRays, rays)
        ..bindStorageBuffer(shaders.texels, texels)
        ..bindUniform(
          shaders.gather.cachedUniformSlot('GatherInfo'),
          context.transientsBuffer.emplace(ByteData.sublistView(gatherInfo)),
        )
        ..dispatch(_groups(texelCount));
    }

    gather(
      irradianceTexels,
      irradianceTexelCount,
      layout.injectionIrradianceWidth,
      false,
    );
    gather(depthTexels, depthTexelCount, layout.injectionDepthWidth, true);
    pass.end();
    commandBuffer
      ..copyBufferToTexture(
        irradianceTexels,
        gpu.TextureRegion(irradianceTarget),
      )
      ..copyBufferToTexture(depthTexels, gpu.TextureRegion(depthTarget));
    rendererSubmissions.submit(commandBuffer);
    trace._bounceReady = true;
  }

  static int _groups(int invocations) =>
      (invocations + _workgroupSize - 1) ~/ _workgroupSize;
}
