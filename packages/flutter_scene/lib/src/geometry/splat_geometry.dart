import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/scene_encoder.dart';
import 'package:flutter_scene/src/splats/gaussian_splats.dart';
import 'package:flutter_scene/src/splats/splat_data.dart';
import 'package:flutter_scene/src/splats/splat_sort_service.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// How a crop box filters the splats of a `SplatComponent`.
/// {@category Gaussian splatting}
enum SplatCropMode {
  /// No crop; every splat draws.
  none,

  /// Only splats inside the box draw.
  include,

  /// Splats inside the box are dropped.
  exclude,
}

/// Draws a [GaussianSplats] set as one instanced batch of screen-space
/// Gaussian footprints.
///
/// Each instance is one splat. The vertex shader fetches the splat's
/// parameters from the set's data textures and expands a quad over its
/// projected footprint. Instances draw presorted back to front by a
/// background sort that reruns when the view direction drifts, so a fast
/// orbit can lag the true order by a few frames.
///
/// Pair with a `SplatMaterial` and attach through a `SplatComponent`.
/// {@category Geometry}
class SplatGeometry extends Geometry {
  /// Creates geometry for [splats].
  SplatGeometry(this.splats) {
    setVertexShaderName('SplatsVertex');
    final bounds = splats.bounds;
    if (bounds != null) {
      final center = (bounds.min + bounds.max) * 0.5;
      final radius = (bounds.max - bounds.min).length * 0.5;
      setLocalBounds(bounds, vm.Sphere.centerRadius(center, radius));
    }
  }

  /// The splat set this geometry draws.
  final GaussianSplats splats;

  /// Global opacity multiplier in [0, 1].
  double opacity = 1.0;

  /// Multiplier on every splat's footprint (standard deviation), 1 is the
  /// captured size.
  double splatScale = 1.0;

  /// Linear RGBA tint multiplied into every splat.
  vm.Vector4 tint = vm.Vector4(1.0, 1.0, 1.0, 1.0);

  /// Whether the low-pass kernel compensates opacity so distant splats dim
  /// instead of shimmering (the anti-aliased rasterization convention).
  bool antialiased = true;

  int _shDegree = 2;

  vm.Matrix4? _cropInverse;
  SplatCropMode _cropMode = SplatCropMode.none;

  /// The active crop box's placement in the splat set's local space (the
  /// box is the unit cube, corners at +/-1), or null when no crop is set.
  vm.Matrix4? get cropBox => _cropBox;
  vm.Matrix4? _cropBox;

  /// How the crop box filters splats.
  SplatCropMode get cropMode => _cropMode;

  /// Sets or clears the crop box.
  ///
  /// [box] places a unit cube (corners at +/-1) in the set's local space;
  /// [mode] keeps only the splats inside it ([SplatCropMode.include]) or
  /// drops them ([SplatCropMode.exclude]). Pass null (or
  /// [SplatCropMode.none]) to clear.
  void setCropBox(
    vm.Matrix4? box, {
    SplatCropMode mode = SplatCropMode.include,
  }) {
    if (box == null || mode == SplatCropMode.none) {
      _cropBox = null;
      _cropInverse = null;
      _cropMode = SplatCropMode.none;
      return;
    }
    _cropBox = box.clone();
    _cropInverse = vm.Matrix4.inverted(box);
    _cropMode = mode;
  }

  /// The spherical-harmonic degree evaluated per splat, clamped to what the
  /// set carries. Lowering it cheapens the vertex stage.
  int get shDegree => math.min(_shDegree, splats.data.shDegree);
  set shDegree(int value) {
    _shDegree = value.clamp(0, 2);
  }

  // Re-sort when the local-space view direction rotates by more than about
  // one degree (dot < cos(1.1 degrees)).
  static const double _kResortDotThreshold = 0.99982;

  // A ring of sorted-order instance buffers, so a completing sort never
  // overwrites one a recent frame's command buffer may still read. Slots
  // fill lazily; _activeSlot is the one bind() uses this frame.
  // TODO(splats): reuse slots with completion tracking (the transient
  // arena's mechanism) instead of relying on sort cadence spacing.
  static const int _kIndexRingSize = 3;
  final List<gpu.DeviceBuffer?> _indexRing = List<gpu.DeviceBuffer?>.filled(
    _kIndexRingSize,
    null,
  );
  int _activeSlot = 0;
  int _sortGeneration = 0;
  bool _sortInFlight = false;
  vm.Vector3? _lastSortDir;
  vm.Vector3? _pendingSortDir;

  SplatSortService? _sorter;

  /// Shuts down the background sorter (called when the owning component
  /// unmounts). A later draw lazily respawns it.
  void disposeSorter() {
    _sorter?.dispose();
    _sorter = null;
    _sortInFlight = false;
    _pendingSortDir = null;
    // Force a fresh sort on remount.
    _lastSortDir = null;
  }

  gpu.BufferView? _quadVertices;
  gpu.BufferView? _quadIndices;

  static const int _kQuadIndexCount = 6;

  final gpu.SamplerOptions _dataSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    mipFilter: gpu.MipFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  @override
  VertexLayoutDescriptor? get instancedVertexLayout => _kSplatLayout;

  // The splat index arrives through the slot-1 instance buffer; the model
  // transform rides the FrameInfo uniform.
  @override
  bool get bindsModelTransformInstance => false;

  // A screen-space footprint has no meaningful winding.
  @override
  bool get isDoubleSided => true;

  void _ensureGpuResources() {
    if (_quadVertices != null) return;

    // The unit quad, corners in [-1, 1] (two triangles, shared by every
    // draw of this geometry).
    final verts = Float32List.fromList(<double>[-1, -1, 1, -1, -1, 1, 1, 1]);
    final indices = Uint16List.fromList(<int>[0, 1, 2, 2, 1, 3]);
    final vBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(verts),
    );
    final iBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(indices),
    );
    _quadVertices = gpu.BufferView(
      vBuffer,
      offsetInBytes: 0,
      lengthInBytes: verts.lengthInBytes,
    );
    _quadIndices = gpu.BufferView(
      iBuffer,
      offsetInBytes: 0,
      lengthInBytes: indices.lengthInBytes,
    );
    setVertices(_quadVertices!, 4);
    setIndices(_quadIndices!, gpu.IndexType.int16);

    // Slot 0 starts as identity order so the set renders (approximately)
    // before the first sort lands.
    final identity = Float32List(splats.count);
    for (var i = 0; i < identity.length; i++) {
      identity[i] = i.toDouble();
    }
    _indexRing[0] = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(identity),
    );
    _activeSlot = 0;
  }

  // Kicks a background sort along [dirLocal] (the local-space direction of
  // increasing view depth), coalescing to the latest request while one is
  // in flight. The sorter worker holds its own copy of the positions, so a
  // request ships twelve bytes out and the order transfers back.
  void _requestSort(vm.Vector3 dirLocal) {
    if (_sortInFlight) {
      _pendingSortDir = dirLocal;
      return;
    }
    _sortInFlight = true;
    _lastSortDir = dirLocal;
    final generation = ++_sortGeneration;
    final sorter = _sorter ??= SplatSortService(
      splats.data.positions,
      splats.count,
    );
    sorter.sort(dirLocal.x, dirLocal.y, dirLocal.z).then((order) {
      _sortInFlight = false;
      if (order == null) return; // Disposed mid-sort.
      if (generation != _sortGeneration) return;
      final slot = (_activeSlot + 1) % _kIndexRingSize;
      final bytes = ByteData.sublistView(order);
      final buffer =
          _indexRing[slot] ??
          gpu.gpuContext.createDeviceBuffer(
            gpu.StorageMode.hostVisible,
            splats.count * 4,
          );
      buffer.overwrite(bytes);
      _indexRing[slot] = buffer;
      _activeSlot = slot;
      final pending = _pendingSortDir;
      _pendingSortDir = null;
      if (pending != null) _requestSort(pending);
    });
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    // Splats use the engine's splat vertex shader; custom material vertex
    // variants do not apply, so this override is accepted and ignored.
    gpu.Shader? shaderOverride,
  }) {
    if (splats.count == 0) return;
    _ensureGpuResources();

    final mvp = cameraTransform * modelTransform;

    // The MVP's w row measures view depth per unit of local position, so its
    // xyz is the local-space sort direction. Ordering along a direction is
    // unaffected by camera translation, so only rotation triggers a re-sort.
    final storage = mvp.storage;
    final sortDir = vm.Vector3(storage[3], storage[7], storage[11]);
    if (sortDir.length2 > 1e-12) {
      sortDir.normalize();
      final last = _lastSortDir;
      if (last == null || last.dot(sortDir) < _kResortDotThreshold) {
        _requestSort(sortDir);
      }
    }

    // Slot 0 is the quad, slot 1 the sorted splat indices (instance rate).
    bindGeometryBuffers(pass);
    final indexBuffer = _indexRing[_activeSlot]!;
    pass.bindVertexBuffer(
      gpu.BufferView(
        indexBuffer,
        offsetInBytes: 0,
        lengthInBytes: splats.count * 4,
      ),
      slot: 1,
    );

    pass.bindTexture(
      vertexShader.getUniformSlot('splat_params_texture'),
      splats.paramsTexture,
      sampler: _dataSampler,
    );
    // The SH slot must always be bound; a set with no rest coefficients
    // binds the params texture as a placeholder (degree 0 never samples it).
    pass.bindTexture(
      vertexShader.getUniformSlot('splat_sh_texture'),
      splats.shTexture ?? splats.paramsTexture,
      sampler: _dataSampler,
    );

    final viewport = currentSceneEncoderViewport;
    final frameInfo = Float32List(72);
    frameInfo.setRange(0, 16, mvp.storage);
    frameInfo.setRange(16, 32, modelTransform.storage);
    final cropInverse = _cropInverse;
    if (cropInverse != null) {
      frameInfo.setRange(32, 48, cropInverse.storage);
    }
    frameInfo[48] = cameraPosition.x;
    frameInfo[49] = cameraPosition.y;
    frameInfo[50] = cameraPosition.z;
    frameInfo[51] = splats.colorSpace == SplatColorSpace.linear ? 1.0 : 0.0;
    frameInfo[52] = splats.paramsWidth.toDouble();
    frameInfo[53] = splats.paramsHeight.toDouble();
    // [54], [55] reserved.
    frameInfo[56] = splats.shWidth.toDouble();
    frameInfo[57] = splats.shHeight.toDouble();
    frameInfo[58] = splats.shStride.toDouble();
    frameInfo[59] = shDegree.toDouble();
    frameInfo[60] = viewport.width;
    frameInfo[61] = viewport.height;
    frameInfo[62] = antialiased ? 1.0 : 0.0;
    frameInfo[63] = splatScale;
    frameInfo[64] = opacity;
    frameInfo[65] = switch (_cropMode) {
      SplatCropMode.none => 0.0,
      SplatCropMode.include => 1.0,
      SplatCropMode.exclude => 2.0,
    };
    // [66], [67] reserved.
    frameInfo[68] = tint.x;
    frameInfo[69] = tint.y;
    frameInfo[70] = tint.z;
    frameInfo[71] = tint.w;
    pass.bindUniform(
      vertexShader.getUniformSlot('FrameInfo'),
      transientsBuffer.emplace(ByteData.sublistView(frameInfo)),
    );
  }

  @override
  void draw(gpu.RenderPass pass, {int instanceCount = 1}) {
    if (splats.count == 0) return;
    drawIndexedCompat(pass, _kQuadIndexCount, instanceCount: splats.count);
  }
}

/// The splat pipeline layout, slot 0 the per-vertex unit quad and slot 1 the
/// per-instance splat index (a float, since the broadest GLES tier has no
/// integer vertex attributes).
final VertexLayoutDescriptor _kSplatLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: 8,
      attributes: [
        VertexAttributeDescriptor(
          name: 'corner',
          format: gpu.VertexFormat.float32x2,
        ),
      ],
    ),
    VertexBufferDescriptor(
      strideInBytes: 4,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        VertexAttributeDescriptor(
          name: 'splat_index',
          format: gpu.VertexFormat.float32,
        ),
      ],
    ),
  ],
);
