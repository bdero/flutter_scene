import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/mesh_data.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/shaders.dart';

/// A batch of thick, disconnected line segments, each expanded into a
/// camera-facing quad of a fixed world-space width in the vertex shader and
/// drawn in a single instanced call.
///
/// Native line primitives render one pixel wide on every backend;
/// `LineSegmentsGeometry` is the styled alternative for bulk segment sets, a
/// model wireframe from [MeshData.extractEdges], debug visualization, or any
/// large set of independent segments. The expansion runs on the GPU, so the
/// segments cost no per-frame CPU work (`PolylineGeometry` remains the
/// choice for connected paths that need joins, caps, and dashes).
///
/// Pair it with any material; the expanded ribbon carries the standard
/// vertex outputs (camera-facing normals, `u` along each segment and `v`
/// across it, white vertex color). Segment endpoints are in the geometry's
/// local space and the owning node's transform places the whole batch.
///
/// When the source [LineSegmentData] carries normals, [normalOffset] pushes
/// each endpoint off the surface along them at construction, which keeps a
/// wireframe overlay from z-fighting the mesh it traces.
/// {@category Geometry}
class LineSegmentsGeometry extends Geometry {
  /// Creates a segment batch from [segments].
  ///
  /// [width] is the ribbon's world-space width. [normalOffset] displaces
  /// endpoints along the source normals (ignored when the segment data
  /// carries none).
  LineSegmentsGeometry(
    LineSegmentData segments, {
    double width = 0.01,
    double normalOffset = 0.0,
  }) : _width = width {
    setVertexShader(baseShaderLibrary['LineSegmentsVertex']!);
    final quad = _sharedQuad();
    setVertices(quad.vertices, _kQuadVertexCount);
    setIndices(quad.indices, gpu.IndexType.int16);

    final positions = segments.positions;
    final normals = segments.normals;
    _segmentCount = segments.segmentCount;
    final endpoints = Float32List(positions.length);
    for (var i = 0; i < positions.length; i++) {
      endpoints[i] = normalOffset != 0.0 && normals != null
          ? positions[i] + normals[i] * normalOffset
          : positions[i];
    }
    _endpoints = endpoints;

    if (_segmentCount > 0) {
      final bytes = ByteData.sublistView(endpoints);
      final buffer = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        bytes.lengthInBytes,
      );
      buffer.overwrite(bytes);
      _instances = gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      );
    }
    _recomputeBounds();
  }

  static const int _kQuadVertexCount = 4;
  static const int _kQuadIndexCount = 6;
  static const int _kInstanceStrideBytes = 24; // start (3) + end (3) floats

  late final Float32List _endpoints;
  int _segmentCount = 0;
  gpu.BufferView? _instances;

  double _width;

  /// The ribbon's world-space width. Takes effect on the next frame.
  double get width => _width;
  set width(double value) {
    _width = value;
    _recomputeBounds();
  }

  /// The number of segments drawn.
  int get segmentCount => _segmentCount;

  void _recomputeBounds() {
    if (_segmentCount == 0) {
      setLocalBounds(null, null);
      return;
    }
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    final e = _endpoints;
    for (var i = 0; i < e.length; i += 3) {
      if (e[i] < minX) minX = e[i];
      if (e[i + 1] < minY) minY = e[i + 1];
      if (e[i + 2] < minZ) minZ = e[i + 2];
      if (e[i] > maxX) maxX = e[i];
      if (e[i + 1] > maxY) maxY = e[i + 1];
      if (e[i + 2] > maxZ) maxZ = e[i + 2];
    }
    // Pad by the half width so an expanded ribbon stays inside the box.
    final pad = _width * 0.5;
    final aabb = vm.Aabb3.minMax(
      vm.Vector3(minX - pad, minY - pad, minZ - pad),
      vm.Vector3(maxX + pad, maxY + pad, maxZ + pad),
    );
    final center = (aabb.min + aabb.max) * 0.5;
    final radius = (aabb.max - aabb.min).length * 0.5;
    setLocalBounds(aabb, vm.Sphere.centerRadius(center, radius));
  }

  @override
  VertexLayoutDescriptor? get instancedVertexLayout => _kLineSegmentsLayout;

  // The segments supply their own slot-1 instance buffer and read the model
  // transform from the FrameInfo uniform, so the color encoder must not bind
  // a model-transform buffer over slot 1.
  @override
  bool get bindsModelTransformInstance => false;

  // A camera-facing ribbon's winding flips with the viewing angle, so the
  // material-less passes (selection mask, depth, shadow) must not cull it.
  @override
  bool get isDoubleSided => true;

  // The expansion runs in the engine's own vertex shader; a custom
  // material's generated vertex variants do not apply to this geometry.
  @override
  String get materialVertexVariant => 'line_segments';

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    // See [materialVertexVariant]; the override is accepted and ignored.
    gpu.Shader? shaderOverride,
  }) {
    // Slot 0: the shared unit quad (and its indices).
    bindGeometryBuffers(pass);

    // Slot 1: the per-segment endpoints.
    final instances = _instances;
    if (instances != null) {
      pass.bindVertexBuffer(instances, slot: 1);
    }

    final frameInfo = Float32List(40);
    frameInfo.setRange(0, 16, cameraTransform.storage);
    frameInfo.setRange(16, 32, modelTransform.storage);
    frameInfo[32] = cameraPosition.x;
    frameInfo[33] = cameraPosition.y;
    frameInfo[34] = cameraPosition.z;
    // [35] padding
    frameInfo[36] = _width * 0.5;
    // [37..39] unused
    pass.bindUniform(
      vertexShader.getUniformSlot('FrameInfo'),
      transientsBuffer.emplace(ByteData.sublistView(frameInfo)),
    );
  }

  @override
  void draw(gpu.RenderPass pass, {int instanceCount = 1}) {
    if (_segmentCount == 0) return;
    drawIndexedCompat(pass, _kQuadIndexCount, instanceCount: _segmentCount);
  }

  // The static unit quad, shared by every segment batch (one GPU context per
  // process). Slot 0 layout: corner.x selects the endpoint (0 or 1),
  // corner.y the ribbon side (-1 or +1).
  static ({gpu.BufferView vertices, gpu.BufferView indices})? _quad;

  static ({gpu.BufferView vertices, gpu.BufferView indices}) _sharedQuad() {
    final cached = _quad;
    if (cached != null) return cached;
    final verts = Float32List.fromList(<double>[
      0.0, -1.0, //
      0.0, 1.0, //
      1.0, 1.0, //
      1.0, -1.0,
    ]);
    final indices = Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]);
    final vertexBytes = ByteData.sublistView(verts);
    final indexBytes = ByteData.sublistView(indices);
    final buffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      vertexBytes.lengthInBytes + indexBytes.lengthInBytes,
    );
    buffer.overwrite(vertexBytes);
    buffer.overwrite(
      indexBytes,
      destinationOffsetInBytes: vertexBytes.lengthInBytes,
    );
    final quad = (
      vertices: gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: vertexBytes.lengthInBytes,
      ),
      indices: gpu.BufferView(
        buffer,
        offsetInBytes: vertexBytes.lengthInBytes,
        lengthInBytes: indexBytes.lengthInBytes,
      ),
    );
    _quad = quad;
    return quad;
  }
}

final VertexLayoutDescriptor _kLineSegmentsLayout = VertexLayoutDescriptor(
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
      strideInBytes: LineSegmentsGeometry._kInstanceStrideBytes,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        VertexAttributeDescriptor(
          name: 'i_start',
          format: gpu.VertexFormat.float32x3,
        ),
        VertexAttributeDescriptor(
          name: 'i_end',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 12,
        ),
      ],
    ),
  ],
);
