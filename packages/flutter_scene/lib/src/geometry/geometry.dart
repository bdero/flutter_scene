import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/geometry/mesh_data.dart';
import 'package:flutter_scene/src/geometry/morph_targets.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/material/instance_attributes.dart';
import 'package:flutter_scene/src/material/vertex_attributes.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/depth_raster.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';

/// [data] as a [ByteData], without copying when it already is one.
///
/// Only for CPU-side retention and reinterpretation. An upload keeps the
/// element type instead, so it never goes through here (see
/// [Geometry._uploadStreams]).
ByteData _asByteData(TypedData data) =>
    data is ByteData ? data : ByteData.sublistView(data);

/// Packs immutable mesh uploads into shared GPU buffers.
///
/// Pass one arena to many `MeshGeometry` objects to avoid one GPU allocation
/// per mesh. Uploads are bump-allocated into fixed-size blocks, filling the
/// first block with room, while uploads larger than [blockSizeInBytes]
/// receive a dedicated block. Geometry buffer views retain their blocks, so
/// the arena itself need not outlive the meshes.
///
/// The arena never reclaims space. An allocation stays reserved for as long
/// as the arena is alive, whether or not the geometry that used it still
/// exists, so an arena only ever grows. Use it for geometry loaded or
/// generated in batches with a lifetime the arena can share (a level, a
/// screen), and drop the arena with them. Geometry rebuilt every frame
/// belongs in `GeometryStorage.updatable`, which reuses its buffers in
/// place; an updatable geometry cannot use an arena.
/// {@category Geometry}
class GeometryBufferArena {
  /// Creates an arena with the given minimum block size.
  GeometryBufferArena({this.blockSizeInBytes = 16 * 1024 * 1024}) {
    if (blockSizeInBytes <= 0) {
      throw ArgumentError.value(
        blockSizeInBytes,
        'blockSizeInBytes',
        'must be positive',
      );
    }
  }

  /// Minimum size of each GPU buffer block.
  final int blockSizeInBytes;

  final List<_GeometryBufferBlock> _blocks = [];

  /// Number of GPU buffers allocated by this arena.
  int get bufferCount => _blocks.length;

  /// Total bytes reserved across all GPU buffers.
  int get capacityInBytes =>
      _blocks.fold(0, (total, block) => total + block.buffer.sizeInBytes);

  /// Bytes consumed by geometry data and alignment padding.
  int get usedInBytes =>
      _blocks.fold(0, (total, block) => total + block.usedInBytes);

  gpu.BufferView _allocate(int sizeInBytes) {
    assert(sizeInBytes > 0);
    final alignedSize = (sizeInBytes + 15) & ~15;
    // First fit over every block, so a block's tail is not abandoned the
    // first time an upload does not fit in it.
    _GeometryBufferBlock? block;
    for (final candidate in _blocks) {
      if (candidate.usedInBytes + alignedSize <= candidate.buffer.sizeInBytes) {
        block = candidate;
        break;
      }
    }
    if (block == null) {
      final capacity = alignedSize > blockSizeInBytes
          ? alignedSize
          : blockSizeInBytes;
      block = _GeometryBufferBlock(
        gpu.gpuContext.createDeviceBuffer(
          gpu.StorageMode.hostVisible,
          capacity,
        ),
      );
      _blocks.add(block);
    }
    final offset = block.usedInBytes;
    block.usedInBytes += alignedSize;
    return gpu.BufferView(
      block.buffer,
      offsetInBytes: offset,
      lengthInBytes: sizeInBytes,
    );
  }
}

class _GeometryBufferBlock {
  _GeometryBufferBlock(this.buffer);

  final gpu.DeviceBuffer buffer;
  int usedInBytes = 0;
}

/// Vertex (and optional index) data along with the vertex shader used to
/// transform it.
///
/// `Geometry` is the geometry half of a [MeshPrimitive] — the shading half
/// is supplied by a [Material]. Built-in subclasses cover the two
/// supported vertex layouts:
///
///  * [UnskinnedGeometry] has 72-byte position, normal, UV0, UV1, color,
///    tangent data.
///  * [SkinnedGeometry] has 104-byte unskinned data plus 4 joint indices and
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

  // The index (or vertex) range the next binds and draws use; see
  // [setDrawWindow].
  int _windowFirst = 0;
  int? _windowCount;

  // CPU copies of the uploaded vertex/index data (references to the caller's
  // buffers, not copies), retained by [uploadVertexData] so scene raycasts
  // can test render geometry without reading back from the GPU. Null for
  // geometry driven through [setVertices] (caller-managed buffers).
  ByteData? _cpuVertices;
  ByteData? _cpuIndices;

  // Structure-of-arrays CPU copies for raycasting and readback, set by the
  // SoA upload path instead of the interleaved [_cpuVertices]. Position is
  // required to raycast; texture coordinates let a hit report a UV; normals
  // and colors exist only for [extractMeshData]. Null for interleaved
  // geometry (which reads off [_cpuVertices]) or non-readable geometry.
  Float32List? _cpuPositions;
  Float32List? _cpuTexCoords;
  Float32List? _cpuTexCoords1;
  Float32List? _cpuNormals;
  Float32List? _cpuColors;
  Float32List? _cpuTangents;

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

  /// Whether source triangles use the opposite of native scene winding.
  ///
  /// Native and imported geometry leave it false since both match the CCW
  /// front-face convention. Custom geometries or importers can set it if
  /// their source indices use clockwise winding.
  @internal
  bool sourceWindingFlipped = false;

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
    _clearResolvedOnLayoutChange(1);
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
    _clearResolvedOnLayoutChange(streams.length);
    _vertexStreams = streams;
    _vertexCount = vertexCount;
  }

  // Extra per-vertex attribute streams a material's custom `attributes` read,
  // keyed by the shader `in` name. Bound after the base vertex streams, as the
  // draw's vertex shader declares them (see [useVertexAttributes]). Populated
  // by [setCustomAttribute], which retains the caller's data for
  // [extractMeshData].
  final Map<
    String,
    ({
      gpu.VertexFormat format,
      gpu.BufferView view,
      Float32List data,
      int components,
    })
  >
  _customAttributes = {};

  /// The number of vertex buffer streams this geometry binds for the current
  /// draw: the built-in streams (one interleaved, or several de-interleaved)
  /// plus the custom attribute streams its vertex shader reads. The color pass
  /// binds the instance-rate transform buffer to the slot after these.
  @internal
  int get vertexStreamCount =>
      _vertexStreams.length +
      (_resolveAttributes(_activeAttributes)?.streams.length ??
          _customAttributes.length);

  // The custom attributes the next draw's vertex shader reads, set by the
  // encoder before binding. Null binds every stream the geometry carries.
  VertexAttributeSchema? _activeAttributes;

  /// Selects the custom attributes the next bind supplies: the ones [schema]
  /// declares, reading zero where this geometry has no stream, or every
  /// stream when [schema] is null. The encoders call this before each bind,
  /// like [setJointsTexture], and must resolve the pipeline layout with the
  /// same schema (see [instancedVertexLayoutFor]).
  @internal
  void useVertexAttributes(VertexAttributeSchema? schema) {
    _activeAttributes = schema;
  }

  // Resolved streams and layouts per schema, since one geometry alternates
  // between a material's schema (color) and none (depth) every frame. Cleared
  // when the custom streams or the vertex count change.
  final Map<VertexAttributeSchema, _ResolvedAttributes> _resolved =
      HashMap.identity();
  int _resolvedVertexCount = -1;

  /// Whether this geometry's layout can be narrowed to what a draw's vertex
  /// shader reads. Only the built-in mesh layouts describe their custom slots.
  bool get _resolvesCustomAttributes => false;

  // The streams and layout slots for [schema], or null to bind every stream
  // (no schema, a caller-declared layout, or a geometry kind whose layout
  // cannot be narrowed).
  _ResolvedAttributes? _resolveAttributes(VertexAttributeSchema? schema) {
    if (schema == null || _vertexLayout != null || !_resolvesCustomAttributes) {
      return null;
    }
    if (_resolvedVertexCount != _vertexCount) {
      _resolved.clear();
      _resolvedVertexCount = _vertexCount;
    }
    return _resolved[schema] ??= _buildResolvedAttributes(schema);
  }

  // The built-in layout depends only on how many streams hold the vertex
  // data (interleaved or not), so updatable meshes swapping in same-shaped
  // streams every frame keep their resolved layouts.
  void _clearResolvedOnLayoutChange(int streamCount) {
    if (streamCount != _vertexStreams.length) _resolved.clear();
  }

  _ResolvedAttributes _buildResolvedAttributes(VertexAttributeSchema schema) {
    final slots = resolveVertexAttributeSlots(schema, {
      for (final entry in _customAttributes.entries)
        entry.key: entry.value.format,
    });
    return _ResolvedAttributes([
      for (final slot in slots)
        slot.provided
            ? _customAttributes[slot.name]!.view
            : _zeroAttributeStream(_vertexCount * slot.format.bytesPerElement),
    ], _describedLayoutWith([for (final slot in slots) slot.buffer]));
  }

  /// The pipeline layout for a draw whose vertex shader reads [schema], built
  /// from the custom streams this geometry has now. Null means the shader's
  /// reflected layout.
  @visibleForTesting
  VertexLayoutDescriptor? debugLayoutForAttributes(
    VertexAttributeSchema schema,
  ) {
    if (!_resolvesCustomAttributes) return instancedVertexLayout;
    final slots = resolveVertexAttributeSlots(schema, {
      for (final entry in _customAttributes.entries)
        entry.key: entry.value.format,
    });
    return _describedLayoutWith([for (final slot in slots) slot.buffer]);
  }

  /// The built-in layout with [customBuffers] appended to its vertex slots.
  /// Only called when [_resolvesCustomAttributes] is true.
  VertexLayoutDescriptor? _describedLayoutWith(
    List<VertexBufferDescriptor> customBuffers,
  ) => null;

  // Shared default-filled buffers, one per fill, each grown to the largest
  // stream asked of it. They stand in for attributes a geometry lacks: the
  // zero fill for declared custom attributes and absent texture coordinates
  // or tangents, the others for absent normals and colors.
  static final List<gpu.DeviceBuffer?> _defaultBuffers = List.filled(
    _StreamFill.values.length,
    null,
  );
  static final List<int> _defaultBufferBytes = List.filled(
    _StreamFill.values.length,
    0,
  );

  static gpu.BufferView _zeroAttributeStream(int bytes) =>
      _defaultAttributeStream(_StreamFill.zero, bytes);

  static gpu.BufferView _defaultAttributeStream(_StreamFill fill, int bytes) {
    final size = bytes < 16 ? 16 : bytes;
    var buffer = _defaultBuffers[fill.index];
    if (buffer == null || _defaultBufferBytes[fill.index] < size) {
      final capacity = 1 << (size - 1).bitLength;
      final floats = Float32List(capacity ~/ 4);
      switch (fill) {
        case _StreamFill.zero:
          break;
        case _StreamFill.unitZ:
          for (var i = 2; i < floats.length; i += 3) {
            floats[i] = 1.0;
          }
        case _StreamFill.one:
          floats.fillRange(0, floats.length, 1.0);
      }
      buffer = _defaultBuffers[fill.index] = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        capacity,
      )..overwrite(ByteData.sublistView(floats));
      _defaultBufferBytes[fill.index] = capacity;
    }
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: size);
  }

  /// Whether this geometry carries any custom attribute streams (see
  /// [setCustomAttribute]).
  @internal
  bool get hasCustomAttributes => _customAttributes.isNotEmpty;

  /// The described vertex-buffer slots for this geometry's custom attributes,
  /// in slot order, one tightly packed buffer per attribute. Appended to the
  /// color-pass layout after the built-in attribute buffers.
  @internal
  List<VertexBufferDescriptor> get customAttributeBuffers => [
    for (final entry in _customAttributes.entries)
      VertexBufferDescriptor(
        strideInBytes: entry.value.format.bytesPerElement,
        attributes: [
          VertexAttributeDescriptor(
            name: entry.key,
            format: entry.value.format,
          ),
        ],
      ),
  ];

  /// Attaches a custom per-vertex attribute stream named [name], matching a
  /// material's `attributes` entry (and the generated shader's `in <name>`).
  ///
  /// [data] is a tightly packed run of [components]-component float vectors,
  /// one per vertex (so its length is `vertexCount * components`). The stream
  /// is uploaded to its own buffer and bound after the geometry's built-in
  /// attributes in the color pass; the depth-style passes fetch only position,
  /// so an attribute-driven vertex displacement is not reflected in shadows.
  /// Re-attaching the same [name] replaces it. Attaching one to a skinned mesh
  /// switches it to a described layout, since reflection cannot know which
  /// slot the stream was bound to.
  /// {@category Geometry}
  void setCustomAttribute(
    String name,
    Float32List data, {
    required int components,
  }) {
    if (components < 1 || components > 4) {
      throw ArgumentError.value(
        components,
        'components',
        'must be between 1 and 4',
      );
    }
    // _vertexCount is 0 until the first vertex upload, so a mismatch can only
    // be judged once the count is known. Setting the attribute first is a
    // legitimate ordering, covered by the message clause below.
    if (_vertexCount > 0 && data.length != _vertexCount * components) {
      throw ArgumentError(
        'Custom attribute "$name" has ${data.length} floats, but this geometry '
        'has $_vertexCount vertices at $components components each, so it needs '
        '${_vertexCount * components}. Set the attribute after uploading '
        'vertices, and re-set it after any rebuild that changes the vertex '
        'count.',
      );
    }
    final bytes = ByteData.sublistView(data);
    final buffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      bytes.lengthInBytes,
    );
    buffer.overwrite(bytes);
    _resolved.clear();
    _customAttributes[name] = (
      format: _vertexFormatForComponents(components),
      view: gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      ),
      data: data,
      components: components,
    );
  }

  /// Binds an already-uploaded index buffer view, with element width
  /// determined by [indexType].
  ///
  /// The element count is computed automatically from the buffer view's
  /// byte length.
  void setIndices(gpu.BufferView indices, gpu.IndexType indexType) {
    _indices = indices;
    _indexType = indexType;
    _debugEdges = null;
    switch (indexType) {
      case gpu.IndexType.int16:
        _indexCount = indices.lengthInBytes ~/ 2;
      case gpu.IndexType.int32:
        _indexCount = indices.lengthInBytes ~/ 4;
    }
  }

  /// The index type (int16 or int32) of the bound index buffer.
  @internal
  gpu.IndexType get indexType => _indexType;

  /// Whether this geometry's vertex shader writes the engine's standard
  /// varyings (`material_varyings.glsl`), which the surface debug views and
  /// their fallback shader read. Mesh geometry does; a geometry with its own
  /// fragment contract (billboards, splats) does not and is left out of the
  /// views.
  @internal
  bool get emitsStandardVaryings => true;

  ({gpu.BufferView view, gpu.IndexType type, int count})? _debugEdges;
  bool _debugEdgesUnavailable = false;

  /// A line-list index buffer of this geometry's unique triangle edges,
  /// built from the retained CPU indices on first use and cached until the
  /// indices change. Null when the geometry is not a triangle list or keeps
  /// no CPU data. Drawn by the wireframe overlay with the geometry's own
  /// vertex streams and shader, so every vertex path (skinning, morphing,
  /// instancing, a material's vertex block) holds.
  @internal
  ({gpu.BufferView view, gpu.IndexType type, int count})? get debugEdges {
    final cached = _debugEdges;
    if (cached != null) return cached;
    if (_debugEdgesUnavailable) return null;
    final built = _buildDebugEdges();
    if (built == null) {
      _debugEdgesUnavailable = true;
      return null;
    }
    return _debugEdges = built;
  }

  ({gpu.BufferView view, gpu.IndexType type, int count})? _buildDebugEdges() {
    if (primitiveType != gpu.PrimitiveType.triangle) return null;
    if (_vertexCount == 0) return null;
    final indices = _cpuIndices;
    if (_indices != null && indices == null) return null;
    final edges = debugEdgeIndices(
      indices,
      _indexType,
      _indexCount,
      _vertexCount,
    );
    if (edges.count == 0) return null;
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(edges.bytes);
    return (
      view: gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: edges.bytes.lengthInBytes,
      ),
      type: edges.type,
      count: edges.count,
    );
  }

  /// Allocates GPU storage and uploads [vertices] (and optional [indices])
  /// into it in one step.
  ///
  /// The vertices must match this geometry subclass's expected interleaved
  /// layout (72 bytes per vertex for [UnskinnedGeometry], 104 bytes for
  /// [SkinnedGeometry]). The subclass may split the interleaved bytes into
  /// several tightly packed streams (see [_vertexStreamBytes]); the streams
  /// are bound via [setVertexStreams] and the indices via [setIndices].
  ///
  /// How many [gpu.DeviceBuffer]s that takes, and where in them the indices
  /// land, is the backend's to decide (see [_uploadStreams]), so read the
  /// bound [gpu.BufferView]s rather than assuming a layout. Native packs the
  /// streams and indices back to back into one buffer; web gives each role a
  /// buffer of its own, since WebGL2 types a buffer on first bind.
  ///
  /// Pass [vertices] and [indices] as the element type their store was
  /// allocated as (the engine's packers build interleaved vertices in a
  /// [Float32List] and indices in a [Uint16List] or [Uint32List]); a
  /// [ByteData] over one of those costs a per-element read to upload on web.
  /// See [_uploadStreams].
  void uploadVertexData(
    TypedData vertices,
    int vertexCount,
    TypedData? indices, {
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    final stride = _expectedVertexStrideInBytes;
    if (stride != null && vertices.lengthInBytes != vertexCount * stride) {
      throw ArgumentError(
        'uploadVertexData got ${vertices.lengthInBytes} bytes for $vertexCount '
        'vertices, but $runtimeType packs a $stride-byte vertex, so it needs '
        '${vertexCount * stride} bytes. Repack at $stride bytes per vertex '
        '(position 3, normal 3, tex_coords_0 2, tex_coords_1 2, color 4, '
        'tangent 4'
        '${stride == kSkinnedPerVertexSize ? ', joints 4, weights 4' : ''}, '
        'all float32, in that order), or supply attributes as separate arrays '
        'with MeshGeometry.fromArrays.',
      );
    }

    final vertexBytes = _asByteData(vertices);
    _cpuVertices = vertexBytes;
    _cpuIndices = indices == null ? null : _asByteData(indices);

    _uploadStreams(
      _vertexStreamBytes(vertices, vertexCount),
      vertexCount,
      indices,
      indexType,
      null,
    );

    if (_localBounds == null && vertexCount > 0 && _autoScanBoundsOnUpload) {
      _scanLocalBoundsFromVertices(vertexBytes, vertexCount);
    }
  }

  /// Uploads vertex [streams] in a caller-defined format, one per vertex
  /// buffer slot in order, plus optional [indices].
  ///
  /// The bytes reach the GPU as given. Describe them with [setVertexLayout]
  /// and read them with a vertex shader from [setVertexShader] (or a
  /// `ShaderMaterial` vertex shader); see "Custom vertex formats" in
  /// MATERIALS.md for what that shader must declare and write. Give the
  /// depth-style passes a position-only path with [setDepthOnlyVertex].
  ///
  /// The engine cannot read a packed position, so it scans no bounds and
  /// keeps no positions for raycasting. Call [setLocalBounds], or the mesh is
  /// never culled. [bufferArena] shares one GPU block between many meshes.
  /// {@category Geometry}
  void uploadVertexStreams(
    List<TypedData> streams,
    int vertexCount, {
    TypedData? indices,
    gpu.IndexType indexType = gpu.IndexType.int16,
    GeometryBufferArena? bufferArena,
  }) {
    if (streams.isEmpty) {
      throw ArgumentError.value(streams, 'streams', 'must not be empty');
    }
    _cpuVertices = null;
    _cpuPositions = null;
    _cpuTexCoords = null;
    _cpuTexCoords1 = null;
    _cpuNormals = null;
    _cpuColors = null;
    _cpuTangents = null;
    // Indices alone still feed the wireframe overlay's edge list.
    _cpuIndices = indices == null ? null : _asByteData(indices);
    _uploadsCallerStreams = true;
    _uploadStreams(streams, vertexCount, indices, indexType, bufferArena);
  }

  // Whether the streams came from [uploadVertexStreams], so binding them
  // without a declared layout is a caller error rather than a built-in one.
  bool _uploadsCallerStreams = false;

  /// Packs [streams] (one tightly packed buffer per vertex slot) and any
  /// [indices] into host-visible [gpu.DeviceBuffer] storage, binding the
  /// streams via [setVertexStreams] and the indices via [setIndices]. Shared
  /// by the interleaved and structure-of-arrays upload paths.
  ///
  /// A [GeometryBufferArena] allocation is one block, indices after vertices.
  /// Otherwise the storage comes from [gpu.createGeometryBuffers], which is
  /// the same single buffer on native and one buffer per role on web.
  // TODO(web-buffers): An arena allocation still shares one staged buffer on
  // web, so it keeps the CPU mirror and the second upload this path drops.
  // Splitting it wants an arena per role, or per-role blocks within one.
  ///
  /// [streams] and [indices] are [TypedData] rather than [ByteData] so a
  /// caller holding, say, a [Float32List] can pass it as one: the web backend
  /// under dart2wasm reads a typed list far faster as itself than through a
  /// byte view. A [ByteData] is still accepted everywhere.
  ///
  /// Pass each one as the element type its BACKING STORE was allocated as,
  /// which is not always the type the producer hands back. Under dart2wasm a
  /// view whose element type differs from its store is read element by
  /// element, and 4.65 MB costs 1.4 ms as a [Float32List] over float storage
  /// against 90 ms as a [Float32List] over byte storage, 165 ms as a
  /// [Uint16List] over byte storage, and 340 ms as a [Uint8List] over float
  /// storage. Nothing here can detect a mismatch, so each producer documents
  /// what it allocates: the interleaved packers and
  /// `InterleavedLayoutAdapter.unskinnedAttributeStreams` build float
  /// storage, `splitUnskinnedAttributes` and `.fscene` payloads are byte
  /// storage, and packed indices are their own width (see
  /// `InterleavedLayoutAdapter.indexUploadView`).
  ///
  /// A null stream binds the matching entry of [residentViews] instead, a
  /// view already on the GPU (a shared default stream), and uploads nothing.
  void _uploadStreams(
    List<TypedData?> streams,
    int vertexCount,
    TypedData? indices,
    gpu.IndexType indexType,
    GeometryBufferArena? bufferArena, {
    List<gpu.BufferView?>? residentViews,
  }) {
    var vertexBytes = 0;
    for (final stream in streams) {
      vertexBytes += stream?.lengthInBytes ?? 0;
    }

    final totalBytes = vertexBytes + (indices?.lengthInBytes ?? 0);
    final allocation = bufferArena == null || totalBytes == 0
        ? null
        : bufferArena._allocate(totalBytes);
    final split = allocation == null
        ? gpu.createGeometryBuffers(vertexBytes, indices?.lengthInBytes ?? 0)
        : null;
    final gpu.DeviceBuffer deviceBuffer = allocation?.buffer ?? split!.vertex;
    final gpu.DeviceBuffer indexBuffer = allocation?.buffer ?? split!.index;
    final baseOffset = allocation?.offsetInBytes ?? 0;
    final indexOffset = split == null
        ? baseOffset + vertexBytes
        : split.indexBaseOffset;

    var offset = 0;
    final views = <gpu.BufferView>[];
    for (var i = 0; i < streams.length; i++) {
      final stream = streams[i];
      if (stream == null) {
        views.add(residentViews![i]!);
        continue;
      }
      gpu.writeGeometryData(
        deviceBuffer,
        stream,
        destinationOffsetInBytes: baseOffset + offset,
      );
      views.add(
        gpu.BufferView(
          deviceBuffer,
          offsetInBytes: baseOffset + offset,
          lengthInBytes: stream.lengthInBytes,
        ),
      );
      offset += stream.lengthInBytes;
    }
    setVertexStreams(views, vertexCount);

    if (indices != null) {
      gpu.writeGeometryData(
        indexBuffer,
        indices,
        destinationOffsetInBytes: indexOffset,
      );
      setIndices(
        gpu.BufferView(
          indexBuffer,
          offsetInBytes: indexOffset,
          lengthInBytes: indices.lengthInBytes,
        ),
        indexType,
      );
    }
    if (totalBytes > 0) {
      if (identical(deviceBuffer, indexBuffer)) {
        deviceBuffer.flush(
          offsetInBytes: baseOffset,
          lengthInBytes: totalBytes,
        );
      } else {
        deviceBuffer.flush(
          offsetInBytes: baseOffset,
          lengthInBytes: vertexBytes,
        );
        indexBuffer.flush();
      }
    }
  }

  /// Splits the interleaved [vertices] into the tightly packed vertex streams
  /// this geometry binds, in slot order.
  ///
  /// The default keeps the interleaved bytes as a single stream (slot 0);
  /// [UnskinnedGeometry] overrides it to de-interleave position into its own
  /// stream. Each returned stream is uploaded to its own buffer region by
  /// [uploadVertexData], keeping its element type (see [_uploadStreams]).
  List<TypedData> _vertexStreamBytes(TypedData vertices, int vertexCount) => [
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
    Float32List? texCoords1,
    ByteData? indices,
    Float32List? normals,
    Float32List? colors,
    Float32List? tangents,
  }) {
    _cpuPositions = positions;
    _cpuTexCoords = texCoords;
    _cpuTexCoords1 = texCoords1;
    _cpuNormals = normals;
    _cpuColors = colors;
    _cpuTangents = tangents;
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

  /// Whether this geometry retains CPU-side vertex data, making
  /// [extractMeshData] available.
  ///
  /// True for geometry loaded by the importers or built from attribute
  /// arrays ([MeshGeometry], [GeometryBuilder], the shape geometries).
  /// False for caller-managed vertex buffers ([setVertices] /
  /// [setVertexStreams]) and before the first upload.
  /// {@category Geometry}
  bool get isReadable => _cpuVertices != null || _cpuPositions != null;

  /// Copies this geometry's retained CPU vertex/index data out as an
  /// isolate-transferable [MeshData] snapshot.
  ///
  /// The snapshot is always a copy (never a view of engine memory) with
  /// structure-of-arrays attributes regardless of how the data is stored
  /// internally, so it is safe to send to a background isolate and derive
  /// new geometry from (see [MeshData.unweld], [MeshData.extractEdges]).
  /// Attributes the engine did not retain come back null; skinned geometry
  /// returns bind-pose positions and no joint data.
  ///
  /// Throws a [StateError] when [isReadable] is false.
  /// {@category Geometry}
  MeshData extractMeshData() {
    final interleaved = _cpuVertices;
    final soaPositions = _cpuPositions;
    if (interleaved == null && soaPositions == null) {
      throw StateError(
        'This geometry retains no CPU vertex data to extract '
        '(isReadable is false). Caller-managed vertex buffers are not '
        'readable.',
      );
    }

    Float32List positions;
    Float32List? normals;
    Float32List? texCoords;
    Float32List? texCoords1;
    Float32List? colors;
    Float32List? tangents;
    if (interleaved != null) {
      final stride = this is SkinnedGeometry
          ? kSkinnedPerVertexSize ~/ 4
          : kUnskinnedPerVertexSize ~/ 4;
      final floats = Float32List.sublistView(interleaved);
      positions = Float32List(_vertexCount * 3);
      normals = Float32List(_vertexCount * 3);
      texCoords = Float32List(_vertexCount * 2);
      texCoords1 = Float32List(_vertexCount * 2);
      colors = Float32List(_vertexCount * 4);
      tangents = Float32List(_vertexCount * 4);
      for (var v = 0; v < _vertexCount; v++) {
        final base = v * stride;
        positions[v * 3] = floats[base];
        positions[v * 3 + 1] = floats[base + 1];
        positions[v * 3 + 2] = floats[base + 2];
        normals[v * 3] = floats[base + 3];
        normals[v * 3 + 1] = floats[base + 4];
        normals[v * 3 + 2] = floats[base + 5];
        texCoords[v * 2] = floats[base + 6];
        texCoords[v * 2 + 1] = floats[base + 7];
        texCoords1[v * 2] = floats[base + 8];
        texCoords1[v * 2 + 1] = floats[base + 9];
        colors[v * 4] = floats[base + 10];
        colors[v * 4 + 1] = floats[base + 11];
        colors[v * 4 + 2] = floats[base + 12];
        colors[v * 4 + 3] = floats[base + 13];
        tangents[v * 4] = floats[base + 14];
        tangents[v * 4 + 1] = floats[base + 15];
        tangents[v * 4 + 2] = floats[base + 16];
        tangents[v * 4 + 3] = floats[base + 17];
      }
    } else {
      positions = Float32List.fromList(soaPositions!);
      final n = _cpuNormals;
      final t = _cpuTexCoords;
      final t1 = _cpuTexCoords1;
      final c = _cpuColors;
      final tg = _cpuTangents;
      normals = n == null ? null : Float32List.fromList(n);
      texCoords = t == null ? null : Float32List.fromList(t);
      texCoords1 = t1 == null ? null : Float32List.fromList(t1);
      colors = c == null ? null : Float32List.fromList(c);
      tangents = tg == null ? null : Float32List.fromList(tg);
    }

    List<int>? indices;
    final indexBytes = _cpuIndices;
    if (indexBytes != null && _indexCount > 0) {
      indices = _indexType == gpu.IndexType.int32
          ? Uint32List.fromList(Uint32List.sublistView(indexBytes))
          : Uint16List.fromList(Uint16List.sublistView(indexBytes));
    }

    return MeshData(
      positions: positions,
      vertexCount: _vertexCount,
      normals: normals,
      texCoords: texCoords,
      texCoords1: texCoords1,
      colors: colors,
      tangents: tangents,
      indices: indices,
      primitiveType: primitiveType,
      customAttributes: {
        for (final entry in _customAttributes.entries)
          entry.key: MeshAttributeData(
            Float32List.fromList(entry.value.data),
            components: entry.value.components,
          ),
      },
    );
  }

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

  /// The exact interleaved vertex stride [uploadVertexData] expects, or
  /// null for a caller-defined layout it does not police. The unskinned
  /// and skinned subclasses override it with their fixed strides.
  int? get _expectedVertexStrideInBytes => null;

  /// Scan the position attribute (the first 12 bytes of each vertex,
  /// shared across the unskinned and skinned layouts)
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

  /// The morph target deltas this geometry carries, or null for unmorphed
  /// geometry. Overridden by the morphed geometry subclasses.
  /// {@category Geometry}
  MorphTargetData? get morphTargets => null;

  /// Hook for morphed geometries to receive the owning node's morph weights.
  ///
  /// The default implementation does nothing. The render passes call this
  /// right before each draw's bind (mirroring [setJointsTexture]), so a
  /// geometry shared between several nodes blends each node's own weights.
  void setMorphWeights(Float32List? weights) {}

  /// Grows [localBounds] to cover a node drawing with [weights]. Called
  /// before culling; the default does nothing.
  @internal
  void coverMorphWeights(Float32List weights) {}

  /// Hook for skinned geometries to receive the joints texture computed
  /// by [Skin.getJointsTexture].
  ///
  /// The default implementation does nothing; [SkinnedGeometry] overrides
  /// it to bind the texture in [bind]. The render passes call this right
  /// before each draw's bind, so a geometry shared between several skinned
  /// nodes carries the correct skeleton for every draw.
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
  /// [depthBias] offsets this draw toward [cameraPosition] in world units.
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  });

  /// Emits this geometry's draw call after [bind] has prepared the render pass.
  void draw(gpu.RenderPass pass, {int instanceCount = 1}) {
    if (_indices != null) {
      final count = _windowIndexCount;
      if (count == 0) return;
      drawIndexedCompat(pass, count, instanceCount: instanceCount);
    } else {
      // TODO(draw-window-vertices): honor the window's first vertex, which
      // needs every vertex stream bound at an offset. Only the count applies.
      final count = math.min(_windowCount ?? _vertexCount, _vertexCount);
      if (count == 0) return;
      drawCompat(pass, count, instanceCount: instanceCount);
    }
  }

  /// Restricts the following binds and draws to [count] indices from
  /// [first], or to the rest when [count] is null. Encoders set it for one
  /// draw from a [MeshDrawSelection] and reset it with [clearDrawWindow].
  @internal
  void setDrawWindow(int first, int? count) {
    _windowFirst = first;
    _windowCount = count;
  }

  /// Draws the whole geometry again.
  @internal
  void clearDrawWindow() {
    _windowFirst = 0;
    _windowCount = null;
  }

  int get _windowIndexCount {
    final rest = math.max(0, _indexCount - _windowFirst);
    return math.min(_windowCount ?? rest, rest);
  }

  void _bindIndices(gpu.RenderPass pass) {
    final indices = _indices!;
    if (_windowFirst == 0 && _windowCount == null) {
      bindIndexBufferCompat(pass, indices, _indexType, _indexCount);
      return;
    }
    // Flutter GPU has no first-index draw argument, so the window becomes an
    // offset view of the index buffer.
    final size = _indexType == gpu.IndexType.int32 ? 4 : 2;
    final first = math.min(_windowFirst, _indexCount);
    final count = _windowIndexCount;
    bindIndexBufferCompat(
      pass,
      gpu.BufferView(
        indices.buffer,
        offsetInBytes: indices.offsetInBytes + first * size,
        lengthInBytes: count * size,
      ),
      _indexType,
      count,
    );
  }

  /// The explicit pipeline vertex layout this geometry's vertex shader
  /// expects, or null for the shader bundle's default interleaved layout.
  ///
  /// A caller-supplied layout ([setVertexLayout]) wins over the subclass's
  /// [defaultVertexLayout].
  @internal
  VertexLayoutDescriptor? get instancedVertexLayout =>
      _vertexLayout ?? defaultVertexLayout;

  /// The layout this geometry kind uses when the caller supplies none.
  /// Subclasses that describe their vertices override this.
  @protected
  VertexLayoutDescriptor? get defaultVertexLayout => null;

  // Memoized widened layout, keyed on the schema and base layout it was built
  // from. Both are stable objects in the steady state, so a scene drawing the
  // same geometry/material pair every frame builds this once.
  InstanceAttributeSchema? _widenedSchema;
  VertexLayoutDescriptor? _widenedBase;
  VertexLayoutDescriptor? _widenedLayout;

  /// [instancedVertexLayout] with the trailing instance-rate slot widened by
  /// the per-instance attributes [schema] declares, or the plain layout when
  /// [schema] is null.
  ///
  /// A material's `instance_attributes` append to the instance record the
  /// engine already binds, so the pipeline this geometry draws with depends on
  /// the material as well as the geometry.
  ///
  /// [attributes] narrows the custom attribute slots to the ones the draw's
  /// vertex shader reads (see [useVertexAttributes]); null keeps every stream
  /// this geometry carries.
  @internal
  VertexLayoutDescriptor? instancedVertexLayoutFor(
    InstanceAttributeSchema? schema, [
    VertexAttributeSchema? attributes,
  ]) {
    final resolved = _resolveAttributes(attributes);
    final base = resolved == null ? instancedVertexLayout : resolved.layout;
    if (schema == null || base == null || !bindsModelTransformInstance) {
      return base;
    }
    if (resolved != null) {
      if (identical(schema, resolved.widenedSchema)) return resolved.widened;
      resolved.widenedSchema = schema;
      return resolved.widened = _widen(base, schema);
    }
    if (identical(schema, _widenedSchema) && identical(base, _widenedBase)) {
      return _widenedLayout;
    }
    _widenedSchema = schema;
    _widenedBase = base;
    return _widenedLayout = _widen(base, schema);
  }

  static VertexLayoutDescriptor _widen(
    VertexLayoutDescriptor base,
    InstanceAttributeSchema schema,
  ) => VertexLayoutDescriptor(
    buffers: [
      ...base.buffers.sublist(0, base.buffers.length - 1),
      schema.widen(base.buffers.last),
    ],
  );

  VertexLayoutDescriptor? _vertexLayout;
  bool? _bindsModelTransformInstance;

  /// Declares the pipeline vertex layout this geometry's buffers provide,
  /// overriding the built-in one, or restores the built-in when [layout] is
  /// null.
  ///
  /// Use this with [setVertexShader] to run a vertex stage over vertices the
  /// engine has no opinion about (extra channels, a packed format, or fewer
  /// attributes than the standard vertex carries). The buffers bound by
  /// [setVertices] and [setCustomAttribute] must match the slots described
  /// here, in order.
  ///
  /// A described layout normally means the shader reads the model transform
  /// from an instance-rate buffer the encoder binds in the trailing slot. Pass
  /// [bindsModelTransform] false when the shader gets the transform some other
  /// way (a uniform, as skinned meshes do), so the encoder leaves that slot
  /// alone.
  /// {@category Geometry}
  // A caller-declared layout describes one buffer per bound slot, so a count
  // mismatch means the pipeline reads a slot nothing was bound to. That reads
  // undefined vertex data rather than failing, so catch it in debug where the
  // cause is still obvious. Debug-only; the built-in layouts always agree.
  bool _checkDeclaredLayout() {
    final layout = _vertexLayout;
    if (layout == null) {
      if (_uploadsCallerStreams) {
        throw StateError(
          'Geometry: uploadVertexStreams supplied a caller-defined format, '
          'but no layout describes it. Call setVertexLayout with one buffer '
          'per stream, plus the instance-rate model transform.',
        );
      }
      return true;
    }
    final expected = vertexStreamCount + (bindsModelTransformInstance ? 1 : 0);
    if (layout.buffers.length != expected) {
      throw StateError(
        'Geometry: setVertexLayout described ${layout.buffers.length} vertex '
        'buffer slots, but this draw binds $expected (${_vertexStreams.length} '
        'vertex stream(s), ${_customAttributes.length} custom attribute(s)'
        '${bindsModelTransformInstance ? ", plus the instance-rate model "
                  "transform" : ""}). Describe one buffer per bound slot, in order, '
        'or pass bindsModelTransform: false if the shader takes the model '
        'transform another way.',
      );
    }
    return true;
  }

  void setVertexLayout(
    VertexLayoutDescriptor? layout, {
    bool bindsModelTransform = true,
  }) {
    _vertexLayout = layout;
    _bindsModelTransformInstance = layout == null ? null : bindsModelTransform;
  }

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
  bool get bindsModelTransformInstance =>
      _bindsModelTransformInstance ?? (instancedVertexLayout != null);

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
    assert(_checkDeclaredLayout());
    var slot = 0;
    for (; slot < _vertexStreams.length; slot++) {
      bindVertexBufferCompat(
        pass,
        _vertexStreams[slot],
        _vertexCount,
        slot: slot,
      );
    }
    // Custom attribute streams follow the built-in streams, one slot each, in
    // the order the layout declares them.
    final resolved = _resolveAttributes(_activeAttributes);
    if (resolved != null) {
      for (final view in resolved.streams) {
        bindVertexBufferCompat(pass, view, _vertexCount, slot: slot++);
      }
    } else {
      for (final attr in _customAttributes.values) {
        bindVertexBufferCompat(pass, attr.view, _vertexCount, slot: slot++);
      }
    }
    if (_indices != null) _bindIndices(pass);
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
    if (_indices != null) _bindIndices(pass);
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
      _declaredDepthOnlyVertex;

  ({gpu.Shader shader, VertexLayoutDescriptor layout})?
  _declaredDepthOnlyVertex;

  /// Assigns the position-only vertex [shader] the depth-style passes (shadow
  /// maps, the depth prepass, the selection mask) draw this geometry with, or
  /// clears it when [shader] is null.
  ///
  /// Those passes bind only the first vertex stream, at slot 0, and the
  /// engine's instance-rate model transform at slot 1. [positionStream]
  /// describes that first stream as [shader] reads it; the engine appends the
  /// instance slot. Without a depth shader, a geometry with a declared
  /// [setVertexLayout] draws depth through its full vertex shader and every
  /// stream, which also works but fetches more per vertex.
  /// {@category Geometry}
  void setDepthOnlyVertex(
    gpu.Shader? shader, {
    VertexBufferDescriptor? positionStream,
  }) {
    if (shader == null) {
      _declaredDepthOnlyVertex = null;
      return;
    }
    if (positionStream == null) {
      throw ArgumentError.notNull('positionStream');
    }
    _declaredDepthOnlyVertex = (
      shader: shader,
      layout: VertexLayoutDescriptor(
        buffers: [positionStream, _kInstanceModelTransformBuffer],
      ),
    );
  }
}

/// Geometry whose vertices use the unskinned 72-byte layout.
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
  // Counts only the built-in streams: a single interleaved stream vs the
  // de-interleaved SoA streams. Custom attribute streams are separate and must
  // not flip this (they never change how the built-in attributes are stored).
  bool get _isDeInterleaved => _vertexStreams.length >= 2;

  @override
  int get _expectedVertexStrideInBytes => kUnskinnedPerVertexSize;

  @override
  List<TypedData> _vertexStreamBytes(TypedData vertices, int vertexCount) {
    final streams = InterleavedLayoutAdapter.splitUnskinnedAttributes(
      _asByteData(vertices),
      vertexCount,
    );
    return [
      streams.position,
      streams.normal,
      streams.texCoord,
      streams.texCoord1,
      streams.color,
      streams.tangent,
    ];
  }

  /// Uploads the unskinned attributes from structure-of-arrays lists
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
    Float32List? texCoords1,
    Float32List? colors,
    Float32List? tangents,
    TypedData? indices,
    gpu.IndexType indexType = gpu.IndexType.int16,
    GeometryBufferArena? bufferArena,
    bool retainCpuData = true,
    bool shareAbsentStreams = false,
  }) {
    if (shareAbsentStreams && !retainCpuData) {
      _uploadSharingAbsentStreams(
        positions: positions,
        vertexCount: vertexCount,
        normals: normals,
        texCoords: texCoords,
        texCoords1: texCoords1,
        colors: colors,
        tangents: tangents,
        indices: indices,
        indexType: indexType,
        bufferArena: bufferArena,
      );
      return;
    }
    final streams = InterleavedLayoutAdapter.unskinnedAttributeStreams(
      positions: positions,
      vertexCount: vertexCount,
      normals: normals,
      texCoords: texCoords,
      texCoords1: texCoords1,
      colors: colors,
      tangents: tangents,
    );
    _uploadStreams(
      [
        Float32List.sublistView(streams.position),
        Float32List.sublistView(streams.normal),
        Float32List.sublistView(streams.texCoord),
        Float32List.sublistView(streams.texCoord1),
        Float32List.sublistView(streams.color),
        Float32List.sublistView(streams.tangent),
      ],
      vertexCount,
      indices,
      indexType,
      bufferArena,
    );
    if (retainCpuData) {
      setRaycastAttributes(
        positions: Float32List.sublistView(streams.position),
        texCoords: Float32List.sublistView(streams.texCoord),
        texCoords1: Float32List.sublistView(streams.texCoord1),
        normals: Float32List.sublistView(streams.normal),
        colors: Float32List.sublistView(streams.color),
        tangents: Float32List.sublistView(streams.tangent),
        indices: indices == null ? null : _asByteData(indices),
      );
    }
    if (localBounds == null && vertexCount > 0) {
      scanLocalBoundsFromPositions(
        Float32List.sublistView(streams.position),
        vertexCount,
      );
    }
  }

  // Uploads only the attributes given; each absent one binds a shared stream
  // of its default value, so a mesh without colors (say) stores none.
  void _uploadSharingAbsentStreams({
    required Float32List positions,
    required int vertexCount,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? texCoords1,
    Float32List? colors,
    Float32List? tangents,
    TypedData? indices,
    required gpu.IndexType indexType,
    GeometryBufferArena? bufferArena,
  }) {
    InterleavedLayoutAdapter.checkAttributeLengths(
      positions: positions,
      vertexCount: vertexCount,
      normals: normals,
      texCoords: texCoords,
      texCoords1: texCoords1,
      colors: colors,
      tangents: tangents,
    );
    gpu.BufferView? shared(Float32List? data, _StreamFill fill, int floats) =>
        data != null
        ? null
        : Geometry._defaultAttributeStream(fill, vertexCount * floats * 4);
    _uploadStreams(
      [positions, normals, texCoords, texCoords1, colors, tangents],
      vertexCount,
      indices,
      indexType,
      bufferArena,
      residentViews: [
        null,
        shared(normals, _StreamFill.unitZ, 3),
        shared(texCoords, _StreamFill.zero, 2),
        shared(texCoords1, _StreamFill.zero, 2),
        shared(colors, _StreamFill.one, 4),
        shared(tangents, _StreamFill.zero, 4),
      ],
    );
    if (localBounds == null && vertexCount > 0) {
      scanLocalBoundsFromPositions(positions, vertexCount);
    }
  }

  /// Uploads already-de-interleaved attribute streams (raw bytes) straight
  /// into per-attribute GPU buffers, with no repacking.
  ///
  /// This is the realizer's path for a structure-of-arrays `.fscene` vertex
  /// payload: the payload bytes are sliced into the streams and uploaded
  /// as-is. Position and texture coordinates are retained (as views into the
  /// payload) for raycasting.
  @internal
  void uploadUnskinnedAttributeStreams(
    UnskinnedAttributeStreams streams,
    int vertexCount, {
    TypedData? indices,
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    _uploadStreams(
      [
        streams.position,
        streams.normal,
        streams.texCoord,
        streams.texCoord1,
        streams.color,
        streams.tangent,
      ],
      vertexCount,
      indices,
      indexType,
      null,
    );
    setRaycastAttributes(
      positions: Float32List.sublistView(streams.position),
      texCoords: Float32List.sublistView(streams.texCoord),
      texCoords1: Float32List.sublistView(streams.texCoord1),
      normals: Float32List.sublistView(streams.normal),
      colors: Float32List.sublistView(streams.color),
      tangents: Float32List.sublistView(streams.tangent),
      indices: indices == null ? null : _asByteData(indices),
    );
    if (localBounds == null && vertexCount > 0) {
      scanLocalBoundsFromPositions(
        Float32List.sublistView(streams.position),
        vertexCount,
      );
    }
  }

  @override
  VertexLayoutDescriptor? get defaultVertexLayout =>
      _describedLayoutWith(customAttributeBuffers);

  @override
  bool get _resolvesCustomAttributes => true;

  @override
  VertexLayoutDescriptor _describedLayoutWith(
    List<VertexBufferDescriptor> customBuffers,
  ) {
    final base = _isDeInterleaved
        ? kUnskinnedSoAColorLayout
        : kUnskinnedInstancedLayout;
    if (customBuffers.isEmpty) return base;
    // Splice the custom attribute buffers in before the trailing instance-rate
    // model-transform buffer, so their slots follow the built-in streams and
    // the instance buffer stays at the last slot (vertexStreamCount).
    return VertexLayoutDescriptor(
      buffers: [
        ...base.buffers.sublist(0, base.buffers.length - 1),
        ...customBuffers,
        base.buffers.last,
      ],
    );
  }

  // Cached once: the depth-style passes use the same position-only shader for
  // every unskinned geometry. The layout still depends on whether position is
  // de-interleaved, so only the shader is cached.
  static gpu.Shader? _depthVertexShader;

  // A declared layout means the first stream may not hold a float3 position,
  // so the engine's position-only shader is only safe without one.
  @override
  ({gpu.Shader shader, VertexLayoutDescriptor layout})? get depthOnlyVertex {
    final declared = _declaredDepthOnlyVertex;
    if (declared != null) return declared;
    if (_vertexLayout != null) return null;
    return (
      shader: _depthVertexShader ??= baseShaderLibrary['UnskinnedDepthVertex']!,
      layout: _isDeInterleaved
          ? kUnskinnedSoADepthLayout
          : kUnskinnedPositionOnlyLayout,
    );
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
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
      depthBias: depthBias,
    );
  }
}

/// Geometry whose vertices use the skinned 104-byte layout: the
/// unskinned attributes followed by 4 joint indices and 4 joint weights.
///
/// Used for meshes attached to a [Skin] for skeletal animation. The
/// joints texture supplied by the skin must be assigned before each draw
/// via [setJointsTexture].
/// {@category Geometry}
class SkinnedGeometry extends Geometry {
  // The skinned FrameInfo, shared by every draw since emplace copies it out.
  // The leading model transform stays identity.
  static final Float32List _skinnedFrameInfoScratch = Float32List(44)
    ..setAll(0, vm.Matrix4.identity().storage);

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
  VertexLayoutDescriptor? get defaultVertexLayout =>
      _describedLayoutWith(customAttributeBuffers);

  @override
  bool get _resolvesCustomAttributes => true;

  @override
  VertexLayoutDescriptor? _describedLayoutWith(
    List<VertexBufferDescriptor> customBuffers,
  ) {
    // Without custom attributes the pipeline layout comes from the shader's
    // own reflection, which is how skinned meshes have always drawn. Custom
    // attribute streams have to be described, though, since reflection folds
    // every declared input into the one interleaved buffer.
    if (customBuffers.isEmpty) return null;
    return VertexLayoutDescriptor(
      buffers: [kSkinnedVertexBuffer, ...customBuffers],
    );
  }

  // The model transform rides in the skinned FrameInfo block, not an
  // instance-rate buffer, so describing the layout must not make the encoder
  // bind one.
  @override
  bool get bindsModelTransformInstance => false;

  @override
  bool get _autoScanBoundsOnUpload => false;

  @override
  int get _expectedVertexStrideInBytes => kSkinnedPerVertexSize;

  @override
  void setJointsTexture(gpu.Texture? texture, int width) {
    _jointsTexture = texture;
    _jointsTextureWidth = width;
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    if (_jointsTexture == null) {
      throw Exception('Joints texture must be set for skinned geometry.');
    }

    // Bind against the shader the pipeline runs (a material's skinned vertex
    // variant when supplied), since its uniform slots can differ.
    final boundShader = shaderOverride ?? vertexShader;

    pass.bindTexture(
      boundShader.cachedUniformSlot('joints_texture'),
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
    final frameInfo = _skinnedFrameInfoScratch
      ..setAll(16, cameraTransform.storage)
      ..[32] = cameraPosition.x
      ..[33] = cameraPosition.y
      ..[34] = cameraPosition.z
      ..[35] = _jointsTexture != null ? 1 : 0
      ..[36] = _jointsTexture != null ? _jointsTextureWidth.toDouble() : 1.0
      ..[37] = depthBias
      // std140 places the depth offset vec4 at the next 16-byte boundary.
      ..[40] = currentDrawDepthOffset[0]
      ..[41] = currentDrawDepthOffset[1]
      ..[42] = currentDrawDepthSlope[0]
      ..[43] = currentDrawDepthSlope[2];
    pass.bindUniform(
      boundShader.cachedUniformSlot('FrameInfo'),
      transientsBuffer.emplace(scratchBytesOf(frameInfo)),
    );
  }
}

/// The custom attribute slots a draw binds when its vertex shader reads
/// [schema] and the geometry [provided] these streams: one per declared
/// attribute, in declaration order, reading the geometry's stream when it has
/// one and zero otherwise. Streams nobody declared are left out.
@visibleForTesting
List<({String name, gpu.VertexFormat format, bool provided})>
resolveVertexAttributeSlots(
  VertexAttributeSchema schema,
  Map<String, gpu.VertexFormat> provided,
) => [
  for (final declared in schema.attributes)
    (
      name: declared.name,
      format:
          provided[declared.name] ??
          _vertexFormatForComponents(declared.components),
      provided: provided.containsKey(declared.name),
    ),
];

extension on ({String name, gpu.VertexFormat format, bool provided}) {
  VertexBufferDescriptor get buffer => VertexBufferDescriptor(
    strideInBytes: format.bytesPerElement,
    attributes: [VertexAttributeDescriptor(name: name, format: format)],
  );
}

// A geometry's custom streams resolved against one vertex attribute schema.
// The value a shared default stream holds per vertex.
enum _StreamFill {
  // All components zero (texture coordinates, tangents, custom attributes).
  zero,
  // A `(0, 0, 1)` normal per vertex.
  unitZ,
  // All components one (opaque white color).
  one,
}

class _ResolvedAttributes {
  _ResolvedAttributes(this.streams, this.layout);

  final List<gpu.BufferView> streams;
  final VertexLayoutDescriptor? layout;

  InstanceAttributeSchema? widenedSchema;
  VertexLayoutDescriptor? widened;
}

/// The float [gpu.VertexFormat] for a 1..4-component custom attribute.
gpu.VertexFormat _vertexFormatForComponents(int components) =>
    switch (components) {
      1 => gpu.VertexFormat.float32,
      2 => gpu.VertexFormat.float32x2,
      3 => gpu.VertexFormat.float32x3,
      4 => gpu.VertexFormat.float32x4,
      _ => throw ArgumentError.value(components, 'components', 'must be 1..4'),
    };

/// The instance-rate transform used by depth-style passes.
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

/// The instance-rate transform and color used by color passes.
const VertexBufferDescriptor _kInstanceDataBuffer = VertexBufferDescriptor(
  strideInBytes: 80,
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
    VertexAttributeDescriptor(
      name: 'instance_color',
      format: gpu.VertexFormat.float32x4,
      offsetInBytes: 64,
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
const VertexBufferDescriptor _kTexCoord1Buffer = VertexBufferDescriptor(
  strideInBytes: 8,
  attributes: [
    VertexAttributeDescriptor(
      name: 'texture_coords_1',
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
const VertexBufferDescriptor _kTangentBuffer = VertexBufferDescriptor(
  strideInBytes: 16,
  attributes: [
    VertexAttributeDescriptor(
      name: 'tangent',
      format: gpu.VertexFormat.float32x4,
    ),
  ],
);

/// The interleaved two-buffer pipeline layout for the unskinned vertex
/// shader: slot 0 carries the interleaved 72-byte vertex stream, slot 1 carries
/// the instance-rate model matrix and linear color multiplier (80 bytes per
/// instance).
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
          name: 'texture_coords_1',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 32,
        ),
        VertexAttributeDescriptor(
          name: 'color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 40,
        ),
        VertexAttributeDescriptor(
          name: 'tangent',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 56,
        ),
      ],
    ),
    _kInstanceDataBuffer,
  ],
);

/// The interleaved-mode depth-style layout for the unskinned vertex shader:
/// slot 0 reads only the position attribute from the interleaved vertex
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
/// tightly packed buffer per attribute plus the instance-rate model matrix.
/// Used for geometry
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
    _kTexCoord1Buffer,
    _kColorBuffer,
    _kTangentBuffer,
    _kInstanceDataBuffer,
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
// Reused across every call: this runs for every draw of every pass, and
// [TransientWriter.emplace] copies the bytes out immediately, so a shared
// scratch is safe and avoids a per-draw allocation.
final Float32List _unskinnedFrameInfoScratch = Float32List(28);

@internal
void bindUnskinnedFrameInfo(
  gpu.RenderPass pass,
  TransientWriter transientsBuffer,
  gpu.Shader shader,
  vm.Matrix4 cameraTransform,
  vm.Vector3 cameraPosition, {
  double depthBias = 0.0,
}) {
  final frameInfoSlot = shader.cachedUniformSlot('FrameInfo');
  final scratch = _unskinnedFrameInfoScratch
    ..setAll(0, cameraTransform.storage)
    ..[16] = cameraPosition.x
    ..[17] = cameraPosition.y
    ..[18] = cameraPosition.z
    ..[19] = depthBias
    ..setAll(20, currentDrawDepthOffset)
    ..setAll(24, currentDrawDepthSlope);
  pass.bindUniform(
    frameInfoSlot,
    transientsBuffer.emplace(scratchBytesOf(scratch)),
  );
}

/// Slot 0 of a skinned mesh: the interleaved 104-byte vertex stream the
/// `SkinnedVertex` shader reads. Offsets match the bytes
/// [InterleavedLayoutAdapter.packSkinned] emits.
@internal
const VertexBufferDescriptor kSkinnedVertexBuffer = VertexBufferDescriptor(
  strideInBytes: kSkinnedPerVertexSize,
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
      name: 'texture_coords_1',
      format: gpu.VertexFormat.float32x2,
      offsetInBytes: 32,
    ),
    VertexAttributeDescriptor(
      name: 'color',
      format: gpu.VertexFormat.float32x4,
      offsetInBytes: 40,
    ),
    VertexAttributeDescriptor(
      name: 'tangent',
      format: gpu.VertexFormat.float32x4,
      offsetInBytes: 56,
    ),
    VertexAttributeDescriptor(
      name: 'joints',
      format: gpu.VertexFormat.float32x4,
      offsetInBytes: 72,
    ),
    VertexAttributeDescriptor(
      name: 'weights',
      format: gpu.VertexFormat.float32x4,
      offsetInBytes: 88,
    ),
  ],
);

/// The unique edges of a triangle list as a line-list index buffer.
///
/// [indices] is the triangle index data (null for a non-indexed list of
/// [vertexCount] vertices), read as [indexType]. Edges are deduplicated by
/// their unordered vertex pair, so a shared edge draws once. The result uses
/// 16-bit indices when every vertex fits, 32-bit otherwise.
@visibleForTesting
({ByteData bytes, gpu.IndexType type, int count}) debugEdgeIndices(
  ByteData? indices,
  gpu.IndexType indexType,
  int indexCount,
  int vertexCount,
) {
  final triangleIndexCount = indices == null ? vertexCount : indexCount;
  final triangles = triangleIndexCount ~/ 3;
  int readIndex(int i) {
    if (indices == null) return i;
    return indexType == gpu.IndexType.int16
        ? indices.getUint16(i * 2, Endian.little)
        : indices.getUint32(i * 4, Endian.little);
  }

  // Keyed on the ordered pair; vertexCount is well under the 2^26 that keeps
  // the product inside a double's exact integer range on the web.
  final seen = <int>{};
  final edges = <int>[];
  void addEdge(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    if (seen.add(lo * vertexCount + hi)) {
      edges.add(lo);
      edges.add(hi);
    }
  }

  for (var t = 0; t < triangles; t++) {
    final a = readIndex(t * 3);
    final b = readIndex(t * 3 + 1);
    final c = readIndex(t * 3 + 2);
    if (a == b || b == c || a == c) continue;
    addEdge(a, b);
    addEdge(b, c);
    addEdge(c, a);
  }
  final wide = vertexCount > 0xFFFF;
  final bytes = wide
      ? ByteData.sublistView(Uint32List.fromList(edges))
      : ByteData.sublistView(Uint16List.fromList(edges));
  return (
    bytes: bytes,
    type: wide ? gpu.IndexType.int32 : gpu.IndexType.int16,
    count: edges.length,
  );
}
