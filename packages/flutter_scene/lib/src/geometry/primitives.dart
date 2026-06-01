import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';

/// Vertex attribute arrays produced by a primitive generator.
///
/// A `null` attribute is left to [MeshGeometry.fromArrays] to default or
/// generate. Used internally to build the procedural primitives below.
typedef PrimitiveArrays = ({
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
///
/// Each face is emitted as its own four vertices carrying that face's flat
/// outward normal, so the box shades (and receives shadows) with crisp,
/// flat faces. The eight corner debug colors are preserved per vertex, so an
/// unlit material still shows the distinct-corner visualization.
PrimitiveArrays buildCuboidArrays(Vector3 extents) {
  final e = extents * 0.5;
  final corners = <Vector3>[
    Vector3(-e.x, -e.y, -e.z),
    Vector3(e.x, -e.y, -e.z),
    Vector3(e.x, e.y, -e.z),
    Vector3(-e.x, e.y, -e.z),
    Vector3(-e.x, -e.y, e.z),
    Vector3(e.x, -e.y, e.z),
    Vector3(e.x, e.y, e.z),
    Vector3(-e.x, e.y, e.z),
  ];
  const cornerColors = <List<double>>[
    [1, 0, 0, 1],
    [0, 1, 0, 1],
    [0, 0, 1, 1],
    [0, 0, 0, 1],
    [0, 1, 1, 1],
    [1, 0, 1, 1],
    [1, 1, 0, 1],
    [1, 1, 1, 1],
  ];
  // Each face: its four corner indices wound (a, b, c, d) so the outward
  // normal follows the engine's front-face convention, plus that normal.
  const faces = <(List<int>, List<double>)>[
    ([0, 1, 2, 3], [0, 0, -1]), // -Z
    ([1, 5, 6, 2], [1, 0, 0]), //  +X
    ([5, 4, 7, 6], [0, 0, 1]), //  +Z
    ([4, 0, 3, 7], [-1, 0, 0]), // -X
    ([3, 2, 6, 7], [0, 1, 0]), //  +Y
    ([4, 5, 1, 0], [0, -1, 0]), // -Y
  ];
  const faceUvs = <List<double>>[
    [0, 0],
    [1, 0],
    [1, 1],
    [0, 1],
  ];

  final positions = Float32List(24 * 3);
  final normals = Float32List(24 * 3);
  final texCoords = Float32List(24 * 2);
  final colors = Float32List(24 * 4);
  final indices = <int>[];
  for (var f = 0; f < faces.length; f++) {
    final (cornerIndices, normal) = faces[f];
    final base = f * 4;
    for (var i = 0; i < 4; i++) {
      final v = base + i;
      final corner = corners[cornerIndices[i]];
      positions[v * 3] = corner.x;
      positions[v * 3 + 1] = corner.y;
      positions[v * 3 + 2] = corner.z;
      normals[v * 3] = normal[0].toDouble();
      normals[v * 3 + 1] = normal[1].toDouble();
      normals[v * 3 + 2] = normal[2].toDouble();
      texCoords[v * 2] = faceUvs[i][0];
      texCoords[v * 2 + 1] = faceUvs[i][1];
      final color = cornerColors[cornerIndices[i]];
      colors[v * 4] = color[0];
      colors[v * 4 + 1] = color[1];
      colors[v * 4 + 2] = color[2];
      colors[v * 4 + 3] = color[3];
    }
    // Two triangles matching the original winding: (a, b, d) and (d, b, c).
    indices.addAll([base, base + 1, base + 3, base + 3, base + 1, base + 2]);
  }
  return (
    positions: positions,
    normals: normals,
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
