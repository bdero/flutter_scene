import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
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
  // One or more vertex buffer streams, bound to consecutive slots (0, 1, ...)
  // in order. Most geometry has a single interleaved stream; unskinned
  // geometry uploaded through [uploadVertexData] is de-interleaved into a
  // tight position stream plus an attribute stream (see
  // [UnskinnedGeometry._vertexStreamBytes]).
  List<gpu.BufferView> _vertexStreams = const [];
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

  // Structure-of-arrays CPU copies for raycasting, set by the SoA upload path
  // instead of the interleaved [_cpuVertices]. Position is required to
  // raycast; texture coordinates let a hit report a UV. Null for interleaved
  // geometry (which raycasts off [_cpuVertices]) or non-raycastable geometry.
  Float32List? _cpuPositions;
  Float32List? _cpuTexCoords;

  gpu.Shader? _vertexShader;
  String? _vertexShaderName;

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
  /// Set by subclasses, either directly with [setVertexShader] or, for a
  /// shader from [baseShaderLibrary], by name with [setVertexShaderName]. A
  /// name is resolved on first access and cached, so the lookup happens once
  /// (at render time) rather than per draw. Throws if accessed before a
  /// shader has been assigned, or before the base shader bundle has loaded
  /// for a named shader.
  gpu.Shader get vertexShader {
    final resolved = _vertexShader ??= _vertexShaderName == null
        ? null
        : baseShaderLibrary[_vertexShaderName!];
    if (resolved == null) {
      throw Exception('Vertex shader has not been set');
    }
    return resolved;
  }

  /// Binds an already-uploaded vertex buffer view as this geometry's
  /// vertex source.
  ///
  /// Use this when the caller manages its own [gpu.DeviceBuffer] (for
  /// example, when packing many meshes into a single buffer). For a
  /// turn-key path that allocates and uploads in one step, see
  /// [uploadVertexData].
  void setVertices(gpu.BufferView vertices, int vertexCount) {
    _vertexStreams = [vertices];
    _vertexCount = vertexCount;
  }

  /// Binds several already-uploaded vertex streams, in slot order (the first
  /// is slot 0, the second slot 1, and so on).
  ///
  /// Used by the de-interleaved unskinned path, which stores position and the
  /// remaining attributes in separate buffer slots. Single-stream geometry
  /// uses [setVertices].
  @internal
  void setVertexStreams(List<gpu.BufferView> streams, int vertexCount) {
    _vertexStreams = streams;
    _vertexCount = vertexCount;
  }

  /// The number of vertex buffer streams this geometry binds (one for
  /// interleaved geometry, more when de-interleaved). The instance-rate
  /// transform buffer of the color pass binds to this slot.
  @internal
  int get vertexStreamCount => _vertexStreams.length;

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
  /// The vertices must match this geometry subclass's expected interleaved
  /// layout (48 bytes per vertex for [UnskinnedGeometry], 80 bytes for
  /// [SkinnedGeometry]). The subclass may split the interleaved bytes into
  /// several tightly packed streams (see [_vertexStreamBytes]); the streams
  /// and any [indices] are packed back-to-back into one buffer, the streams
  /// bound via [setVertexStreams] and the indices via [setIndices].
  void uploadVertexData(
    ByteData vertices,
    int vertexCount,
    ByteData? indices, {
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    _cpuVertices = vertices;
    _cpuIndices = indices;

    _uploadStreams(
      _vertexStreamBytes(vertices, vertexCount),
      vertexCount,
      indices,
      indexType,
    );

    if (_localBounds == null && vertexCount > 0 && _autoScanBoundsOnUpload) {
      _scanLocalBoundsFromVertices(vertices, vertexCount);
    }
  }

  /// Packs [streams] (one tightly packed buffer per vertex slot) and any
  /// [indices] back-to-back into a single host-visible [gpu.DeviceBuffer],
  /// binding the streams via [setVertexStreams] and the indices via
  /// [setIndices]. Shared by the interleaved and structure-of-arrays upload
  /// paths.
  void _uploadStreams(
    List<ByteData> streams,
    int vertexCount,
    ByteData? indices,
    gpu.IndexType indexType,
  ) {
    var vertexBytes = 0;
    for (final stream in streams) {
      vertexBytes += stream.lengthInBytes;
    }

    final gpu.DeviceBuffer deviceBuffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      vertexBytes + (indices?.lengthInBytes ?? 0),
    );

    var offset = 0;
    final views = <gpu.BufferView>[];
    for (final stream in streams) {
      deviceBuffer.overwrite(stream, destinationOffsetInBytes: offset);
      views.add(
        gpu.BufferView(
          deviceBuffer,
          offsetInBytes: offset,
          lengthInBytes: stream.lengthInBytes,
        ),
      );
      offset += stream.lengthInBytes;
    }
    setVertexStreams(views, vertexCount);

    if (indices != null) {
      deviceBuffer.overwrite(indices, destinationOffsetInBytes: offset);
      setIndices(
        gpu.BufferView(
          deviceBuffer,
          offsetInBytes: offset,
          lengthInBytes: indices.lengthInBytes,
        ),
        indexType,
      );
    }
  }

  /// Splits the interleaved [vertices] into the tightly packed vertex streams
  /// this geometry binds, in slot order.
  ///
  /// The default keeps the interleaved bytes as a single stream (slot 0);
  /// [UnskinnedGeometry] overrides it to de-interleave position into its own
  /// stream. Each returned [ByteData] is uploaded to its own buffer region by
  /// [uploadVertexData].
  List<ByteData> _vertexStreamBytes(ByteData vertices, int vertexCount) => [
    vertices,
  ];

  /// Internal: retains structure-of-arrays CPU attributes (and the index
  /// data) for raycasts, used by the de-interleaved upload path instead of an
  /// interleaved copy. The indices must be retained too, or an indexed mesh
  /// raycasts as a non-indexed triangle list.
  @internal
  void setRaycastAttributes({
    required Float32List positions,
    Float32List? texCoords,
    ByteData? indices,
  }) {
    _cpuPositions = positions;
    _cpuTexCoords = texCoords;
    _cpuIndices = indices;
    _cpuVertices = null;
  }

  /// Internal: the retained CPU vertex/index data for scene raycasts. Either
  /// [vertices] (interleaved) or [positions] (structure of arrays) is set
  /// when the geometry is raycastable; both are null for caller-managed
  /// buffers or before the first upload.
  @internal
  ({
    ByteData? vertices,
    Float32List? positions,
    Float32List? texCoords,
    ByteData? indices,
    gpu.IndexType indexType,
    int vertexCount,
    int indexCount,
  })
  get cpuMeshData => (
    vertices: _cpuVertices,
    positions: _cpuPositions,
    texCoords: _cpuTexCoords,
    indices: _cpuIndices,
    indexType: _indexType,
    vertexCount: _vertexCount,
    indexCount: _indexCount,
  );

  /// Internal: populate bounds from a tightly packed position list (three
  /// floats per vertex), used by the structure-of-arrays upload path.
  @internal
  void scanLocalBoundsFromPositions(Float32List positions, int vertexCount) {
    if (vertexCount == 0) return;
    double minX = double.infinity,
        minY = double.infinity,
        minZ = double.infinity;
    double maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (var i = 0; i < vertexCount; i++) {
      final x = positions[i * 3],
          y = positions[i * 3 + 1],
          z = positions[i * 3 + 2];
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
    _vertexShaderName = null;
  }

  /// Assigns the vertex shader by [name] from [baseShaderLibrary].
  ///
  /// The shader is resolved lazily on first use and then cached, so a
  /// geometry can be constructed before [Scene.initializeStaticResources]
  /// has loaded the base shader bundle. The shader is only needed at render
  /// time, which the engine already defers until the bundle is ready.
  void setVertexShaderName(String name) {
    _vertexShaderName = name;
    _vertexShader = null;
  }

  /// The `.fmat` vertex-variant key for this geometry's mesh type, used to
  /// select a custom material's generated vertex shader (see
  /// [Material.materialVertexShader]). Unskinned geometry is `'unskinned'`;
  /// [SkinnedGeometry] overrides this to `'skinned'`.
  @internal
  String get materialVertexVariant => 'unskinned';

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
  ///
  /// [shaderOverride] is the vertex shader the pipeline actually runs when it
  /// differs from this geometry's default [vertexShader] (a custom material's
  /// generated vertex variant). The per-frame uniforms (`FrameInfo`, the joints
  /// texture) must be bound against that shader's slots, since a variant can
  /// place its uniform blocks at different binding points.
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  });

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

  /// Whether the color encoder should bind the node's model transform as a
  /// one-element instance-rate buffer at the slot after this geometry's
  /// vertex streams.
  ///
  /// True by default whenever [instancedVertexLayout] is set, matching the
  /// unskinned layouts whose shader reads the model matrix from the
  /// instance-rate `model_transform_*` attributes. A geometry that supplies
  /// its own instance-rate buffer (a billboard's per-particle attributes) and
  /// takes the model transform some other way (a uniform) overrides this to
  /// false so the encoder leaves its slot alone.
  @internal
  bool get bindsModelTransformInstance => instancedVertexLayout != null;

  /// Whether this geometry should be drawn without back-face culling.
  ///
  /// Material-driven passes (the color pass) read the cull mode from the
  /// material, but the material-less passes (the selection mask, depth prepass,
  /// shadow map) cull back faces by default. A geometry whose facing is not a
  /// reliable front/back (a camera-facing billboard, whose winding flips with
  /// the view) overrides this to true so those passes draw it from both sides
  /// instead of culling it away.
  @internal
  bool get isDoubleSided => false;

  /// Binds all of this geometry's vertex streams (to slots 0, 1, ...) and
  /// its index buffer onto [pass] without binding any uniforms.
  ///
  /// The color path goes through [bind], which also binds per-frame
  /// uniforms against [vertexShader]. Use this for the full attribute set;
  /// the depth-style passes bind only the position stream with
  /// [bindPositionStream].
  @internal
  void bindGeometryBuffers(gpu.RenderPass pass) {
    _requireVertices();
    for (var slot = 0; slot < _vertexStreams.length; slot++) {
      bindVertexBufferCompat(
        pass,
        _vertexStreams[slot],
        _vertexCount,
        slot: slot,
      );
    }
    if (_indices != null) {
      bindIndexBufferCompat(pass, _indices!, _indexType, _indexCount);
    }
  }

  /// Binds only this geometry's position stream (slot 0) and its index
  /// buffer onto [pass].
  ///
  /// The depth-style passes use this with a position-only shader and layout
  /// (see [depthOnlyVertex]) so they fetch only position. The first stream
  /// holds position for both the interleaved and de-interleaved layouts.
  @internal
  void bindPositionStream(gpu.RenderPass pass) {
    _requireVertices();
    bindVertexBufferCompat(pass, _vertexStreams.first, _vertexCount, slot: 0);
    if (_indices != null) {
      bindIndexBufferCompat(pass, _indices!, _indexType, _indexCount);
    }
  }

  void _requireVertices() {
    if (_vertexStreams.isEmpty) {
      throw Exception('setVertices must be called before binding Geometry.');
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
    setVertexShaderName('UnskinnedVertex');
  }

  // Whether this geometry stores its attributes de-interleaved into separate
  // per-attribute streams (uploaded through [uploadVertexData] or
  // [uploadUnskinnedAttributes]) versus a single interleaved stream (a
  // caller-managed [setVertices] buffer, or the updatable MeshGeometry path).
  // The two store the same bytes but bind different layouts.
  bool get _isDeInterleaved => vertexStreamCount >= 2;

  @override
  List<ByteData> _vertexStreamBytes(ByteData vertices, int vertexCount) {
    final streams = InterleavedLayoutAdapter.splitUnskinnedAttributes(
      vertices,
      vertexCount,
    );
    return [
      ByteData.sublistView(streams.position),
      ByteData.sublistView(streams.normal),
      ByteData.sublistView(streams.texCoord),
      ByteData.sublistView(streams.color),
    ];
  }

  /// Uploads the four unskinned attributes from structure-of-arrays lists
  /// directly into per-attribute streams, with no interleave step.
  ///
  /// This is the efficient path for a structure-of-arrays source (a
  /// procedural mesh, a generator): each attribute is written straight to its
  /// own buffer. Absent attributes get defaults (normal `(0, 0, 1)`, texture
  /// coordinate `(0, 0)`, color opaque white). The position and texture
  /// coordinate streams are retained on the CPU for raycasting.
  @internal
  void uploadUnskinnedAttributes({
    required Float32List positions,
    required int vertexCount,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? colors,
    ByteData? indices,
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    final streams = InterleavedLayoutAdapter.unskinnedAttributeStreams(
      positions: positions,
      vertexCount: vertexCount,
      normals: normals,
      texCoords: texCoords,
      colors: colors,
    );
    _uploadStreams(
      [
        ByteData.sublistView(streams.position),
        ByteData.sublistView(streams.normal),
        ByteData.sublistView(streams.texCoord),
        ByteData.sublistView(streams.color),
      ],
      vertexCount,
      indices,
      indexType,
    );
    setRaycastAttributes(
      positions: Float32List.sublistView(streams.position),
      texCoords: Float32List.sublistView(streams.texCoord),
      indices: indices,
    );
    if (localBounds == null && vertexCount > 0) {
      scanLocalBoundsFromPositions(
        Float32List.sublistView(streams.position),
        vertexCount,
      );
    }
  }

  /// Uploads already-de-interleaved attribute streams (raw bytes) straight
  /// into per-attribute GPU buffers, with no repacking.
  ///
  /// This is the realizer's path for a structure-of-arrays `.fscene` vertex
  /// payload: the payload bytes are sliced into the four streams and uploaded
  /// as-is. Position and texture coordinates are retained (as views into the
  /// payload) for raycasting.
  @internal
  void uploadUnskinnedAttributeStreams(
    UnskinnedAttributeStreams streams,
    int vertexCount, {
    ByteData? indices,
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    _uploadStreams(
      [
        ByteData.sublistView(streams.position),
        ByteData.sublistView(streams.normal),
        ByteData.sublistView(streams.texCoord),
        ByteData.sublistView(streams.color),
      ],
      vertexCount,
      indices,
      indexType,
    );
    setRaycastAttributes(
      positions: Float32List.sublistView(streams.position),
      texCoords: Float32List.sublistView(streams.texCoord),
      indices: indices,
    );
    if (localBounds == null && vertexCount > 0) {
      scanLocalBoundsFromPositions(
        Float32List.sublistView(streams.position),
        vertexCount,
      );
    }
  }

  @override
  VertexLayoutDescriptor? get instancedVertexLayout =>
      _isDeInterleaved ? kUnskinnedSoAColorLayout : kUnskinnedInstancedLayout;

  // Cached once: the depth-style passes use the same position-only shader for
  // every unskinned geometry. The layout still depends on whether position is
  // de-interleaved, so only the shader is cached.
  static gpu.Shader? _depthVertexShader;

  @override
  ({gpu.Shader shader, VertexLayoutDescriptor layout})? get depthOnlyVertex => (
    shader: _depthVertexShader ??= baseShaderLibrary['UnskinnedDepthVertex']!,
    layout: _isDeInterleaved
        ? kUnskinnedSoADepthLayout
        : kUnskinnedPositionOnlyLayout,
  );

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    bindGeometryBuffers(pass);

    // Unskinned vertex UBO. The model transform is NOT part of this block;
    // it arrives through the instance-rate vertex buffer (the last slot),
    // bound by the encoder for instanced and non-instanced draws alike.
    bindUnskinnedFrameInfo(
      pass,
      transientsBuffer,
      shaderOverride ?? vertexShader,
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
    setVertexShaderName('SkinnedVertex');
  }

  @override
  String get materialVertexVariant => 'skinned';

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
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    if (_jointsTexture == null) {
      throw Exception('Joints texture must be set for skinned geometry.');
    }

    // Bind against the shader the pipeline runs (a material's skinned vertex
    // variant when supplied), since its uniform slots can differ.
    final boundShader = shaderOverride ?? vertexShader;

    pass.bindTexture(
      boundShader.getUniformSlot('joints_texture'),
      _jointsTexture!,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
        mipFilter: gpu.MipFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );

    bindGeometryBuffers(pass);

    // Skinned vertex UBO. The model transform is identity on purpose:
    // the joint matrices from Skin.getJointsTexture are already full
    // global transforms (including the scene-root flip), so the shader
    // applies them directly. Passing the mesh node's own transform here
    // would double-apply it (and glTF requires a skinned mesh node's
    // transform to be ignored). `modelTransform` is unused for skinned
    // geometry as a result.
    final identityTransform = vm.Matrix4.identity();
    final frameInfoSlot = boundShader.getUniformSlot('FrameInfo');
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

/// The tightly packed de-interleaved position stream: one `vec3` (12 bytes)
/// per vertex, the slot-0 buffer of the de-interleaved unskinned layouts.
const VertexBufferDescriptor _kPositionBuffer = VertexBufferDescriptor(
  strideInBytes: 12,
  attributes: [
    VertexAttributeDescriptor(
      name: 'position',
      format: gpu.VertexFormat.float32x3,
    ),
  ],
);

/// The tightly packed per-attribute streams (structure of arrays) that make
/// up the de-interleaved unskinned layout, each its own buffer slot: normal
/// (12 bytes), texture coordinates (8 bytes), color (16 bytes).
const VertexBufferDescriptor _kNormalBuffer = VertexBufferDescriptor(
  strideInBytes: 12,
  attributes: [
    VertexAttributeDescriptor(
      name: 'normal',
      format: gpu.VertexFormat.float32x3,
    ),
  ],
);
const VertexBufferDescriptor _kTexCoordBuffer = VertexBufferDescriptor(
  strideInBytes: 8,
  attributes: [
    VertexAttributeDescriptor(
      name: 'texture_coords',
      format: gpu.VertexFormat.float32x2,
    ),
  ],
);
const VertexBufferDescriptor _kColorBuffer = VertexBufferDescriptor(
  strideInBytes: 16,
  attributes: [
    VertexAttributeDescriptor(
      name: 'color',
      format: gpu.VertexFormat.float32x4,
    ),
  ],
);

/// The interleaved two-buffer pipeline layout for the unskinned vertex
/// shader: slot 0 carries the interleaved 48-byte vertex stream (position,
/// normal, texture coords, color), slot 1 carries the instance-rate model
/// matrix as four vec4 columns (64 bytes per instance).
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

/// The interleaved-mode depth-style layout for the unskinned vertex shader:
/// slot 0 reads only the position attribute from the interleaved 48-byte
/// vertex stream (the other attributes are present in the buffer but not
/// fetched), slot 1 the instance-rate model matrix. Paired with the
/// `UnskinnedDepthVertex` shader by the shadow, depth-prepass, and
/// object-mask passes when position is not de-interleaved (a caller-managed
/// [Geometry.setVertices] buffer, or the updatable MeshGeometry path).
///
/// Geometry uploaded through [Geometry.uploadVertexData] is de-interleaved
/// into per-attribute streams and uses [kUnskinnedSoADepthLayout] instead,
/// whose slot-0 stride is 12 for the locality win.
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

/// The structure-of-arrays color layout for the unskinned vertex shader: one
/// tightly packed buffer per attribute (position 12, normal 12, texture
/// coords 8, color 16) plus the instance-rate model matrix. Used for geometry
/// uploaded through [Geometry.uploadVertexData] or the structure-of-arrays
/// upload, which store each attribute in its own stream.
///
/// The attributes could equally be grouped into one interleaved "rest" buffer
/// (one fetch on a tiler); because the layout is interned and the pipeline
/// specialized per draw, that regrouping would be a layout-only change with no
/// API impact. Per-attribute streams are the default for cheap single-
/// attribute updates and zero-interleave uploads.
@internal
final VertexLayoutDescriptor kUnskinnedSoAColorLayout = VertexLayoutDescriptor(
  buffers: const [
    _kPositionBuffer,
    _kNormalBuffer,
    _kTexCoordBuffer,
    _kColorBuffer,
    _kInstanceModelTransformBuffer,
  ],
);

/// The structure-of-arrays depth-style layout for the unskinned vertex
/// shader: slot 0 the tightly packed position stream (12 bytes), slot 1 the
/// instance-rate model matrix. The other attribute streams are not bound, so
/// these passes fetch only the 12-byte position per vertex. Paired with the
/// `UnskinnedDepthVertex` shader.
@internal
final VertexLayoutDescriptor kUnskinnedSoADepthLayout = VertexLayoutDescriptor(
  buffers: const [_kPositionBuffer, _kInstanceModelTransformBuffer],
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
