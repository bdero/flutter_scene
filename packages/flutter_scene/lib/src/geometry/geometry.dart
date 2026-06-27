import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/shaders.dart';

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
/// supply mesh data. For procedurally generated meshes, `MeshGeometry`
/// and `GeometryBuilder` assemble a [Geometry] from vertex attribute
/// arrays without packing vertex bytes by hand.
/// {@category Geometry}
abstract class Geometry {
  gpu.BufferView? _vertices;
  int _vertexCount = 0;

  gpu.BufferView? _indices;
  gpu.IndexType _indexType = gpu.IndexType.int16;
  int _indexCount = 0;

  // CPU copies of the uploaded vertex/index data (references to the caller's
  // buffers, not copies), retained by [uploadVertexData] so scene raycasts
  // can test render geometry without reading back from the GPU. Null for
  // geometry driven through [setVertices] (caller-managed buffers).
  ByteData? _cpuVertices;
  ByteData? _cpuIndices;

  gpu.Shader? _vertexShader;

  /// How the vertex/index data is assembled into primitives when drawn.
  ///
  /// Defaults to [gpu.PrimitiveType.triangle]. Set it to
  /// [gpu.PrimitiveType.lineStrip] or [gpu.PrimitiveType.line] for line
  /// geometry, or [gpu.PrimitiveType.point] for a point list. Native
  /// line and point primitives render at a fixed one-pixel size; thick
  /// styled lines are built as triangle geometry instead.
  gpu.PrimitiveType primitiveType = gpu.PrimitiveType.triangle;

  vm.Aabb3? _localBounds;
  vm.Sphere? _localBoundingSphere;
  int _localBoundsVersion = 0;

  /// A counter that increments each time [setLocalBounds] changes the
  /// bounds.
  ///
  /// Lets cache holders such as [Mesh] notice that an updatable
  /// geometry's bounds moved without an explicit invalidation call.
  @internal
  int get localBoundsVersion => _localBoundsVersion;

  /// Local-space axis-aligned bounding box of this geometry's vertex
  /// positions, or `null` if bounds are unknown. Computed by
  /// [uploadVertexData] for procedural geometry, populated from baked
  /// scene-package bounds for imported geometry, and (for the advanced
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
    _localBoundsVersion++;
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

    _cpuVertices = vertices;
    _cpuIndices = indices;

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

    if (_localBounds == null && vertexCount > 0 && _autoScanBoundsOnUpload) {
      _scanLocalBoundsFromVertices(vertices, vertexCount);
    }
  }

  /// Internal: retains CPU vertex/index data for scene raycasts. Subclasses
  /// with their own upload paths (see MeshGeometry's updatable buffers) call
  /// this when they bypass [uploadVertexData].
  @internal
  void retainCpuMeshData(ByteData? vertices, ByteData? indices) {
    _cpuVertices = vertices;
    _cpuIndices = indices;
  }

  /// Internal: the retained CPU vertex/index data for scene raycasts, or
  /// null vertices when this geometry is not raycastable (caller-managed
  /// buffers via [setVertices], or no upload yet).
  @internal
  ({
    ByteData? vertices,
    ByteData? indices,
    gpu.IndexType indexType,
    int vertexCount,
    int indexCount,
  })
  get cpuMeshData => (
    vertices: _cpuVertices,
    indices: _cpuIndices,
    indexType: _indexType,
    vertexCount: _vertexCount,
    indexCount: _indexCount,
  );

  /// Whether [uploadVertexData] should auto-populate [localBounds] from
  /// the vertex positions when no bound has been set yet. True by
  /// default; [SkinnedGeometry] overrides it to `false` since the
  /// position scan would yield bind-pose extents, which under-cover
  /// the skinned mesh once joints animate. Skinned geometries get
  /// their bounds from the offline-baked `skinned_pose_union_aabb`
  /// instead, or fall back to the always-visible cull path when the
  /// importer didn't bake one (notably the runtime GLB importer).
  bool get _autoScanBoundsOnUpload => true;

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

  /// Emits this geometry's draw call after [bind] has prepared the render pass.
  void draw(gpu.RenderPass pass, {int instanceCount = 1}) {
    if (_indices != null) {
      drawIndexedCompat(pass, _indexCount, instanceCount: instanceCount);
    } else {
      drawCompat(pass, _vertexCount, instanceCount: instanceCount);
    }
  }

  /// The explicit pipeline vertex layout this geometry's vertex shader
  /// expects, or null for the shader bundle's default interleaved layout.
  ///
  /// A non-null layout signals the encoders that the shader consumes the
  /// model transform from the instance-rate vertex buffer (slot 1) rather
  /// than a per-draw uniform, so every draw must bind an instance buffer.
  @internal
  VertexLayoutDescriptor? get instancedVertexLayout => null;

  /// Binds this geometry's vertex buffer (slot 0) and index buffer onto
  /// [pass] without binding any uniforms.
  ///
  /// The color path goes through [bind], which also binds per-frame
  /// uniforms against [vertexShader]. The depth-style passes drive a
  /// different vertex shader (see [depthOnlyVertex]), so they bind the
  /// buffers with this and supply their own uniforms against that shader.
  @internal
  void bindGeometryBuffers(gpu.RenderPass pass) {
    if (_vertices == null) {
      throw Exception('setVertices must be called before binding Geometry.');
    }
    bindVertexBufferCompat(pass, _vertices!, _vertexCount);
    if (_indices != null) {
      bindIndexBufferCompat(pass, _indices!, _indexType, _indexCount);
    }
  }

  /// The vertex shader and layout the depth-style passes (the directional
  /// shadow map, the camera depth prepass, and the object-selection mask)
  /// should use for this geometry, or null to reuse [vertexShader] with
  /// [instancedVertexLayout].
  ///
  /// Unskinned geometry returns a position-only shader and layout so those
  /// passes fetch only the position attribute. Skinned geometry returns
  /// null (its joints-driven shader has no position-only variant yet), so
  /// the depth passes drive it through [bind] like the color pass.
  @internal
  ({gpu.Shader shader, VertexLayoutDescriptor layout})? get depthOnlyVertex =>
      null;
}

/// Geometry whose vertices use the unskinned 48-byte layout: position
/// (`vec3`), normal (`vec3`), tex coords (`vec2`), color (`vec4`).
///
/// This is the default vertex format for static (non-animated) meshes
/// imported from a scene package or glTF.
/// {@category Geometry}
class UnskinnedGeometry extends Geometry {
  /// Creates an [UnskinnedGeometry] preconfigured with the
  /// `UnskinnedVertex` shader from [baseShaderLibrary].
  UnskinnedGeometry() {
    setVertexShader(baseShaderLibrary['UnskinnedVertex']!);
  }

  @override
  VertexLayoutDescriptor? get instancedVertexLayout =>
      kUnskinnedInstancedLayout;

  // Cached once: the depth-style passes use the same position-only shader and
  // layout for every unskinned geometry, so the record is shared rather than
  // rebuilt per draw. The shader keeps its identity across hot reloads.
  static ({gpu.Shader shader, VertexLayoutDescriptor layout})? _depthOnlyVertex;

  @override
  ({gpu.Shader shader, VertexLayoutDescriptor layout})? get depthOnlyVertex =>
      _depthOnlyVertex ??= (
        shader: baseShaderLibrary['UnskinnedDepthVertex']!,
        layout: kUnskinnedPositionOnlyLayout,
      );

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  ) {
    bindGeometryBuffers(pass);

    // Unskinned vertex UBO. The model transform is NOT part of this block;
    // it arrives through the instance-rate vertex buffer (slot 1), bound by
    // the encoder for instanced and non-instanced draws alike.
    bindUnskinnedFrameInfo(
      pass,
      transientsBuffer,
      vertexShader,
      cameraTransform,
      cameraPosition,
    );
  }
}

/// Geometry whose vertices use the skinned 80-byte layout: the
/// unskinned attributes followed by 4 joint indices and 4 joint weights.
///
/// Used for meshes attached to a [Skin] for skeletal animation. The
/// joints texture supplied by the skin must be assigned before each draw
/// via [setJointsTexture].
/// {@category Geometry}
class SkinnedGeometry extends Geometry {
  gpu.Texture? _jointsTexture;
  int _jointsTextureWidth = 0;

  /// Creates a [SkinnedGeometry] preconfigured with the `SkinnedVertex`
  /// shader from [baseShaderLibrary].
  SkinnedGeometry() {
    setVertexShader(baseShaderLibrary['SkinnedVertex']!);
  }

  @override
  bool get _autoScanBoundsOnUpload => false;

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

    bindVertexBufferCompat(pass, _vertices!, _vertexCount);
    if (_indices != null) {
      bindIndexBufferCompat(pass, _indices!, _indexType, _indexCount);
    }

    // Skinned vertex UBO. The model transform is identity on purpose:
    // the joint matrices from Skin.getJointsTexture are already full
    // global transforms (including the scene-root flip), so the shader
    // applies them directly. Passing the mesh node's own transform here
    // would double-apply it (and glTF requires a skinned mesh node's
    // transform to be ignored). `modelTransform` is unused for skinned
    // geometry as a result.
    final identityTransform = vm.Matrix4.identity();
    final frameInfoSlot = vertexShader.getUniformSlot('FrameInfo');
    final frameInfoFloats = Float32List.fromList([
      identityTransform.storage[0],
      identityTransform.storage[1],
      identityTransform.storage[2],
      identityTransform.storage[3],
      identityTransform.storage[4],
      identityTransform.storage[5],
      identityTransform.storage[6],
      identityTransform.storage[7],
      identityTransform.storage[8],
      identityTransform.storage[9],
      identityTransform.storage[10],
      identityTransform.storage[11],
      identityTransform.storage[12],
      identityTransform.storage[13],
      identityTransform.storage[14],
      identityTransform.storage[15],
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

/// The instance-rate vertex buffer slot shared by every unskinned layout:
/// the model matrix as four vec4 columns, 64 bytes per instance, advanced
/// once per instance.
const VertexBufferDescriptor _kInstanceModelTransformBuffer =
    VertexBufferDescriptor(
      strideInBytes: 64,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        VertexAttributeDescriptor(
          name: 'model_transform_0',
          format: gpu.VertexFormat.float32x4,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_1',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 16,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_2',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 32,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_3',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 48,
        ),
      ],
    );

/// The two-buffer pipeline layout for the unskinned vertex shader: slot 0
/// carries the interleaved 48-byte vertex stream (position, normal, texture
/// coords, color), slot 1 carries the instance-rate model matrix as four
/// vec4 columns (64 bytes per instance).
///
/// This is the canonical described layout; its slot-0 stride is
/// [kUnskinnedPerVertexSize] and its attribute offsets match the bytes
/// [InterleavedLayoutAdapter.packUnskinned] emits.
@internal
final VertexLayoutDescriptor kUnskinnedInstancedLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: kUnskinnedPerVertexSize,
      attributes: [
        VertexAttributeDescriptor(
          name: 'position',
          format: gpu.VertexFormat.float32x3,
        ),
        VertexAttributeDescriptor(
          name: 'normal',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 12,
        ),
        VertexAttributeDescriptor(
          name: 'texture_coords',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 24,
        ),
        VertexAttributeDescriptor(
          name: 'color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 32,
        ),
      ],
    ),
    _kInstanceModelTransformBuffer,
  ],
);

/// The depth-style layout for the unskinned vertex shader: slot 0 reads only
/// the position attribute from the interleaved 48-byte vertex stream (the
/// other attributes are present in the buffer but not fetched), slot 1 the
/// instance-rate model matrix. Paired with the `UnskinnedDepthVertex` shader
/// by the shadow, depth-prepass, and object-mask passes so they fetch only
/// position per vertex.
///
/// The bound buffers are identical to the color pass (the same interleaved
/// vertex buffer at slot 0, the same instance buffer at slot 1); only the
/// declared attribute set differs.
///
/// TODO(position-stream): once positions live in their own tightly packed
/// 12-byte buffer (de-interleaved at upload, composing with the dynamic
/// position-update path), drop slot 0's stride to 12 for the locality win.
/// The descriptor and the binding stay otherwise the same.
@internal
final VertexLayoutDescriptor kUnskinnedPositionOnlyLayout =
    VertexLayoutDescriptor(
      buffers: const [
        VertexBufferDescriptor(
          strideInBytes: kUnskinnedPerVertexSize,
          attributes: [
            VertexAttributeDescriptor(
              name: 'position',
              format: gpu.VertexFormat.float32x3,
            ),
          ],
        ),
        _kInstanceModelTransformBuffer,
      ],
    );

/// Emplaces and binds the unskinned `FrameInfo` uniform (camera transform
/// plus camera position) onto [pass], resolving the slot against [shader].
///
/// Shared by the color path ([UnskinnedGeometry.bind]) and the depth-style
/// passes, which drive the position-only shader but use the identical
/// `FrameInfo` block; the slot is resolved against whichever shader the bound
/// pipeline uses.
@internal
void bindUnskinnedFrameInfo(
  gpu.RenderPass pass,
  gpu.HostBuffer transientsBuffer,
  gpu.Shader shader,
  vm.Matrix4 cameraTransform,
  vm.Vector3 cameraPosition,
) {
  final frameInfoSlot = shader.getUniformSlot('FrameInfo');
  final frameInfoFloats = Float32List.fromList([
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
  pass.bindUniform(
    frameInfoSlot,
    transientsBuffer.emplace(frameInfoFloats.buffer.asByteData()),
  );
}
