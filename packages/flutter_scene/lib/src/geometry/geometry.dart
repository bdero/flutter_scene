import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene_importer/constants.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

/// Vertex (and optional index) data along with the vertex shader used to
/// transform it.
///
/// `Geometry` is the geometry half of a [MeshPrimitive] — the shading half
/// is supplied by a [Material]. Built-in subclasses cover the two
/// supported vertex layouts:
///
///  * [UnskinnedGeometry] — 48-byte vertices: position, normal, UV, color.
///  * [SkinnedGeometry] — 80-byte vertices: unskinned + 4 joint indices +
///    4 joint weights. Used in conjunction with a [Skin].
///
/// Construct an instance directly and call [uploadVertexData] (or
/// [setVertices]/[setIndices] with already-uploaded buffer views) to
/// supply mesh data, or use [Geometry.fromFlatbuffer] when deserializing
/// a `.model` payload. [CuboidGeometry] is provided as a built-in
/// example.
abstract class Geometry {
  gpu.BufferView? _vertices;
  int _vertexCount = 0;

  gpu.BufferView? _indices;
  gpu.IndexType _indexType = gpu.IndexType.int16;
  int _indexCount = 0;

  gpu.Shader? _vertexShader;

  vm.Aabb3? _localBounds;
  vm.Sphere? _localBoundingSphere;

  /// Local-space axis-aligned bounding box of this geometry's vertex
  /// positions, or `null` if bounds are unknown. Computed by
  /// [uploadVertexData] for procedural geometry, populated from the
  /// `.model` flatbuffer for imported geometry, and (for the advanced
  /// [setVertices] path where the caller manages its own GPU buffer)
  /// left `null` unless the caller assigns it via [setLocalBounds].
  vm.Aabb3? get localBounds => _localBounds;

  /// Local-space bounding sphere paired with [localBounds]. Same
  /// nullability semantics.
  vm.Sphere? get localBoundingSphere => _localBoundingSphere;

  /// Override the bounds. Useful for callers driving [setVertices] from
  /// a caller-managed [gpu.DeviceBuffer] who want to participate in
  /// bounds-driven scene queries (e.g. frustum culling).
  void setLocalBounds(vm.Aabb3? aabb, vm.Sphere? sphere) {
    _localBounds = aabb;
    _localBoundingSphere = sphere;
  }

  /// The vertex shader used when rendering this geometry.
  ///
  /// Set by subclasses (or via [setVertexShader]) before the first frame.
  /// Throws if accessed before a shader has been assigned.
  gpu.Shader get vertexShader {
    if (_vertexShader == null) {
      throw Exception('Vertex shader has not been set');
    }
    return _vertexShader!;
  }

  /// Constructs a [Geometry] from a deserialized flatbuffer mesh
  /// primitive, choosing [UnskinnedGeometry] or [SkinnedGeometry] based
  /// on the embedded vertex buffer type.
  ///
  /// The vertex buffer must be a multiple of the layout size (48 bytes
  /// unskinned, 80 bytes skinned); a partial trailing vertex is dropped
  /// with a debug warning.
  static Geometry fromFlatbuffer(fb.MeshPrimitive fbPrimitive) {
    Uint8List vertices;
    bool isSkinned =
        fbPrimitive.vertices!.runtimeType == fb.SkinnedVertexBuffer;
    int perVertexBytes =
        isSkinned ? kSkinnedPerVertexSize : kUnskinnedPerVertexSize;

    switch (fbPrimitive.vertices!.runtimeType) {
      case const (fb.UnskinnedVertexBuffer):
        fb.UnskinnedVertexBuffer unskinned =
            (fbPrimitive.vertices as fb.UnskinnedVertexBuffer?)!;
        vertices = unskinned.vertices! as Uint8List;
      case const (fb.SkinnedVertexBuffer):
        fb.SkinnedVertexBuffer skinned =
            (fbPrimitive.vertices as fb.SkinnedVertexBuffer?)!;
        vertices = skinned.vertices! as Uint8List;
      default:
        throw Exception('Unknown vertex buffer type');
    }

    if (vertices.length % perVertexBytes != 0) {
      debugPrint(
        'OH NO: Encountered an vertex buffer of size '
        '${vertices.lengthInBytes} bytes, which doesn\'t match the '
        'expected multiple of $perVertexBytes bytes. Possible data corruption! '
        'Attempting to use a vertex count of ${vertices.length ~/ perVertexBytes}. '
        'The last ${vertices.length % perVertexBytes} bytes will be ignored.',
      );
    }
    int vertexCount = vertices.length ~/ perVertexBytes;

    gpu.IndexType indexType = fbPrimitive.indices!.type.toIndexType();
    Uint8List indices = fbPrimitive.indices!.data! as Uint8List;

    Geometry geometry;
    switch (fbPrimitive.vertices!.runtimeType) {
      case const (fb.UnskinnedVertexBuffer):
        geometry = UnskinnedGeometry();
      case const (fb.SkinnedVertexBuffer):
        geometry = SkinnedGeometry();
      default:
        throw Exception('Unknown vertex buffer type');
    }

    // Pre-populate bounds from the flatbuffer when present so
    // uploadVertexData can skip the position scan. Geometry written by
    // older importers (without bounds) falls back to a scan.
    //
    // For skinned primitives, prefer the offline-baked
    // `skinned_pose_union_aabb` since it covers every animated pose
    // extent. The static-pose `bounds_aabb` is only useful for
    // editor-style queries on bind-pose extents and would produce
    // wrong cull decisions when joints animate beyond it.
    final fbAabb =
        isSkinned
            ? (fbPrimitive.skinnedPoseUnionAabb ?? fbPrimitive.boundsAabb)
            : fbPrimitive.boundsAabb;
    if (fbAabb != null) {
      geometry._localBounds = vm.Aabb3.minMax(
        vm.Vector3(fbAabb.min.x, fbAabb.min.y, fbAabb.min.z),
        vm.Vector3(fbAabb.max.x, fbAabb.max.y, fbAabb.max.z),
      );
    }
    if (isSkinned && fbPrimitive.skinnedPoseUnionAabb != null) {
      // Derive the sphere from the pose-union AABB so it covers the
      // same animated extent. The baked `bounds_sphere` is fit to the
      // static bind-pose mesh and would be too small.
      geometry._localBoundingSphere = _circumscribedSphere(
        geometry._localBounds!,
      );
    } else {
      final fbSphere = fbPrimitive.boundsSphere;
      if (fbSphere != null) {
        geometry._localBoundingSphere = vm.Sphere.centerRadius(
          vm.Vector3(fbSphere.center.x, fbSphere.center.y, fbSphere.center.z),
          fbSphere.radius,
        );
      }
    }

    geometry.uploadVertexData(
      ByteData.sublistView(vertices),
      vertexCount,
      ByteData.sublistView(indices),
      indexType: indexType,
    );
    return geometry;
  }

  /// Binds an already-uploaded vertex buffer view as this geometry's
  /// vertex source.
  ///
  /// Use this when the caller manages its own [gpu.DeviceBuffer] (for
  /// example, when packing many meshes into a single buffer). For a
  /// turn-key path that allocates and uploads in one step, see
  /// [uploadVertexData].
  void setVertices(gpu.BufferView vertices, int vertexCount) {
    _vertices = vertices;
    _vertexCount = vertexCount;
  }

  /// Binds an already-uploaded index buffer view, with element width
  /// determined by [indexType].
  ///
  /// The element count is computed automatically from the buffer view's
  /// byte length.
  void setIndices(gpu.BufferView indices, gpu.IndexType indexType) {
    _indices = indices;
    _indexType = indexType;
    switch (indexType) {
      case gpu.IndexType.int16:
        _indexCount = indices.lengthInBytes ~/ 2;
      case gpu.IndexType.int32:
        _indexCount = indices.lengthInBytes ~/ 4;
    }
  }

  /// Allocates a [gpu.DeviceBuffer] and uploads [vertices] (and optional
  /// [indices]) into it in one step.
  ///
  /// The vertices must match this geometry subclass's expected layout
  /// (48 bytes per vertex for [UnskinnedGeometry], 80 bytes for
  /// [SkinnedGeometry]). When [indices] is supplied, the buffer is sized
  /// to hold both ranges back-to-back and bound via [setIndices].
  void uploadVertexData(
    ByteData vertices,
    int vertexCount,
    ByteData? indices, {
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    gpu.DeviceBuffer deviceBuffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      indices == null
          ? vertices.lengthInBytes
          : vertices.lengthInBytes + indices.lengthInBytes,
    );

    deviceBuffer.overwrite(vertices, destinationOffsetInBytes: 0);
    setVertices(
      gpu.BufferView(
        deviceBuffer,
        offsetInBytes: 0,
        lengthInBytes: vertices.lengthInBytes,
      ),
      vertexCount,
    );

    if (indices != null) {
      deviceBuffer.overwrite(
        indices,
        destinationOffsetInBytes: vertices.lengthInBytes,
      );
      setIndices(
        gpu.BufferView(
          deviceBuffer,
          offsetInBytes: vertices.lengthInBytes,
          lengthInBytes: indices.lengthInBytes,
        ),
        indexType,
      );
    }

    if (_localBounds == null && vertexCount > 0) {
      _scanLocalBoundsFromVertices(vertices, vertexCount);
    }
  }

  /// Scan the position attribute (the first 12 bytes of each vertex,
  /// shared across the unskinned 48-byte and skinned 80-byte layouts)
  /// to populate [_localBounds] and [_localBoundingSphere].
  void _scanLocalBoundsFromVertices(ByteData vertices, int vertexCount) {
    final stride = vertices.lengthInBytes ~/ vertexCount;
    if (stride < 12) {
      return;
    }
    double minX = double.infinity,
        minY = double.infinity,
        minZ = double.infinity;
    double maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (int i = 0; i < vertexCount; i++) {
      final off = i * stride;
      final x = vertices.getFloat32(off, Endian.little);
      final y = vertices.getFloat32(off + 4, Endian.little);
      final z = vertices.getFloat32(off + 8, Endian.little);
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    final aabb = vm.Aabb3.minMax(
      vm.Vector3(minX, minY, minZ),
      vm.Vector3(maxX, maxY, maxZ),
    );
    _localBounds = aabb;
    _localBoundingSphere ??= _circumscribedSphere(aabb);
  }

  static vm.Sphere _circumscribedSphere(vm.Aabb3 aabb) {
    final center = (aabb.min + aabb.max) * 0.5;
    final extents = (aabb.max - aabb.min) * 0.5;
    return vm.Sphere.centerRadius(center, extents.length);
  }

  /// Assigns the vertex [shader] used when this geometry is drawn.
  ///
  /// The built-in subclasses set this in their constructor. Custom
  /// subclasses may override it with their own shader, typically pulled
  /// from [baseShaderLibrary] or another shader bundle.
  void setVertexShader(gpu.Shader shader) {
    _vertexShader = shader;
  }

  /// Hook for skinned geometries to receive the joints texture computed
  /// by [Skin.getJointsTexture].
  ///
  /// The default implementation does nothing; [SkinnedGeometry] overrides
  /// it to bind the texture in [bind].
  void setJointsTexture(gpu.Texture? texture, int width) {}

  /// Binds vertex/index buffers and per-frame uniforms onto [pass] in
  /// preparation for a draw call.
  ///
  /// Implementations write the model and camera transforms (and any
  /// subclass-specific values, like the joints texture for skinned
  /// geometry) into the supplied transient buffer and bind the resulting
  /// uniform views.
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  );
}

/// Geometry whose vertices use the unskinned 48-byte layout: position
/// (`vec3`), normal (`vec3`), tex coords (`vec2`), color (`vec4`).
///
/// This is the default vertex format for static (non-animated) meshes
/// imported from `.model` or glTF.
class UnskinnedGeometry extends Geometry {
  /// Creates an [UnskinnedGeometry] preconfigured with the
  /// `UnskinnedVertex` shader from [baseShaderLibrary].
  UnskinnedGeometry() {
    setVertexShader(baseShaderLibrary['UnskinnedVertex']!);
  }

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  ) {
    if (_vertices == null) {
      throw Exception(
        'SetVertices must be called before GetBufferView for Geometry.',
      );
    }

    pass.bindVertexBuffer(_vertices!, _vertexCount);
    if (_indices != null) {
      pass.bindIndexBuffer(_indices!, _indexType, _indexCount);
    }

    // Unskinned vertex UBO.
    final frameInfoSlot = vertexShader.getUniformSlot('FrameInfo');
    final frameInfoFloats = Float32List.fromList([
      modelTransform.storage[0],
      modelTransform.storage[1],
      modelTransform.storage[2],
      modelTransform.storage[3],
      modelTransform.storage[4],
      modelTransform.storage[5],
      modelTransform.storage[6],
      modelTransform.storage[7],
      modelTransform.storage[8],
      modelTransform.storage[9],
      modelTransform.storage[10],
      modelTransform.storage[11],
      modelTransform.storage[12],
      modelTransform.storage[13],
      modelTransform.storage[14],
      modelTransform.storage[15],
      cameraTransform.storage[0],
      cameraTransform.storage[1],
      cameraTransform.storage[2],
      cameraTransform.storage[3],
      cameraTransform.storage[4],
      cameraTransform.storage[5],
      cameraTransform.storage[6],
      cameraTransform.storage[7],
      cameraTransform.storage[8],
      cameraTransform.storage[9],
      cameraTransform.storage[10],
      cameraTransform.storage[11],
      cameraTransform.storage[12],
      cameraTransform.storage[13],
      cameraTransform.storage[14],
      cameraTransform.storage[15],
      cameraPosition.x,
      cameraPosition.y,
      cameraPosition.z,
    ]);
    final frameInfoView = transientsBuffer.emplace(
      frameInfoFloats.buffer.asByteData(),
    );
    pass.bindUniform(frameInfoSlot, frameInfoView);
  }
}

/// Geometry whose vertices use the skinned 80-byte layout: the
/// unskinned attributes followed by 4 joint indices and 4 joint weights.
///
/// Used for meshes attached to a [Skin] for skeletal animation. The
/// joints texture supplied by the skin must be assigned before each draw
/// via [setJointsTexture].
class SkinnedGeometry extends Geometry {
  gpu.Texture? _jointsTexture;
  int _jointsTextureWidth = 0;

  /// Creates a [SkinnedGeometry] preconfigured with the `SkinnedVertex`
  /// shader from [baseShaderLibrary].
  SkinnedGeometry() {
    setVertexShader(baseShaderLibrary['SkinnedVertex']!);
  }

  @override
  void setJointsTexture(gpu.Texture? texture, int width) {
    _jointsTexture = texture;
    _jointsTextureWidth = width;
  }

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  ) {
    if (_jointsTexture == null) {
      throw Exception('Joints texture must be set for skinned geometry.');
    }

    pass.bindTexture(
      vertexShader.getUniformSlot('joints_texture'),
      _jointsTexture!,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
        mipFilter: gpu.MipFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );

    if (_vertices == null) {
      throw Exception(
        'SetVertices must be called before GetBufferView for Geometry.',
      );
    }

    pass.bindVertexBuffer(_vertices!, _vertexCount);
    if (_indices != null) {
      pass.bindIndexBuffer(_indices!, _indexType, _indexCount);
    }

    // Skinned vertex UBO.
    final frameInfoSlot = vertexShader.getUniformSlot('FrameInfo');
    final frameInfoFloats = Float32List.fromList([
      modelTransform.storage[0],
      modelTransform.storage[1],
      modelTransform.storage[2],
      modelTransform.storage[3],
      modelTransform.storage[4],
      modelTransform.storage[5],
      modelTransform.storage[6],
      modelTransform.storage[7],
      modelTransform.storage[8],
      modelTransform.storage[9],
      modelTransform.storage[10],
      modelTransform.storage[11],
      modelTransform.storage[12],
      modelTransform.storage[13],
      modelTransform.storage[14],
      modelTransform.storage[15],
      cameraTransform.storage[0],
      cameraTransform.storage[1],
      cameraTransform.storage[2],
      cameraTransform.storage[3],
      cameraTransform.storage[4],
      cameraTransform.storage[5],
      cameraTransform.storage[6],
      cameraTransform.storage[7],
      cameraTransform.storage[8],
      cameraTransform.storage[9],
      cameraTransform.storage[10],
      cameraTransform.storage[11],
      cameraTransform.storage[12],
      cameraTransform.storage[13],
      cameraTransform.storage[14],
      cameraTransform.storage[15],
      cameraPosition.x,
      cameraPosition.y,
      cameraPosition.z,
      _jointsTexture != null ? 1 : 0,
      _jointsTexture != null ? _jointsTextureWidth.toDouble() : 1.0,
    ]);
    final frameInfoView = transientsBuffer.emplace(
      frameInfoFloats.buffer.asByteData(),
    );
    pass.bindUniform(frameInfoSlot, frameInfoView);
  }
}

/// A unit-cube geometry sized to the supplied extents.
///
/// Useful as a quick placeholder or for debugging — pair with any
/// [Material] to render an axis-aligned box. Each face has unique
/// vertex colors, which can be visualized with [UnlitMaterial].
class CuboidGeometry extends UnskinnedGeometry {
  /// Builds a cuboid spanning `-extents/2` to `+extents/2` on each axis.
  CuboidGeometry(vm.Vector3 extents) {
    final e = extents / 2;
    // Layout: Position, normal, uv, color
    final vertices = Float32List.fromList(<double>[
      -e.x, -e.y, -e.z, /* */ 0, 0, -1, /* */ 0, 0, /* */ 1, 0, 0, 1, //
      e.x, -e.y, -e.z, /*  */ 0, 0, -1, /* */ 1, 0, /* */ 0, 1, 0, 1, //
      e.x, e.y, -e.z, /*   */ 0, 0, -1, /* */ 1, 1, /* */ 0, 0, 1, 1, //
      -e.x, e.y, -e.z, /*  */ 0, 0, -1, /* */ 0, 1, /* */ 0, 0, 0, 1, //
      -e.x, -e.y, e.z, /*  */ 0, 0, -1, /* */ 0, 0, /* */ 0, 1, 1, 1, //
      e.x, -e.y, e.z, /*   */ 0, 0, -1, /* */ 1, 0, /* */ 1, 0, 1, 1, //
      e.x, e.y, e.z, /*    */ 0, 0, -1, /* */ 1, 1, /* */ 1, 1, 0, 1, //
      -e.x, e.y, e.z, /*   */ 0, 0, -1, /* */ 0, 1, /* */ 1, 1, 1, 1, //
    ]);

    final indices = Uint16List.fromList(<int>[
      0, 1, 3, 3, 1, 2, //
      1, 5, 2, 2, 5, 6, //
      5, 4, 6, 6, 4, 7, //
      4, 0, 7, 7, 0, 3, //
      3, 2, 7, 7, 2, 6, //
      4, 5, 0, 0, 5, 1, //
    ]);

    uploadVertexData(
      ByteData.sublistView(vertices),
      8,
      ByteData.sublistView(indices),
      indexType: gpu.IndexType.int16,
    );
  }
}
