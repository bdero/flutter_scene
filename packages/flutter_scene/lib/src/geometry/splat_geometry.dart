import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/scene_encoder.dart';
import 'package:flutter_scene/src/splats/gaussian_splats.dart';
import 'package:flutter_scene/src/splats/splat_data.dart';
import 'package:flutter_scene/src/splats/splat_sorter.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Draws a [GaussianSplats] set as one instanced batch of screen-space
/// Gaussian footprints.
///
/// Each instance is one splat; the vertex shader fetches the splat's
/// parameters from the set's data textures and expands a quad over its
/// projected footprint. Instances draw in presorted back-to-front order; the
/// sort runs on a background isolate and is retriggered when the view
/// direction (in the set's local space) drifts past a small threshold, so a
/// fast orbit can lag the true order by a few frames.
///
/// Pair with a `SplatMaterial`; attach to the scene through a
/// `SplatComponent`.
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

  /// The spherical-harmonic degree evaluated per splat, clamped to what the
  /// set carries. Lowering it cheapens the vertex stage.
  int get shDegree => math.min(_shDegree, splats.data.shDegree);
  set shDegree(int value) {
    _shDegree = value.clamp(0, 2);
  }

  // Re-sort when the local-space view direction rotates by more than about
  // one degree (dot < cos(1.1 degrees)).
  static const double _kResortDotThreshold = 0.99982;

  // The sorted-order instance buffers. A ring so a completing sort never
  // overwrites the buffer a recent frame's command buffer may still read.
  // Slots fill lazily; _activeSlot is the one bind() uses this frame.
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
  // in flight.
  void _requestSort(vm.Vector3 dirLocal) {
    if (_sortInFlight) {
      _pendingSortDir = dirLocal;
      return;
    }
    _sortInFlight = true;
    _lastSortDir = dirLocal;
    final generation = ++_sortGeneration;
    // TODO(splats): a long-lived sorter isolate would avoid re-sending the
    // positions array on every sort (compute copies its arguments).
    compute(sortSplatsForIsolate, (
      positions: splats.data.positions,
      count: splats.count,
      dirX: dirLocal.x,
      dirY: dirLocal.y,
      dirZ: dirLocal.z,
    ), debugLabel: 'sortSplats').then((order) {
      _sortInFlight = false;
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

    // Slot 0: the quad. Slot 1: the sorted splat indices, instance rate.
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
    final frameInfo = Float32List(56);
    frameInfo.setRange(0, 16, mvp.storage);
    frameInfo.setRange(16, 32, modelTransform.storage);
    frameInfo[32] = cameraPosition.x;
    frameInfo[33] = cameraPosition.y;
    frameInfo[34] = cameraPosition.z;
    frameInfo[35] = splats.colorSpace == SplatColorSpace.linear ? 1.0 : 0.0;
    frameInfo[36] = splats.paramsWidth.toDouble();
    frameInfo[37] = splats.paramsHeight.toDouble();
    // [38], [39] reserved.
    frameInfo[40] = splats.shWidth.toDouble();
    frameInfo[41] = splats.shHeight.toDouble();
    frameInfo[42] = splats.shStride.toDouble();
    frameInfo[43] = shDegree.toDouble();
    frameInfo[44] = viewport.width;
    frameInfo[45] = viewport.height;
    frameInfo[46] = antialiased ? 1.0 : 0.0;
    frameInfo[47] = splatScale;
    frameInfo[48] = opacity;
    // [49..51] reserved.
    frameInfo[52] = tint.x;
    frameInfo[53] = tint.y;
    frameInfo[54] = tint.z;
    frameInfo[55] = tint.w;
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

/// The splat pipeline layout: slot 0 the per-vertex unit quad, slot 1 the
/// per-instance splat index (a float; the broadest GLES tier has no integer
/// vertex attributes).
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
