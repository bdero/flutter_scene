import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:scene/physics.dart' show ConvexHullShape, TriMeshShape;

/// One named per-vertex attribute stream carried by a [MeshData], matching a
/// custom material's `attributes` entry (see `Geometry.setCustomAttribute`).
///
/// [data] is a tightly packed run of [components]-component float vectors,
/// one per vertex.
/// {@category Geometry}
class MeshAttributeData {
  MeshAttributeData(this.data, {required this.components}) {
    if (components < 1 || components > 4) {
      throw ArgumentError.value(
        components,
        'components',
        'must be between 1 and 4',
      );
    }
  }

  /// The packed attribute values, `components * vertexCount` floats.
  final Float32List data;

  /// Components per vertex, 1 through 4.
  final int components;
}

/// The canned per-triangle attributes [MeshData.unweld] can attach to its
/// output, under the names custom materials read them by.
/// {@category Geometry}
enum UnweldAttribute {
  /// `triangle_centroid` (vec3), the triangle's centroid position. The
  /// anchor for per-shard motion (fly-in, tumble about the center).
  centroid,

  /// `triangle_seed` (float), a deterministic per-triangle random in
  /// `[0, 1)`. Stable across runs and isolates.
  seed,

  /// `triangle_index` (float), the source triangle's index.
  triangleIndex,

  /// `barycentric` (vec3), `(1,0,0)`/`(0,1,0)`/`(0,0,1)` per corner. Enables
  /// single-pass fragment wireframes and edge-distance effects.
  barycentric,
}

/// One triangle of a [MeshData], yielded by [MeshData.triangles].
/// {@category Geometry}
class MeshTriangle {
  MeshTriangle(this.index, this.a, this.b, this.c, this.pa, this.pb, this.pc);

  /// The triangle's index in the mesh.
  final int index;

  /// The three vertex indices.
  final int a, b, c;

  /// The three corner positions.
  final vm.Vector3 pa, pb, pc;
}

/// Disconnected line segments (point pairs) derived from a mesh, the output
/// of [MeshData.extractEdges].
///
/// Feed [positions] to a line-list mesh for one-pixel debug rendering, or
/// construct a `LineSegmentsGeometry` for thick, camera-facing segments.
/// {@category Geometry}
class LineSegmentData {
  LineSegmentData({required this.positions, this.normals}) {
    if (positions.length % 6 != 0) {
      throw ArgumentError(
        'positions has ${positions.length} floats; expected six per segment '
        '(two xyz endpoints)',
      );
    }
    if (normals != null && normals!.length != positions.length) {
      throw ArgumentError(
        'normals must match positions in length when supplied',
      );
    }
  }

  /// Endpoint positions, six floats (two xyz points) per segment.
  final Float32List positions;

  /// Optional per-endpoint surface normals matching [positions], carried
  /// from the source mesh so callers can offset segments off the surface.
  final Float32List? normals;

  /// The number of segments.
  int get segmentCount => positions.length ~/ 6;
}

/// An isolate-transferable snapshot of a mesh's vertex and index data.
///
/// `MeshData` separates the CPU work of building a mesh (assembling vertex
/// arrays and generating normals) from the GPU upload. Its construction is
/// pure and touches no GPU resources, so it can run on a background
/// isolate; the result is sent back and turned into a live mesh on the
/// render isolate. This keeps heavy meshing, such as remeshing a voxel
/// chunk, off the render isolate.
///
/// It is also the interchange type for reading geometry back and deriving
/// new geometry from it: `Geometry.extractMeshData` produces one from a
/// loaded mesh, and the pure derivation methods ([unweld], [extractEdges],
/// [merge]) consume and produce them, so a whole derivation chain can run
/// off the render isolate.
///
/// Recipe (using `compute` from `package:flutter/foundation.dart`):
///
/// ```dart
/// // Top-level or static, runs on the background isolate.
/// MeshData buildChunk(ChunkInput input) {
///   final positions = ...; // your generator
///   final indices = ...;
///   return MeshData.build(positions: positions, indices: indices);
/// }
///
/// // On the render isolate:
/// final data = await compute(buildChunk, input);
/// final geometry = MeshGeometry.fromMeshData(data);
/// // or, to update an existing updatable mesh in place:
/// existing.applyMeshData(data);
/// ```
/// {@category Geometry}
class MeshData {
  /// Wraps already-prepared vertex arrays without generating anything.
  ///
  /// Prefer [MeshData.build], which fills in normals. Use this only when
  /// every attribute is already in hand. [vertexCount] must equal
  /// `positions.length ~/ 3`.
  MeshData({
    required this.positions,
    required this.vertexCount,
    this.normals,
    this.texCoords,
    this.texCoords1,
    this.colors,
    this.tangents,
    this.indices,
    this.primitiveType = gpu.PrimitiveType.triangle,
    this.customAttributes = const {},
  });

  /// Builds a snapshot from vertex attribute arrays, generating
  /// area-weighted normals from the faces when [normals] is absent and
  /// [primitiveType] is a triangle list. The normal generation is the work
  /// worth doing off the render isolate. The attribute-array contract
  /// matches [MeshGeometry.fromArrays].
  factory MeshData.build({
    required Float32List positions,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? texCoords1,
    Float32List? colors,
    Float32List? tangents,
    List<int>? indices,
    gpu.PrimitiveType primitiveType = gpu.PrimitiveType.triangle,
    Map<String, MeshAttributeData> customAttributes = const {},
  }) {
    if (positions.length % 3 != 0) {
      throw ArgumentError(
        'positions has ${positions.length} floats; expected a multiple of '
        'three (one vec3 per vertex)',
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
    return MeshData(
      positions: positions,
      vertexCount: vertexCount,
      normals: resolvedNormals,
      texCoords: texCoords,
      texCoords1: texCoords1,
      colors: colors,
      tangents: tangents,
      indices: indices,
      primitiveType: primitiveType,
      customAttributes: customAttributes,
    );
  }

  /// Vertex positions, three floats each.
  final Float32List positions;

  /// The number of vertices, equal to `positions.length ~/ 3`.
  final int vertexCount;

  /// Vertex normals (three floats each), or null to let the upload
  /// generate or default them.
  final Float32List? normals;

  /// Texture coordinates (two floats each), or null to default to `(0, 0)`.
  final Float32List? texCoords;

  /// Secondary texture coordinates, or null to default to `(0, 0)`.
  final Float32List? texCoords1;

  /// Vertex colors (four floats each), or null to default to opaque white.
  final Float32List? colors;

  /// Vertex tangents (four floats each), or null to derive tangent space.
  final Float32List? tangents;

  /// Triangle (or line/point) indices, or null for a non-indexed mesh.
  final List<int>? indices;

  /// How the vertices assemble into primitives when drawn.
  final gpu.PrimitiveType primitiveType;

  /// Named custom per-vertex attribute streams, forwarded to
  /// `Geometry.setCustomAttribute` on upload.
  final Map<String, MeshAttributeData> customAttributes;

  /// The number of triangles (indexed or not). Zero for non-triangle
  /// primitive types.
  int get triangleCount => primitiveType == gpu.PrimitiveType.triangle
      ? (indices?.length ?? vertexCount) ~/ 3
      : 0;

  /// Iterates the mesh's triangles with their corner indices and positions.
  ///
  /// The yielded positions are copies; mutating them does not touch the
  /// snapshot.
  Iterable<MeshTriangle> get triangles sync* {
    _requireTriangles('triangles');
    final count = triangleCount;
    for (var t = 0; t < count; t++) {
      final a = _cornerIndex(t * 3);
      final b = _cornerIndex(t * 3 + 1);
      final c = _cornerIndex(t * 3 + 2);
      yield MeshTriangle(t, a, b, c, _position(a), _position(b), _position(c));
    }
  }

  /// This mesh placed by [transform].
  ///
  /// Positions move as points. [normals] are carried by the inverse
  /// transpose, so a non-uniform scale leaves them perpendicular to the
  /// surface, and [tangents] by [transform] itself; both are renormalized.
  /// Every other attribute carries through untouched.
  ///
  /// A mirroring [transform] reverses orientation, so it flips the tangent
  /// handedness and reverses triangle winding to match. The renderer flips
  /// winding per node for a mirrored node transform, which cannot help once
  /// the mirror lives in the vertices. An unindexed triangle list comes back
  /// indexed, since that is where its winding lives.
  MeshData transformed(vm.Matrix4 transform) {
    final m = transform.storage;
    final outPositions = Float32List(vertexCount * 3);
    for (var v = 0; v < vertexCount; v++) {
      final i = v * 3;
      final x = positions[i];
      final y = positions[i + 1];
      final z = positions[i + 2];
      outPositions[i] = m[0] * x + m[4] * y + m[8] * z + m[12];
      outPositions[i + 1] = m[1] * x + m[5] * y + m[9] * z + m[13];
      outPositions[i + 2] = m[2] * x + m[6] * y + m[10] * z + m[14];
    }

    final linear = transform.getRotation();
    final mirrored = linear.determinant() < 0;

    Float32List? outNormals;
    final srcNormals = normals;
    if (srcNormals != null) {
      // A singular linear part has no inverse transpose; carrying normals
      // through unchanged beats emitting NaNs.
      final normalMatrix = vm.Matrix3.copy(linear);
      if (normalMatrix.invert() == 0.0) {
        normalMatrix.setFrom(linear);
      } else {
        normalMatrix.transpose();
      }
      outNormals = _transformVectors(srcNormals, normalMatrix, 3);
    }

    Float32List? outTangents;
    final srcTangents = tangents;
    if (srcTangents != null) {
      outTangents = _transformVectors(srcTangents, linear, 4);
      if (mirrored) {
        for (var v = 0; v < vertexCount; v++) {
          outTangents[v * 4 + 3] = -outTangents[v * 4 + 3];
        }
      }
    }

    return MeshData(
      positions: outPositions,
      vertexCount: vertexCount,
      normals: outNormals,
      texCoords: texCoords,
      texCoords1: texCoords1,
      colors: colors,
      tangents: outTangents,
      indices: mirrored ? _reversedWinding() : indices,
      primitiveType: primitiveType,
      customAttributes: customAttributes,
    );
  }

  /// This mesh's triangle corners with each triangle's last two swapped, or
  /// [indices] unchanged when winding does not apply. Synthesizes the corners
  /// for an unindexed list, which has no other place to carry winding.
  List<int>? _reversedWinding() {
    if (primitiveType != gpu.PrimitiveType.triangle) return indices;
    final source = indices;
    final cornerCount = source?.length ?? vertexCount;
    // A partial triangle has no winding to preserve; leave it as it came.
    if (cornerCount == 0 || cornerCount % 3 != 0) return indices;
    final out = List<int>.filled(cornerCount, 0);
    for (var t = 0; t < cornerCount; t += 3) {
      out[t] = source?[t] ?? t;
      out[t + 1] = source?[t + 2] ?? t + 2;
      out[t + 2] = source?[t + 1] ?? t + 1;
    }
    return out;
  }

  /// A collision triangle mesh over this mesh's triangles.
  ///
  /// The shape holds its own copy of the positions and indices, so the
  /// snapshot can be discarded afterwards. Triangle meshes are hollow and
  /// carry no volume, so they collide as static environment geometry; use
  /// [toConvexHullShape] for a dynamic body.
  ///
  /// Throws a [StateError] when this snapshot is not a triangle list or
  /// has no triangles.
  TriMeshShape toTriMeshShape() {
    _requireTriangles('toTriMeshShape');
    final count = triangleCount;
    if (count == 0) {
      throw StateError('toTriMeshShape requires at least one triangle');
    }
    final outIndices = Uint32List(count * 3);
    for (var corner = 0; corner < outIndices.length; corner++) {
      outIndices[corner] = _cornerIndex(corner);
    }
    return TriMeshShape(
      vertices: Float32List.fromList(positions),
      indices: outIndices,
    );
  }

  /// A collision convex hull enclosing this mesh's vertices.
  ///
  /// The backend computes the hull from the positions, so concave detail is
  /// filled in. Unlike [toTriMeshShape] the result is solid and works on a
  /// dynamic body.
  ConvexHullShape toConvexHullShape() {
    if (vertexCount == 0) {
      throw StateError('toConvexHullShape requires at least one vertex');
    }
    return ConvexHullShape(points: Float32List.fromList(positions));
  }

  Float32List _transformVectors(
    Float32List source,
    vm.Matrix3 matrix,
    int stride,
  ) {
    final m = matrix.storage;
    final out = Float32List.fromList(source);
    for (var v = 0; v < vertexCount; v++) {
      final i = v * stride;
      final x = source[i];
      final y = source[i + 1];
      final z = source[i + 2];
      var nx = m[0] * x + m[3] * y + m[6] * z;
      var ny = m[1] * x + m[4] * y + m[7] * z;
      var nz = m[2] * x + m[5] * y + m[8] * z;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length > 0) {
        nx /= length;
        ny /= length;
        nz /= length;
      }
      out[i] = nx;
      out[i + 1] = ny;
      out[i + 2] = nz;
    }
    return out;
  }

  /// A flat-shaded triangle soup derived from this mesh.
  ///
  /// Every triangle gets three unique vertices carrying its face normal
  /// (oriented to agree with the source vertex normals when present), with
  /// texture coordinates, colors, and custom attributes carried through
  /// per corner. [attributes] attaches canned per-triangle streams under
  /// the names in [UnweldAttribute], ready for a custom material's
  /// `attributes` list.
  ///
  /// [keepVertexNormals] carries each corner's source vertex normal through
  /// instead of the face normal, so the unwelded mesh still shades smooth
  /// (needed when the same geometry has to render as an ordinary solid, not
  /// just a shattered/faceted one). Has no effect when this mesh has no
  /// source normals.
  ///
  /// Triples the vertex data of an indexed mesh; run it on a background
  /// isolate for large inputs (the whole derivation is pure CPU work).
  MeshData unweld({
    Set<UnweldAttribute> attributes = const {},
    bool keepVertexNormals = false,
  }) {
    _requireTriangles('unweld');
    final count = triangleCount;
    final outCount = count * 3;

    final srcTexCoords = texCoords;
    final srcTexCoords1 = texCoords1;
    final srcColors = colors;
    final srcTangents = tangents;
    final outPositions = Float32List(outCount * 3);
    final outNormals = Float32List(outCount * 3);
    final outTexCoords = srcTexCoords == null
        ? null
        : Float32List(outCount * 2);
    final outTexCoords1 = srcTexCoords1 == null
        ? null
        : Float32List(outCount * 2);
    final outColors = srcColors == null ? null : Float32List(outCount * 4);
    final outTangents = srcTangents == null ? null : Float32List(outCount * 4);
    final outCustom = <String, MeshAttributeData>{
      for (final entry in customAttributes.entries)
        entry.key: MeshAttributeData(
          Float32List(outCount * entry.value.components),
          components: entry.value.components,
        ),
    };

    final wantCentroid = attributes.contains(UnweldAttribute.centroid);
    final wantSeed = attributes.contains(UnweldAttribute.seed);
    final wantIndex = attributes.contains(UnweldAttribute.triangleIndex);
    final wantBarycentric = attributes.contains(UnweldAttribute.barycentric);
    final centroids = wantCentroid ? Float32List(outCount * 3) : null;
    final seeds = wantSeed ? Float32List(outCount) : null;
    final triIndices = wantIndex ? Float32List(outCount) : null;
    final barycentrics = wantBarycentric ? Float32List(outCount * 3) : null;

    final srcNormals = normals;
    var seedState = 0x9e3779b9;
    for (var t = 0; t < count; t++) {
      final i0 = _cornerIndex(t * 3);
      final i1 = _cornerIndex(t * 3 + 1);
      final i2 = _cornerIndex(t * 3 + 2);

      // Face normal from the winding, sign-checked against the source
      // vertex normals so mirrored or inconsistently wound data still
      // points outward.
      final ax = positions[i0 * 3],
          ay = positions[i0 * 3 + 1],
          az = positions[i0 * 3 + 2];
      final e1x = positions[i1 * 3] - ax,
          e1y = positions[i1 * 3 + 1] - ay,
          e1z = positions[i1 * 3 + 2] - az;
      final e2x = positions[i2 * 3] - ax,
          e2y = positions[i2 * 3 + 1] - ay,
          e2z = positions[i2 * 3 + 2] - az;
      var nx = e1y * e2z - e1z * e2y;
      var ny = e1z * e2x - e1x * e2z;
      var nz = e1x * e2y - e1y * e2x;
      final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (nLen > 0) {
        nx /= nLen;
        ny /= nLen;
        nz /= nLen;
      }
      if (srcNormals != null) {
        final sx = srcNormals[i0 * 3] + srcNormals[i1 * 3] + srcNormals[i2 * 3];
        final sy =
            srcNormals[i0 * 3 + 1] +
            srcNormals[i1 * 3 + 1] +
            srcNormals[i2 * 3 + 1];
        final sz =
            srcNormals[i0 * 3 + 2] +
            srcNormals[i1 * 3 + 2] +
            srcNormals[i2 * 3 + 2];
        if (nx * sx + ny * sy + nz * sz < 0) {
          nx = -nx;
          ny = -ny;
          nz = -nz;
        }
      }

      final cx =
          (positions[i0 * 3] + positions[i1 * 3] + positions[i2 * 3]) / 3;
      final cy =
          (positions[i0 * 3 + 1] +
              positions[i1 * 3 + 1] +
              positions[i2 * 3 + 1]) /
          3;
      final cz =
          (positions[i0 * 3 + 2] +
              positions[i1 * 3 + 2] +
              positions[i2 * 3 + 2]) /
          3;

      // Deterministic per-triangle random in [0, 1).
      seedState = 0x1fffffff & (seedState * 1103515245 + 12345);
      final seed = (seedState & 0xffff) / 0x10000;

      for (var corner = 0; corner < 3; corner++) {
        final src = corner == 0 ? i0 : (corner == 1 ? i1 : i2);
        final v = t * 3 + corner;
        outPositions[v * 3] = positions[src * 3];
        outPositions[v * 3 + 1] = positions[src * 3 + 1];
        outPositions[v * 3 + 2] = positions[src * 3 + 2];
        if (keepVertexNormals && srcNormals != null) {
          outNormals[v * 3] = srcNormals[src * 3];
          outNormals[v * 3 + 1] = srcNormals[src * 3 + 1];
          outNormals[v * 3 + 2] = srcNormals[src * 3 + 2];
        } else {
          outNormals[v * 3] = nx;
          outNormals[v * 3 + 1] = ny;
          outNormals[v * 3 + 2] = nz;
        }
        if (outTexCoords != null) {
          outTexCoords[v * 2] = srcTexCoords![src * 2];
          outTexCoords[v * 2 + 1] = srcTexCoords[src * 2 + 1];
        }
        if (outTexCoords1 != null) {
          outTexCoords1[v * 2] = srcTexCoords1![src * 2];
          outTexCoords1[v * 2 + 1] = srcTexCoords1[src * 2 + 1];
        }
        if (outColors != null) {
          for (var i = 0; i < 4; i++) {
            outColors[v * 4 + i] = srcColors![src * 4 + i];
          }
        }
        if (outTangents != null) {
          for (var i = 0; i < 4; i++) {
            outTangents[v * 4 + i] = srcTangents![src * 4 + i];
          }
        }
        for (final entry in customAttributes.entries) {
          final components = entry.value.components;
          final srcData = entry.value.data;
          final dstData = outCustom[entry.key]!.data;
          for (var i = 0; i < components; i++) {
            dstData[v * components + i] = srcData[src * components + i];
          }
        }
        if (centroids != null) {
          centroids[v * 3] = cx;
          centroids[v * 3 + 1] = cy;
          centroids[v * 3 + 2] = cz;
        }
        if (seeds != null) seeds[v] = seed;
        if (triIndices != null) triIndices[v] = t.toDouble();
        if (barycentrics != null) {
          barycentrics[v * 3 + corner] = 1.0;
        }
      }
    }

    if (centroids != null) {
      outCustom['triangle_centroid'] = MeshAttributeData(
        centroids,
        components: 3,
      );
    }
    if (seeds != null) {
      outCustom['triangle_seed'] = MeshAttributeData(seeds, components: 1);
    }
    if (triIndices != null) {
      outCustom['triangle_index'] = MeshAttributeData(
        triIndices,
        components: 1,
      );
    }
    if (barycentrics != null) {
      outCustom['barycentric'] = MeshAttributeData(barycentrics, components: 3);
    }

    return MeshData(
      positions: outPositions,
      vertexCount: outCount,
      normals: outNormals,
      texCoords: outTexCoords,
      texCoords1: outTexCoords1,
      colors: outColors,
      tangents: outTangents,
      primitiveType: gpu.PrimitiveType.triangle,
      customAttributes: outCustom,
    );
  }

  /// The mesh's unique undirected edges as disconnected line segments.
  ///
  /// With a null [creaseAngleDegrees] every edge is kept (a full
  /// wireframe). With a value, an edge is kept only when its two adjacent
  /// faces meet at more than that angle (a feature-edge wireframe);
  /// boundary edges (a single adjacent face) are always kept.
  ///
  /// The output carries per-endpoint source normals when this mesh has
  /// normals, so callers can offset the segments off the surface.
  LineSegmentData extractEdges({double? creaseAngleDegrees}) {
    _requireTriangles('extractEdges');
    final count = triangleCount;

    // Unique undirected edges, keyed lo * vertexCount + hi (safe well past
    // any practical vertex count). Each edge tracks up to two face normals
    // for the crease filter.
    final edgeSlot = <int, int>{};
    final edgeA = <int>[];
    final edgeB = <int>[];
    final faceNx = <double>[];
    final faceNy = <double>[];
    final faceNz = <double>[];
    // Per edge: first face index, second face index (or -1).
    final firstFace = <int>[];
    final secondFace = <int>[];

    for (var t = 0; t < count; t++) {
      final i0 = _cornerIndex(t * 3);
      final i1 = _cornerIndex(t * 3 + 1);
      final i2 = _cornerIndex(t * 3 + 2);

      if (creaseAngleDegrees != null) {
        final ax = positions[i0 * 3],
            ay = positions[i0 * 3 + 1],
            az = positions[i0 * 3 + 2];
        final e1x = positions[i1 * 3] - ax,
            e1y = positions[i1 * 3 + 1] - ay,
            e1z = positions[i1 * 3 + 2] - az;
        final e2x = positions[i2 * 3] - ax,
            e2y = positions[i2 * 3 + 1] - ay,
            e2z = positions[i2 * 3 + 2] - az;
        var nx = e1y * e2z - e1z * e2y;
        var ny = e1z * e2x - e1x * e2z;
        var nz = e1x * e2y - e1y * e2x;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len > 0) {
          nx /= len;
          ny /= len;
          nz /= len;
        }
        faceNx.add(nx);
        faceNy.add(ny);
        faceNz.add(nz);
      }

      void addEdge(int a, int b) {
        final lo = math.min(a, b);
        final hi = math.max(a, b);
        final key = lo * vertexCount + hi;
        final slot = edgeSlot[key];
        if (slot == null) {
          edgeSlot[key] = edgeA.length;
          edgeA.add(lo);
          edgeB.add(hi);
          firstFace.add(t);
          secondFace.add(-1);
        } else if (secondFace[slot] == -1) {
          secondFace[slot] = t;
        }
      }

      addEdge(i0, i1);
      addEdge(i1, i2);
      addEdge(i2, i0);
    }

    // cos of the crease angle; adjacent faces whose normals agree more than
    // this are coplanar enough to drop.
    final creaseCos = creaseAngleDegrees == null
        ? null
        : math.cos(creaseAngleDegrees * math.pi / 180.0);

    final srcNormals = normals;
    final outPositions = <double>[];
    final outNormals = srcNormals == null ? null : <double>[];
    for (var e = 0; e < edgeA.length; e++) {
      if (creaseCos != null && secondFace[e] != -1) {
        final f0 = firstFace[e];
        final f1 = secondFace[e];
        final dot =
            faceNx[f0] * faceNx[f1] +
            faceNy[f0] * faceNy[f1] +
            faceNz[f0] * faceNz[f1];
        if (dot > creaseCos) continue;
      }
      for (final v in [edgeA[e], edgeB[e]]) {
        outPositions
          ..add(positions[v * 3])
          ..add(positions[v * 3 + 1])
          ..add(positions[v * 3 + 2]);
        outNormals
          ?..add(srcNormals![v * 3])
          ..add(srcNormals[v * 3 + 1])
          ..add(srcNormals[v * 3 + 2]);
      }
    }

    return LineSegmentData(
      positions: Float32List.fromList(outPositions),
      normals: outNormals == null ? null : Float32List.fromList(outNormals),
    );
  }

  /// Concatenates [parts] into one snapshot, rebasing indices.
  ///
  /// Every part must share the primitive type, the presence of each
  /// optional attribute, and the same custom attribute names and widths.
  /// When some parts are indexed and others are not, sequential indices
  /// are synthesized for the unindexed ones.
  static MeshData merge(List<MeshData> parts) {
    if (parts.isEmpty) {
      throw ArgumentError('merge requires at least one MeshData');
    }
    if (parts.length == 1) return parts.first;
    final first = parts.first;
    for (final part in parts.skip(1)) {
      if (part.primitiveType != first.primitiveType ||
          (part.normals == null) != (first.normals == null) ||
          (part.texCoords == null) != (first.texCoords == null) ||
          (part.texCoords1 == null) != (first.texCoords1 == null) ||
          (part.colors == null) != (first.colors == null) ||
          (part.tangents == null) != (first.tangents == null)) {
        throw ArgumentError(
          'merge requires matching primitive types and attribute sets',
        );
      }
      if (part.customAttributes.length != first.customAttributes.length ||
          first.customAttributes.entries.any(
            (e) =>
                part.customAttributes[e.key]?.components != e.value.components,
          )) {
        throw ArgumentError(
          'merge requires matching custom attribute names and widths',
        );
      }
    }

    final anyIndexed = parts.any((p) => p.indices != null);
    var vertexCount = 0;
    var indexCount = 0;
    for (final part in parts) {
      vertexCount += part.vertexCount;
      if (anyIndexed) {
        indexCount += part.indices?.length ?? part.vertexCount;
      }
    }

    final positions = Float32List(vertexCount * 3);
    final normals = first.normals == null ? null : Float32List(vertexCount * 3);
    final texCoords = first.texCoords == null
        ? null
        : Float32List(vertexCount * 2);
    final texCoords1 = first.texCoords1 == null
        ? null
        : Float32List(vertexCount * 2);
    final colors = first.colors == null ? null : Float32List(vertexCount * 4);
    final tangents = first.tangents == null
        ? null
        : Float32List(vertexCount * 4);
    final custom = <String, MeshAttributeData>{
      for (final entry in first.customAttributes.entries)
        entry.key: MeshAttributeData(
          Float32List(vertexCount * entry.value.components),
          components: entry.value.components,
        ),
    };
    final indices = anyIndexed ? List<int>.filled(indexCount, 0) : null;

    var vertexBase = 0;
    var indexBase = 0;
    for (final part in parts) {
      positions.setRange(
        vertexBase * 3,
        vertexBase * 3 + part.positions.length,
        part.positions,
      );
      normals?.setRange(
        vertexBase * 3,
        vertexBase * 3 + part.normals!.length,
        part.normals!,
      );
      texCoords?.setRange(
        vertexBase * 2,
        vertexBase * 2 + part.texCoords!.length,
        part.texCoords!,
      );
      texCoords1?.setRange(
        vertexBase * 2,
        vertexBase * 2 + part.texCoords1!.length,
        part.texCoords1!,
      );
      colors?.setRange(
        vertexBase * 4,
        vertexBase * 4 + part.colors!.length,
        part.colors!,
      );
      tangents?.setRange(
        vertexBase * 4,
        vertexBase * 4 + part.tangents!.length,
        part.tangents!,
      );
      for (final entry in part.customAttributes.entries) {
        final components = entry.value.components;
        custom[entry.key]!.data.setRange(
          vertexBase * components,
          vertexBase * components + entry.value.data.length,
          entry.value.data,
        );
      }
      if (indices != null) {
        final partIndices = part.indices;
        final partCount = partIndices?.length ?? part.vertexCount;
        for (var i = 0; i < partCount; i++) {
          indices[indexBase + i] = (partIndices?[i] ?? i) + vertexBase;
        }
        indexBase += partCount;
      }
      vertexBase += part.vertexCount;
    }

    return MeshData(
      positions: positions,
      vertexCount: vertexCount,
      normals: normals,
      texCoords: texCoords,
      texCoords1: texCoords1,
      colors: colors,
      tangents: tangents,
      indices: indices,
      primitiveType: first.primitiveType,
      customAttributes: custom,
    );
  }

  int _cornerIndex(int corner) => indices?[corner] ?? corner;

  vm.Vector3 _position(int vertex) => vm.Vector3(
    positions[vertex * 3],
    positions[vertex * 3 + 1],
    positions[vertex * 3 + 2],
  );

  void _requireTriangles(String operation) {
    if (primitiveType != gpu.PrimitiveType.triangle) {
      throw StateError('$operation requires a triangle-list MeshData');
    }
    final cornerCount = indices?.length ?? vertexCount;
    if (cornerCount % 3 != 0) {
      throw StateError(
        '$operation requires a whole number of triangles '
        '($cornerCount corner indices)',
      );
    }
  }
}
