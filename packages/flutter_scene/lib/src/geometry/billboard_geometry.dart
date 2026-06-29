import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/shaders.dart';

/// How a billboard quad orients itself toward the camera.
/// {@category Geometry}
enum BillboardFacing {
  /// Per-particle camera-position facing: every quad's normal points at the
  /// eye. Stable as the camera rotates and the best default.
  spherical,

  /// The quad's up axis is locked to [BillboardGeometry.worldUp] (upright
  /// flames, grass, ground cards) and it yaws to face the camera.
  axisLocked,

  /// The quad's up axis follows its per-instance velocity and its long edge
  /// stretches with speed (sparks, rain, speed lines). In-plane rotation is
  /// ignored in this mode.
  velocityStretched,
}

/// A batch of camera-facing quads ("billboards"), expanded from per-instance
/// data in the vertex shader and drawn in a single instanced call.
///
/// Each instance carries a center, a size, an in-plane rotation, a linear
/// RGBA color, a flipbook frame, and a velocity (used only by
/// [BillboardFacing.velocityStretched]). The center is in the geometry's
/// local space; the owning node's transform places and orients the whole
/// batch. Pair it with a `SpriteMaterial` (or any material whose fragment
/// shader reads `v_uv` and `v_color`).
///
/// Write instance data into [instanceData] (a flat [Float32List] of
/// [floatsPerInstance] floats each) and call [commit] with the live count.
/// The batch is the backing primitive for sprites, impostors, and the
/// particle sprite renderer.
/// {@category Geometry}
class BillboardGeometry extends Geometry {
  /// Creates a billboard batch sized for up to [capacity] instances.
  BillboardGeometry({this.capacity = 256})
    : assert(capacity > 0),
      _instanceData = Float32List(capacity * floatsPerInstance) {
    setVertexShader(baseShaderLibrary['BillboardVertex']!);
    final quad = _sharedQuad();
    setVertices(quad.vertices, _kQuadVertexCount);
    setIndices(quad.indices, gpu.IndexType.int16);
  }

  /// The number of floats per instance in [instanceData]: center (3), size
  /// (2), rotation (1), color (4), flipbook frame (1), velocity (3).
  static const int floatsPerInstance = 14;

  static const int _kQuadVertexCount = 4;
  static const int _kInstanceStrideBytes = floatsPerInstance * 4;

  /// The maximum number of instances this batch can draw.
  final int capacity;

  final Float32List _instanceData;
  int _instanceCount = 0;

  /// How the quads orient toward the camera.
  BillboardFacing facing = BillboardFacing.spherical;

  /// The world up axis used to build the billboard basis (and the locked axis
  /// for [BillboardFacing.axisLocked]). Defaults to +Y.
  vm.Vector3 worldUp = vm.Vector3(0, 1, 0);

  /// Flipbook atlas columns and rows. `1 x 1` (the default) samples the whole
  /// texture; larger grids select the cell for each instance's frame.
  int flipbookColumns = 1;
  int flipbookRows = 1;

  /// World units of extra length added per unit of speed in
  /// [BillboardFacing.velocityStretched].
  double velocityStretch = 0.0;

  /// The flat per-instance buffer the caller writes into, [capacity] *
  /// [floatsPerInstance] floats long. Lay out each instance as: center x,y,z;
  /// size x,y; rotation; color r,g,b,a; frame; velocity x,y,z. Call [commit]
  /// after writing.
  Float32List get instanceData => _instanceData;

  /// The number of instances drawn last [commit].
  int get instanceCount => _instanceCount;

  /// Writes one instance's fields at [index] into [instanceData]. A
  /// convenience over hand-indexing the flat buffer; call [commit] when done.
  void setInstance(
    int index, {
    required vm.Vector3 center,
    required double width,
    required double height,
    double rotation = 0.0,
    vm.Vector4? color,
    double frame = 0.0,
    vm.Vector3? velocity,
  }) {
    assert(index >= 0 && index < capacity);
    final o = index * floatsPerInstance;
    final d = _instanceData;
    d[o] = center.x;
    d[o + 1] = center.y;
    d[o + 2] = center.z;
    d[o + 3] = width;
    d[o + 4] = height;
    d[o + 5] = rotation;
    d[o + 6] = color?.x ?? 1.0;
    d[o + 7] = color?.y ?? 1.0;
    d[o + 8] = color?.z ?? 1.0;
    d[o + 9] = color?.w ?? 1.0;
    d[o + 10] = frame;
    d[o + 11] = velocity?.x ?? 0.0;
    d[o + 12] = velocity?.y ?? 0.0;
    d[o + 13] = velocity?.z ?? 0.0;
  }

  /// Sets the number of live instances to draw and recomputes the batch's
  /// local bounds from their centers and sizes (so the owning item culls and,
  /// with an [LodComponent], measures its screen size correctly).
  void commit(int count) {
    assert(count >= 0 && count <= capacity);
    _instanceCount = count;
    _recomputeBounds(count);
  }

  void _recomputeBounds(int count) {
    if (count == 0) {
      setLocalBounds(null, null);
      return;
    }
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    final d = _instanceData;
    for (var i = 0; i < count; i++) {
      final o = i * floatsPerInstance;
      // Pad each center by the instance's half-diagonal so a rotated quad
      // stays inside the box.
      final r = 0.5 * (d[o + 3].abs() + d[o + 4].abs());
      final x = d[o], y = d[o + 1], z = d[o + 2];
      if (x - r < minX) minX = x - r;
      if (y - r < minY) minY = y - r;
      if (z - r < minZ) minZ = z - r;
      if (x + r > maxX) maxX = x + r;
      if (y + r > maxY) maxY = y + r;
      if (z + r > maxZ) maxZ = z + r;
    }
    final aabb = vm.Aabb3.minMax(
      vm.Vector3(minX, minY, minZ),
      vm.Vector3(maxX, maxY, maxZ),
    );
    final center = (aabb.min + aabb.max) * 0.5;
    final radius = (aabb.max - aabb.min).length * 0.5;
    setLocalBounds(aabb, vm.Sphere.centerRadius(center, radius));
  }

  @override
  VertexLayoutDescriptor? get instancedVertexLayout => _kBillboardLayout;

  // The billboard supplies its own slot-1 instance buffer (per-instance
  // attributes) and reads the model transform from the FrameInfo uniform, so
  // the color encoder must not bind a model-transform buffer over slot 1.
  @override
  bool get bindsModelTransformInstance => false;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  ) {
    // Slot 0: the shared unit quad (and its indices).
    bindGeometryBuffers(pass);

    // Slot 1: the live per-instance attributes.
    if (_instanceCount > 0) {
      final liveBytes = ByteData.sublistView(
        _instanceData,
        0,
        _instanceCount * floatsPerInstance,
      );
      pass.bindVertexBuffer(
        instanceTransformBuffers.emplace(liveBytes),
        slot: 1,
      );
    }

    final frameInfo = Float32List(44);
    frameInfo.setRange(0, 16, cameraTransform.storage);
    frameInfo.setRange(16, 32, modelTransform.storage);
    frameInfo[32] = cameraPosition.x;
    frameInfo[33] = cameraPosition.y;
    frameInfo[34] = cameraPosition.z;
    // [35] padding
    frameInfo[36] = worldUp.x;
    frameInfo[37] = worldUp.y;
    frameInfo[38] = worldUp.z;
    // [39] padding
    frameInfo[40] = _facingValue(facing);
    frameInfo[41] = flipbookColumns.toDouble();
    frameInfo[42] = flipbookRows.toDouble();
    frameInfo[43] = velocityStretch;
    pass.bindUniform(
      vertexShader.getUniformSlot('FrameInfo'),
      transientsBuffer.emplace(ByteData.sublistView(frameInfo)),
    );
  }

  @override
  void draw(gpu.RenderPass pass, {int instanceCount = 1}) {
    if (_instanceCount == 0) return;
    drawIndexedCompat(pass, _kQuadIndexCount, instanceCount: _instanceCount);
  }

  static double _facingValue(BillboardFacing facing) => switch (facing) {
    BillboardFacing.spherical => 0.0,
    BillboardFacing.axisLocked => 1.0,
    BillboardFacing.velocityStretched => 2.0,
  };

  // The static unit quad, shared by every billboard batch (one GPU context per
  // process). Slot 0 layout: corner.xy (centered, [-0.5, 0.5]) then quad_uv.xy.
  static const int _kQuadIndexCount = 6;
  static ({gpu.BufferView vertices, gpu.BufferView indices})? _quad;

  static ({gpu.BufferView vertices, gpu.BufferView indices}) _sharedQuad() {
    final cached = _quad;
    if (cached != null) return cached;
    final verts = Float32List.fromList(<double>[
      // corner.x, corner.y, u, v  (uv top-left origin: corner.y +0.5 -> v 0)
      -0.5, -0.5, 0.0, 1.0,
      0.5, -0.5, 1.0, 1.0,
      -0.5, 0.5, 0.0, 0.0,
      0.5, 0.5, 1.0, 0.0,
    ]);
    final indices = Uint16List.fromList(<int>[0, 1, 2, 2, 1, 3]);
    final vBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(verts),
    );
    final iBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(indices),
    );
    final quad = (
      vertices: gpu.BufferView(
        vBuffer,
        offsetInBytes: 0,
        lengthInBytes: verts.lengthInBytes,
      ),
      indices: gpu.BufferView(
        iBuffer,
        offsetInBytes: 0,
        lengthInBytes: indices.lengthInBytes,
      ),
    );
    _quad = quad;
    return quad;
  }
}

/// The billboard pipeline layout: slot 0 the per-vertex unit quad, slot 1 the
/// per-instance attributes.
final VertexLayoutDescriptor _kBillboardLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: 16,
      attributes: [
        VertexAttributeDescriptor(
          name: 'corner',
          format: gpu.VertexFormat.float32x2,
        ),
        VertexAttributeDescriptor(
          name: 'quad_uv',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 8,
        ),
      ],
    ),
    VertexBufferDescriptor(
      strideInBytes: BillboardGeometry._kInstanceStrideBytes,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        VertexAttributeDescriptor(
          name: 'i_center',
          format: gpu.VertexFormat.float32x3,
        ),
        VertexAttributeDescriptor(
          name: 'i_size',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 12,
        ),
        VertexAttributeDescriptor(
          name: 'i_rotation',
          format: gpu.VertexFormat.float32,
          offsetInBytes: 20,
        ),
        VertexAttributeDescriptor(
          name: 'i_color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 24,
        ),
        VertexAttributeDescriptor(
          name: 'i_frame',
          format: gpu.VertexFormat.float32,
          offsetInBytes: 40,
        ),
        VertexAttributeDescriptor(
          name: 'i_velocity',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 44,
        ),
      ],
    ),
  ],
);
