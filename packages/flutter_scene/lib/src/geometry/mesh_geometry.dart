import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';

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
  MeshGeometry.fromArrays({
    required Float32List positions,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? colors,
    List<int>? indices,
    gpu.PrimitiveType primitiveType = gpu.PrimitiveType.triangle,
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
        (primitiveType == gpu.PrimitiveType.triangle
            ? InterleavedLayoutAdapter.generateNormals(
              positions: positions,
              vertexCount: vertexCount,
              indices: indices,
            )
            : null);

    final vertexBytes = InterleavedLayoutAdapter.packUnskinned(
      positions: positions,
      vertexCount: vertexCount,
      normals: resolvedNormals,
      texCoords: texCoords,
      colors: colors,
    );

    ByteData? indexBytes;
    var indexType = gpu.IndexType.int16;
    if (indices != null) {
      final packed = InterleavedLayoutAdapter.packIndices(indices);
      indexBytes = ByteData.sublistView(packed.bytes);
      indexType = packed.is32Bit ? gpu.IndexType.int32 : gpu.IndexType.int16;
    }

    uploadVertexData(
      ByteData.sublistView(vertexBytes),
      vertexCount,
      indexBytes,
      indexType: indexType,
    );
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
  MeshGeometry build() {
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList(_positions),
      normals: _resolveNormals(),
      texCoords: Float32List.fromList(_texCoords),
      colors: Float32List.fromList(_colors),
      indices: _indices.isEmpty ? null : List.of(_indices),
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
