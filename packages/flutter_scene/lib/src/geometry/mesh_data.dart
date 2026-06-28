import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// An isolate-transferable snapshot of a mesh's vertex and index data.
///
/// `MeshData` separates the CPU work of building a mesh (assembling vertex
/// arrays and generating normals) from the GPU upload. Its construction is
/// pure and touches no GPU resources, so it can run on a background
/// isolate; the result is sent back and turned into a live mesh on the
/// render isolate. This keeps heavy meshing, such as remeshing a voxel
/// chunk, off the render isolate.
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
    this.colors,
    this.indices,
    this.primitiveType = gpu.PrimitiveType.triangle,
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
      colors: colors,
      indices: indices,
      primitiveType: primitiveType,
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

  /// Vertex colors (four floats each), or null to default to opaque white.
  final Float32List? colors;

  /// Triangle (or line/point) indices, or null for a non-indexed mesh.
  final List<int>? indices;

  /// How the vertices assemble into primitives when drawn.
  final gpu.PrimitiveType primitiveType;
}
