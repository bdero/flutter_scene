import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';

/// Vertex attribute arrays produced by a primitive generator.
///
/// A `null` attribute is left to [MeshGeometry.fromArrays] to default or
/// generate. Used internally to build the procedural primitives below.
typedef PrimitiveArrays =
    ({
      Float32List positions,
      Float32List? normals,
      Float32List? texCoords,
      Float32List? colors,
      List<int> indices,
    });

/// An axis-aligned box geometry spanning `-extents/2` to `+extents/2` on
/// each axis.
///
/// Useful as a quick placeholder or for debugging. Each corner carries a
/// distinct vertex color, which can be visualized with an unlit material.
class CuboidGeometry extends MeshGeometry {
  /// Builds a cuboid sized to [extents].
  factory CuboidGeometry(Vector3 extents) =>
      CuboidGeometry._(buildCuboidArrays(extents));

  CuboidGeometry._(PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        colors: arrays.colors,
        indices: arrays.indices,
      );
}

/// A flat rectangular grid in the XZ plane, centered on the origin, with
/// its surface facing `+Y`.
///
/// [width] spans X and [depth] spans Z. [segmentsX] and [segmentsZ] set
/// the number of grid cells along each axis; subdividing is useful when
/// the surface will be deformed or lit by per-vertex data.
class PlaneGeometry extends MeshGeometry {
  /// Builds a plane of the given size and subdivision.
  factory PlaneGeometry({
    double width = 1.0,
    double depth = 1.0,
    int segmentsX = 1,
    int segmentsZ = 1,
  }) {
    return PlaneGeometry._(
      buildPlaneArrays(
        width: width,
        depth: depth,
        segmentsX: segmentsX,
        segmentsZ: segmentsZ,
      ),
    );
  }

  PlaneGeometry._(PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );
}

/// A UV sphere centered on the origin.
///
/// [segments] is the number of divisions around the equator and
/// [rings] the number of divisions from pole to pole. Vertex normals
/// point radially outward and texture coordinates wrap longitude in `u`
/// and latitude in `v`.
class SphereGeometry extends MeshGeometry {
  /// Builds a sphere of the given [radius] and tessellation.
  factory SphereGeometry({
    double radius = 0.5,
    int segments = 32,
    int rings = 16,
  }) {
    return SphereGeometry._(
      buildSphereArrays(radius: radius, segments: segments, rings: rings),
    );
  }

  SphereGeometry._(PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );
}

/// Generates the vertex arrays for a [CuboidGeometry] sized to [extents].
PrimitiveArrays buildCuboidArrays(Vector3 extents) {
  final e = extents * 0.5;
  final positions = Float32List.fromList(<double>[
    -e.x, -e.y, -e.z, //
    e.x, -e.y, -e.z, //
    e.x, e.y, -e.z, //
    -e.x, e.y, -e.z, //
    -e.x, -e.y, e.z, //
    e.x, -e.y, e.z, //
    e.x, e.y, e.z, //
    -e.x, e.y, e.z, //
  ]);
  final texCoords = Float32List.fromList(<double>[
    0, 0, //
    1, 0, //
    1, 1, //
    0, 1, //
    0, 0, //
    1, 0, //
    1, 1, //
    0, 1, //
  ]);
  final colors = Float32List.fromList(<double>[
    1, 0, 0, 1, //
    0, 1, 0, 1, //
    0, 0, 1, 1, //
    0, 0, 0, 1, //
    0, 1, 1, 1, //
    1, 0, 1, 1, //
    1, 1, 0, 1, //
    1, 1, 1, 1, //
  ]);
  const indices = <int>[
    0, 1, 3, 3, 1, 2, //
    1, 5, 2, 2, 5, 6, //
    5, 4, 6, 6, 4, 7, //
    4, 0, 7, 7, 0, 3, //
    3, 2, 7, 7, 2, 6, //
    4, 5, 0, 0, 5, 1, //
  ];
  return (
    positions: positions,
    normals: null,
    texCoords: texCoords,
    colors: colors,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [PlaneGeometry].
PrimitiveArrays buildPlaneArrays({
  required double width,
  required double depth,
  required int segmentsX,
  required int segmentsZ,
}) {
  if (segmentsX < 1 || segmentsZ < 1) {
    throw ArgumentError('A plane needs at least one segment on each axis');
  }
  final columns = segmentsX + 1;
  final rows = segmentsZ + 1;
  final vertexCount = columns * rows;
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);
  final texCoords = Float32List(vertexCount * 2);

  for (var r = 0; r < rows; r++) {
    final z = -depth / 2 + depth * r / segmentsZ;
    for (var c = 0; c < columns; c++) {
      final x = -width / 2 + width * c / segmentsX;
      final v = r * columns + c;
      positions[v * 3] = x;
      positions[v * 3 + 1] = 0.0;
      positions[v * 3 + 2] = z;
      normals[v * 3 + 1] = 1.0;
      texCoords[v * 2] = c / segmentsX;
      texCoords[v * 2 + 1] = r / segmentsZ;
    }
  }

  final indices = <int>[];
  for (var r = 0; r < segmentsZ; r++) {
    for (var c = 0; c < segmentsX; c++) {
      final v00 = r * columns + c;
      final v10 = v00 + 1;
      final v01 = v00 + columns;
      final v11 = v01 + 1;
      // Wound so the lit surface faces +Y, toward a camera above.
      indices
        ..addAll([v00, v10, v01])
        ..addAll([v10, v11, v01]);
    }
  }

  return (
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [SphereGeometry].
PrimitiveArrays buildSphereArrays({
  required double radius,
  required int segments,
  required int rings,
}) {
  if (segments < 3) {
    throw ArgumentError('A sphere needs at least three segments');
  }
  if (rings < 2) {
    throw ArgumentError('A sphere needs at least two rings');
  }
  final columns = segments + 1;
  final rowCount = rings + 1;
  final vertexCount = columns * rowCount;
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);
  final texCoords = Float32List(vertexCount * 2);

  for (var r = 0; r < rowCount; r++) {
    final latitude = math.pi * r / rings;
    final sinLat = math.sin(latitude);
    final cosLat = math.cos(latitude);
    for (var s = 0; s < columns; s++) {
      final longitude = 2 * math.pi * s / segments;
      final sinLon = math.sin(longitude);
      final cosLon = math.cos(longitude);
      final nx = sinLat * cosLon;
      final ny = cosLat;
      final nz = sinLat * sinLon;
      final v = r * columns + s;
      positions[v * 3] = radius * nx;
      positions[v * 3 + 1] = radius * ny;
      positions[v * 3 + 2] = radius * nz;
      normals[v * 3] = nx;
      normals[v * 3 + 1] = ny;
      normals[v * 3 + 2] = nz;
      texCoords[v * 2] = s / segments;
      texCoords[v * 2 + 1] = r / rings;
    }
  }

  final indices = <int>[];
  for (var r = 0; r < rings; r++) {
    for (var s = 0; s < segments; s++) {
      final a = r * columns + s;
      final b = a + 1;
      final c = a + columns;
      final d = c + 1;
      // Wound counter-clockwise as seen from outside the sphere.
      indices
        ..addAll([a, c, b])
        ..addAll([b, c, d]);
    }
  }

  return (
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: null,
    indices: indices,
  );
}
