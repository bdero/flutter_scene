import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';

/// How a [MeshGeometry] manages its GPU buffers over its lifetime.
/// {@category Geometry}
enum GeometryStorage {
  /// The vertex and index buffers are uploaded once at construction and
  /// never change. This is the right choice for imported or generated
  /// meshes that stay still.
  fixed,

  /// The vertex and index buffers are retained so the mesh can be
  /// updated in place every frame without reallocating GPU memory. Use
  /// this for geometry that is regenerated continuously, such as a route
  /// line that follows a moving vehicle.
  ///
  /// An updatable geometry keeps a CPU-side copy of each attribute and
  /// allocates its buffers with spare capacity, so topology-stable
  /// updates ([MeshGeometry.updatePositions] and friends) and bounded
  /// growth ([MeshGeometry.rebuild]) avoid reallocation.
  updatable,
}

/// A triangle mesh built at runtime from vertex attribute arrays.
///
/// `MeshGeometry` is the general-purpose [Geometry] for procedurally
/// generated content. Build one directly from attribute arrays with
/// [MeshGeometry.fromArrays], or assemble it incrementally with a
/// [GeometryBuilder].
///
/// Callers supply attributes as independent typed arrays (positions,
/// normals, texture coordinates, colors) and never pack vertex bytes by
/// hand; the arrays are interleaved into the engine vertex layout
/// internally.
///
/// Pass [GeometryStorage.updatable] as the storage mode to create a
/// geometry that can be mutated in place. [updatePositions],
/// [updateNormals], [updateTexCoords], and [updateColors] replace one
/// attribute when the vertex count is unchanged; [rebuild] replaces
/// everything and reallocates only when the data outgrows the spare
/// capacity.
/// {@category Geometry}
class MeshGeometry extends UnskinnedGeometry {
  /// Builds a mesh from structure-of-arrays vertex attributes.
  ///
  /// [positions] is required and holds three floats per vertex. The
  /// optional attributes hold, per vertex, three floats for [normals],
  /// two for [texCoords], and four for [colors]; each must match the
  /// vertex count implied by [positions] when supplied. Absent
  /// attributes fall back to defaults: texture coordinate `(0, 0)` and
  /// color opaque white.
  ///
  /// When [normals] is omitted and [primitiveType] is a triangle list,
  /// area-weighted vertex normals are generated from the faces; for line
  /// and point primitives, absent normals keep their default. [indices],
  /// when supplied, is an index list; when omitted a triangle mesh must
  /// have a vertex count that is a multiple of three.
  ///
  /// [primitiveType] selects how the vertex/index data is assembled into
  /// primitives when drawn, and defaults to a triangle list.
  ///
  /// [storage] selects whether the mesh can later be updated in place.
  /// An updatable mesh fixes its indexed-or-not state at construction:
  /// supplying [indices] makes [rebuild] require indices thereafter, and
  /// omitting them makes it reject them. To start empty, pass a
  /// zero-length [positions] array with [GeometryStorage.updatable].
  MeshGeometry.fromArrays({
    required Float32List positions,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? colors,
    List<int>? indices,
    gpu.PrimitiveType primitiveType = gpu.PrimitiveType.triangle,
    this.storage = GeometryStorage.fixed,
  }) {
    if (positions.length % 3 != 0) {
      throw ArgumentError(
        'positions has ${positions.length} floats; expected a multiple of '
        'three (one vec3 per vertex)',
      );
    }
    final vertexCount = positions.length ~/ 3;
    this.primitiveType = primitiveType;

    // Normals are generated from triangle faces; line and point
    // geometry has none, so absent normals are left at their default.
    final resolvedNormals =
        normals ??
        (vertexCount > 0 && primitiveType == gpu.PrimitiveType.triangle
            ? InterleavedLayoutAdapter.generateNormals(
                positions: positions,
                vertexCount: vertexCount,
                indices: indices,
              )
            : null);

    if (storage == GeometryStorage.fixed) {
      _uploadFixed(
        positions,
        vertexCount,
        resolvedNormals,
        texCoords,
        colors,
        indices,
      );
    } else {
      _indexed = indices != null;
      _setCpuStreams(
        positions,
        vertexCount,
        resolvedNormals,
        texCoords,
        colors,
      );
      _positionRing = _RingBufferStream(
        InterleavedLayoutAdapter.positionStreamBytes,
      );
      _normalRing = _RingBufferStream(
        InterleavedLayoutAdapter.normalStreamBytes,
      );
      _texCoordRing = _RingBufferStream(
        InterleavedLayoutAdapter.texCoordStreamBytes,
      );
      _colorRing = _RingBufferStream(InterleavedLayoutAdapter.colorStreamBytes);
      _liveVertexCount = vertexCount;
      // Indices first, so the attribute upload can retain them for raycasting.
      if (_indexed) _uploadIndices(indices!);
      _uploadAllStreams();
      _recomputeBounds();
    }
  }

  /// How this geometry's GPU buffers are managed; see [GeometryStorage].
  final GeometryStorage storage;

  // --- Updatable-storage state. Unused while [storage] is fixed. ---

  bool _indexed = false;
  int _liveVertexCount = 0;
  int _indexCapacity = 0;
  gpu.DeviceBuffer? _indexBuffer;
  gpu.IndexType _indexType = gpu.IndexType.int16;

  // One ring of host-visible buffers per attribute, so an in-place update
  // writes to a buffer the GPU is not currently reading (avoiding the
  // write-vs-read race). The index buffer stays single-buffered, since
  // topology-stable updates leave it untouched and only the slow rebuild path
  // rewrites it. [_streamViews] holds the currently bound view of each ring,
  // in slot order (position, normal, texcoord, color).
  late final _RingBufferStream _positionRing;
  late final _RingBufferStream _normalRing;
  late final _RingBufferStream _texCoordRing;
  late final _RingBufferStream _colorRing;
  List<gpu.BufferView> _streamViews = const [];

  // The interleaved vertex bytes, built lazily from the structure-of-arrays
  // CPU streams only when the scene serializer asks for them, and invalidated
  // on every update. Nothing interleaves on the upload path anymore.
  Uint8List? _packedVertexBytes;
  Uint8List? _packedIndexBytes;
  bool _packedIndices32Bit = false;

  /// The packed interleaved vertex bytes (and packed index bytes with their
  /// width), retained so the scene serializer can re-emit this geometry as
  /// payload chunks. Interleaved lazily from the per-attribute CPU streams on
  /// first access.
  ({Uint8List vertexBytes, Uint8List? indexBytes, bool indices32Bit})
  get packedData => (
    vertexBytes: _packedVertexBytes ??= InterleavedLayoutAdapter.packUnskinned(
      positions: _cpuPositions,
      vertexCount: _liveVertexCount,
      normals: _cpuNormals,
      texCoords: _cpuTexCoords,
      colors: _cpuColors,
    ),
    indexBytes: _packedIndexBytes,
    indices32Bit: _packedIndices32Bit,
  );

  Float32List _cpuPositions = Float32List(0);
  Float32List _cpuNormals = Float32List(0);
  Float32List _cpuTexCoords = Float32List(0);
  Float32List _cpuColors = Float32List(0);

  /// The number of vertices currently drawn.
  int get vertexCount => _liveVertexCount;

  /// Whether this geometry can be updated in place.
  bool get isUpdatable => storage == GeometryStorage.updatable;

  /// Replaces every vertex position, keeping the vertex count unchanged.
  ///
  /// [positions] holds three floats per vertex and must match the
  /// current [vertexCount]. To change the vertex count, use [rebuild].
  /// Throws a [StateError] unless this geometry is
  /// [GeometryStorage.updatable].
  void updatePositions(Float32List positions) {
    _ensureUpdatable('updatePositions');
    _checkAttributeLength('positions', positions.length, 3);
    _cpuPositions = Float32List.fromList(positions);
    _writeStream(0, _positionRing, _cpuPositions);
    _recomputeBounds();
  }

  /// Replaces every vertex normal, keeping the vertex count unchanged.
  void updateNormals(Float32List normals) {
    _ensureUpdatable('updateNormals');
    _checkAttributeLength('normals', normals.length, 3);
    _cpuNormals = Float32List.fromList(normals);
    _writeStream(1, _normalRing, _cpuNormals);
  }

  /// Replaces every texture coordinate, keeping the vertex count
  /// unchanged.
  void updateTexCoords(Float32List texCoords) {
    _ensureUpdatable('updateTexCoords');
    _checkAttributeLength('texCoords', texCoords.length, 2);
    _cpuTexCoords = Float32List.fromList(texCoords);
    _writeStream(2, _texCoordRing, _cpuTexCoords);
  }

  /// Replaces every vertex color, keeping the vertex count unchanged.
  void updateColors(Float32List colors) {
    _ensureUpdatable('updateColors');
    _checkAttributeLength('colors', colors.length, 4);
    _cpuColors = Float32List.fromList(colors);
    _writeStream(3, _colorRing, _cpuColors);
  }

  /// Replaces all of this geometry's data, allowing the vertex and index
  /// counts to change.
  ///
  /// Reuses the existing GPU buffers when the new data fits within their
  /// spare capacity, and reallocates with headroom only when it does
  /// not. The indexed-or-not state is fixed at construction: a geometry
  /// created with indices requires [indices] here, and one created
  /// without must omit them. Throws a [StateError] unless this geometry
  /// is [GeometryStorage.updatable].
  void rebuild({
    required Float32List positions,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? colors,
    List<int>? indices,
  }) {
    _ensureUpdatable('rebuild');
    if (positions.length % 3 != 0) {
      throw ArgumentError(
        'positions has ${positions.length} floats; expected a multiple of '
        'three (one vec3 per vertex)',
      );
    }
    if (_indexed && indices == null) {
      throw ArgumentError(
        'This geometry was created with indices; rebuild requires them',
      );
    }
    if (!_indexed && indices != null) {
      throw ArgumentError(
        'This geometry was created without indices; rebuild must not '
        'supply them',
      );
    }
    final vertexCount = positions.length ~/ 3;
    final resolvedNormals =
        normals ??
        (vertexCount > 0 && primitiveType == gpu.PrimitiveType.triangle
            ? InterleavedLayoutAdapter.generateNormals(
                positions: positions,
                vertexCount: vertexCount,
                indices: indices,
              )
            : null);

    _setCpuStreams(positions, vertexCount, resolvedNormals, texCoords, colors);
    _liveVertexCount = vertexCount;
    // The rings reallocate themselves when the count outgrows their capacity.
    if (_indexed) _uploadIndices(indices!);
    _uploadAllStreams();
    _recomputeBounds();
  }

  void _uploadFixed(
    Float32List positions,
    int vertexCount,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? colors,
    List<int>? indices,
  ) {
    _liveVertexCount = vertexCount;
    // Retain the structure-of-arrays attributes (defaults filled). These back
    // both lazy serialization (interleaved on demand) and raycasting, and they
    // are uploaded straight to per-attribute GPU streams with no interleave.
    _setCpuStreams(positions, vertexCount, normals, texCoords, colors);
    ByteData? indexBytes;
    var indexType = gpu.IndexType.int16;
    if (indices != null) {
      final packed = InterleavedLayoutAdapter.packIndices(indices);
      indexBytes = ByteData.sublistView(packed.bytes);
      indexType = packed.is32Bit ? gpu.IndexType.int32 : gpu.IndexType.int16;
      _packedIndexBytes = packed.bytes;
      _packedIndices32Bit = packed.is32Bit;
    }
    uploadUnskinnedAttributes(
      positions: _cpuPositions,
      vertexCount: vertexCount,
      normals: _cpuNormals,
      texCoords: _cpuTexCoords,
      colors: _cpuColors,
      indices: indexBytes,
      indexType: indexType,
    );
    // Raycast off this geometry's own attribute arrays instead of the
    // transient upload copies, so no extra position/texcoord copy lingers.
    // Keep the index bytes so an indexed mesh raycasts as indexed.
    setRaycastAttributes(
      positions: _cpuPositions,
      texCoords: _cpuTexCoords,
      indices: indexBytes,
    );
  }

  // Writes all four attribute streams into their rings and binds them.
  // Used at construction and on rebuild.
  void _uploadAllStreams() {
    _streamViews = [
      _positionRing.write(_bytesOf(_cpuPositions), _liveVertexCount),
      _normalRing.write(_bytesOf(_cpuNormals), _liveVertexCount),
      _texCoordRing.write(_bytesOf(_cpuTexCoords), _liveVertexCount),
      _colorRing.write(_bytesOf(_cpuColors), _liveVertexCount),
    ];
    setVertexStreams(_streamViews, _liveVertexCount);
    _refreshRaycastData();
    // Invalidate the lazily interleaved serialization bytes.
    _packedVertexBytes = null;
  }

  // Writes one changed attribute into its ring's next buffer and rebinds the
  // streams. The other attributes keep their current ring buffers, so only
  // the dirty stream's bytes are re-uploaded.
  void _writeStream(int slot, _RingBufferStream ring, Float32List attribute) {
    _streamViews = List<gpu.BufferView>.of(_streamViews);
    _streamViews[slot] = ring.write(_bytesOf(attribute), _liveVertexCount);
    setVertexStreams(_streamViews, _liveVertexCount);
    _refreshRaycastData();
    _packedVertexBytes = null;
  }

  void _refreshRaycastData() {
    setRaycastAttributes(
      positions: _cpuPositions,
      texCoords: _cpuTexCoords,
      indices: _packedIndexBytes == null
          ? null
          : ByteData.sublistView(_packedIndexBytes!),
    );
  }

  static Uint8List _bytesOf(Float32List attribute) => attribute.buffer
      .asUint8List(attribute.offsetInBytes, attribute.lengthInBytes);

  void _uploadIndices(List<int> indices) {
    final packed = InterleavedLayoutAdapter.packIndices(indices);
    _packedIndexBytes = packed.bytes;
    _packedIndices32Bit = packed.is32Bit;
    // Raycast index data is retained alongside the attribute streams by
    // [_refreshRaycastData]; this method only manages the GPU index buffer.
    final indexType = packed.is32Bit
        ? gpu.IndexType.int32
        : gpu.IndexType.int16;
    final elementBytes = packed.is32Bit ? 4 : 2;
    if (_indexBuffer == null ||
        indices.length > _indexCapacity ||
        indexType != _indexType) {
      _indexCapacity = nextBufferCapacity(indices.length);
      _indexType = indexType;
      _indexBuffer = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        _indexCapacity * elementBytes,
      );
    }
    final buffer = _indexBuffer!;
    if (packed.bytes.isNotEmpty) {
      buffer.overwrite(ByteData.sublistView(packed.bytes));
      buffer.flush(offsetInBytes: 0, lengthInBytes: packed.bytes.length);
    }
    setIndices(
      gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: packed.bytes.length,
      ),
      indexType,
    );
  }

  void _setCpuStreams(
    Float32List positions,
    int vertexCount,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? colors,
  ) {
    if (normals != null && normals.length != vertexCount * 3) {
      throw ArgumentError(
        'normals has ${normals.length} floats; expected ${vertexCount * 3}',
      );
    }
    if (texCoords != null && texCoords.length != vertexCount * 2) {
      throw ArgumentError(
        'texCoords has ${texCoords.length} floats; expected '
        '${vertexCount * 2}',
      );
    }
    if (colors != null && colors.length != vertexCount * 4) {
      throw ArgumentError(
        'colors has ${colors.length} floats; expected ${vertexCount * 4}',
      );
    }
    _cpuPositions = Float32List.fromList(positions);
    _cpuNormals = normals != null
        ? Float32List.fromList(normals)
        : _filledStream(vertexCount, 3, const [0.0, 0.0, 1.0]);
    _cpuTexCoords = texCoords != null
        ? Float32List.fromList(texCoords)
        : Float32List(vertexCount * 2);
    _cpuColors = colors != null
        ? Float32List.fromList(colors)
        : _filledStream(vertexCount, 4, const [1.0, 1.0, 1.0, 1.0]);
  }

  void _recomputeBounds() {
    if (_liveVertexCount == 0) {
      setLocalBounds(null, null);
      return;
    }
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (var v = 0; v < _liveVertexCount; v++) {
      final x = _cpuPositions[v * 3];
      final y = _cpuPositions[v * 3 + 1];
      final z = _cpuPositions[v * 3 + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    final min = Vector3(minX, minY, minZ);
    final max = Vector3(maxX, maxY, maxZ);
    final center = (min + max) * 0.5;
    final radius = ((max - min) * 0.5).length;
    setLocalBounds(Aabb3.minMax(min, max), Sphere.centerRadius(center, radius));
  }

  void _ensureUpdatable(String operation) {
    if (storage != GeometryStorage.updatable) {
      throw StateError(
        '$operation requires GeometryStorage.updatable; this geometry is '
        'fixed',
      );
    }
  }

  void _checkAttributeLength(String name, int length, int componentsPerVertex) {
    final expected = _liveVertexCount * componentsPerVertex;
    if (length != expected) {
      throw ArgumentError(
        '$name has $length floats; a topology-stable update expects '
        '$expected for $_liveVertexCount vertices. Use rebuild to change '
        'the vertex count.',
      );
    }
  }

  static Float32List _filledStream(
    int vertexCount,
    int componentsPerVertex,
    List<double> value,
  ) {
    final stream = Float32List(vertexCount * componentsPerVertex);
    for (var v = 0; v < vertexCount; v++) {
      for (var c = 0; c < componentsPerVertex; c++) {
        stream[v * componentsPerVertex + c] = value[c];
      }
    }
    return stream;
  }
}

/// Rounds [needed] up to a buffer capacity with spare headroom.
///
/// Updatable geometry allocates its GPU buffers at the returned size so
/// that a buffer which grows gradually reallocates only a logarithmic
/// number of times rather than on every change. The result is the
/// smallest power of two that is at least [needed] and at least
/// [minimum].
int nextBufferCapacity(int needed, {int minimum = 16}) {
  if (needed <= minimum) return minimum;
  var capacity = minimum;
  while (capacity < needed) {
    capacity <<= 1;
  }
  return capacity;
}

/// A small ring of host-visible device buffers for one updatable attribute
/// stream.
///
/// Each [write] advances to the next buffer in the ring before overwriting,
/// so the GPU keeps reading the previously bound buffer while the CPU writes
/// the next one. The ring depth matches the frame count the engine's
/// transient `HostBuffer` cycles through, which bounds the GPU's in-flight
/// reads. The ring reallocates (at a power-of-two capacity) only when the
/// vertex count outgrows it, so steady-state updates never allocate.
class _RingBufferStream {
  _RingBufferStream(this.bytesPerVertex);

  /// Tightly packed bytes for one vertex of this attribute.
  final int bytesPerVertex;

  // Matches `gpu.HostBuffer`'s frame count, the number of frames the engine
  // cycles transient buffers through.
  static const int _ringDepth = 4;

  final List<gpu.DeviceBuffer> _buffers = [];
  int _capacityVertices = 0;
  int _cursor = 0;

  gpu.BufferView write(Uint8List bytes, int vertexCount) {
    if (_buffers.isEmpty || vertexCount > _capacityVertices) {
      _capacityVertices = nextBufferCapacity(vertexCount);
      _buffers
        ..clear()
        ..addAll(
          List.generate(
            _ringDepth,
            (_) => gpu.gpuContext.createDeviceBuffer(
              gpu.StorageMode.hostVisible,
              _capacityVertices * bytesPerVertex,
            ),
          ),
        );
      _cursor = 0;
    } else {
      _cursor = (_cursor + 1) % _ringDepth;
    }
    final length = vertexCount * bytesPerVertex;
    final buffer = _buffers[_cursor];
    if (length > 0) {
      buffer.overwrite(
        ByteData.sublistView(bytes),
        destinationOffsetInBytes: 0,
      );
      buffer.flush(offsetInBytes: 0, lengthInBytes: length);
    }
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: length);
  }
}

/// Assembles a [MeshGeometry] one vertex and triangle at a time.
///
/// The attribute setters ([normal], [texCoord], [color]) are sticky:
/// each value applies to every [addVertex] call that follows until it is
/// changed. [addVertex] returns the index of the added vertex; when
/// [deduplicate] is set, a vertex equal to one already added is merged
/// and the existing index is returned instead.
///
/// ```dart
/// final geometry = (GeometryBuilder()
///       ..color(Vector4(1, 0, 0, 1))
///       ..addVertex(Vector3(0, 0, 0))
///       ..addVertex(Vector3(1, 0, 0))
///       ..addVertex(Vector3(0, 1, 0))
///       ..addTriangle(0, 1, 2))
///     .build();
/// ```
/// {@category Geometry}
class GeometryBuilder {
  /// Creates an empty builder.
  ///
  /// When [deduplicate] is `true` (the default), [addVertex] merges a
  /// vertex equal to one already added.
  GeometryBuilder({this.deduplicate = true});

  /// Whether [addVertex] merges a vertex equal to one already added.
  final bool deduplicate;

  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _texCoords = [];
  final List<double> _colors = [];
  final List<int> _indices = [];
  final Map<String, int> _vertexLookup = {};

  Vector3 _normal = Vector3(0.0, 0.0, 1.0);
  Vector2 _texCoord = Vector2.zero();
  Vector4 _color = Vector4(1.0, 1.0, 1.0, 1.0);
  bool _normalsAuthored = false;

  /// The number of vertices added so far.
  int get vertexCount => _positions.length ~/ 3;

  /// The number of triangles added so far.
  int get triangleCount => _indices.length ~/ 3;

  /// Sets the normal applied to vertices added after this call.
  ///
  /// Authoring any normal opts the whole mesh out of generated normals;
  /// vertices added without an explicit normal keep the default
  /// `(0, 0, 1)`.
  GeometryBuilder normal(Vector3 value) {
    _normal = value.clone();
    _normalsAuthored = true;
    return this;
  }

  /// Sets the texture coordinate applied to vertices added after this
  /// call.
  GeometryBuilder texCoord(Vector2 value) {
    _texCoord = value.clone();
    return this;
  }

  /// Sets the color applied to vertices added after this call.
  GeometryBuilder color(Vector4 value) {
    _color = value.clone();
    return this;
  }

  /// Adds a vertex at [position] carrying the current sticky attributes
  /// and returns its index.
  int addVertex(Vector3 position) {
    if (deduplicate) {
      final key = _vertexKey(position);
      final existing = _vertexLookup[key];
      if (existing != null) return existing;
      final index = vertexCount;
      _vertexLookup[key] = index;
      _appendVertex(position);
      return index;
    }
    final index = vertexCount;
    _appendVertex(position);
    return index;
  }

  /// Adds a triangle referencing three previously added vertex indices.
  GeometryBuilder addTriangle(int a, int b, int c) {
    final count = vertexCount;
    for (final index in [a, b, c]) {
      if (index < 0 || index >= count) {
        throw RangeError.range(index, 0, count - 1, 'vertex index');
      }
    }
    _indices
      ..add(a)
      ..add(b)
      ..add(c);
    return this;
  }

  /// Packs the accumulated vertices into the interleaved layout.
  ///
  /// Pure and free of GPU resources; [build] uses it, and it can be
  /// exercised directly without a render context.
  Uint8List packVertices() {
    return InterleavedLayoutAdapter.packUnskinned(
      positions: Float32List.fromList(_positions),
      vertexCount: vertexCount,
      normals: _resolveNormals(),
      texCoords: Float32List.fromList(_texCoords),
      colors: Float32List.fromList(_colors),
    );
  }

  /// Builds and GPU-uploads the accumulated mesh.
  ///
  /// Pass [GeometryStorage.updatable] for [storage] to build a mesh that
  /// can be mutated in place afterwards.
  MeshGeometry build({GeometryStorage storage = GeometryStorage.fixed}) {
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList(_positions),
      normals: _resolveNormals(),
      texCoords: Float32List.fromList(_texCoords),
      colors: Float32List.fromList(_colors),
      indices: _indices.isEmpty ? null : List.of(_indices),
      storage: storage,
    );
  }

  Float32List _resolveNormals() {
    if (_normalsAuthored) return Float32List.fromList(_normals);
    return InterleavedLayoutAdapter.generateNormals(
      positions: Float32List.fromList(_positions),
      vertexCount: vertexCount,
      indices: _indices,
    );
  }

  void _appendVertex(Vector3 position) {
    _positions
      ..add(position.x)
      ..add(position.y)
      ..add(position.z);
    _normals
      ..add(_normal.x)
      ..add(_normal.y)
      ..add(_normal.z);
    _texCoords
      ..add(_texCoord.x)
      ..add(_texCoord.y);
    _colors
      ..add(_color.x)
      ..add(_color.y)
      ..add(_color.z)
      ..add(_color.w);
  }

  String _vertexKey(Vector3 position) {
    return '${position.x},${position.y},${position.z},'
        '${_normal.x},${_normal.y},${_normal.z},'
        '${_texCoord.x},${_texCoord.y},'
        '${_color.x},${_color.y},${_color.z},${_color.w}';
  }
}
