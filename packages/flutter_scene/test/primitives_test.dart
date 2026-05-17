// Covers the procedural primitive generators: cuboid, plane, and
// sphere vertex/index arrays. Pure logic, so these run without a
// Flutter GPU context; constructing the geometry classes themselves
// uploads to the GPU and is exercised by the example app.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Right-hand-rule normal of a triangle. The engine treats the side
// opposite this normal as the front face.
Vector3 triangleNormal(Float32List positions, List<int> indices, int triangle) {
  Vector3 at(int v) =>
      Vector3(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2]);
  final a = at(indices[triangle * 3]);
  final b = at(indices[triangle * 3 + 1]);
  final c = at(indices[triangle * 3 + 2]);
  return (b - a).cross(c - a);
}

void main() {
  group('buildCuboidArrays', () {
    test('produces eight colored corners and twelve triangles', () {
      final arrays = buildCuboidArrays(Vector3(2, 2, 2));
      expect(arrays.positions, hasLength(8 * 3));
      expect(arrays.colors, hasLength(8 * 4));
      expect(arrays.indices, hasLength(12 * 3));
      // The first corner sits at -extents/2 on each axis.
      expect(arrays.positions.sublist(0, 3), [-1, -1, -1]);
    });
  });

  group('buildPlaneArrays', () {
    test('a single-segment plane is one quad facing +Y', () {
      final arrays = buildPlaneArrays(
        width: 2,
        depth: 4,
        segmentsX: 1,
        segmentsZ: 1,
      );
      expect(arrays.positions, hasLength(4 * 3));
      expect(arrays.indices, hasLength(6));
      for (var v = 0; v < 4; v++) {
        expect(arrays.normals!.sublist(v * 3, v * 3 + 3), [0, 1, 0]);
        // The surface lies in the y == 0 plane.
        expect(arrays.positions[v * 3 + 1], 0);
      }
    });

    test('subdivision sets the vertex and index counts', () {
      final arrays = buildPlaneArrays(
        width: 1,
        depth: 1,
        segmentsX: 3,
        segmentsZ: 2,
      );
      expect(arrays.positions, hasLength((3 + 1) * (2 + 1) * 3));
      expect(arrays.indices, hasLength(3 * 2 * 6));
    });

    test('rejects a plane with no segments', () {
      expect(
        () => buildPlaneArrays(width: 1, depth: 1, segmentsX: 0, segmentsZ: 1),
        throwsArgumentError,
      );
    });

    test('triangles are wound so the surface faces +Y', () {
      final arrays = buildPlaneArrays(
        width: 2,
        depth: 2,
        segmentsX: 1,
        segmentsZ: 1,
      );
      // A +Y-facing surface has a -Y geometric normal.
      expect(
        triangleNormal(arrays.positions, arrays.indices, 0).y,
        lessThan(0),
      );
    });
  });

  group('buildSphereArrays', () {
    test('vertex and index counts follow the tessellation', () {
      final arrays = buildSphereArrays(radius: 1, segments: 8, rings: 4);
      expect(arrays.positions, hasLength((8 + 1) * (4 + 1) * 3));
      expect(arrays.indices, hasLength(8 * 4 * 6));
    });

    test('normals are unit length and positions lie on the radius', () {
      final arrays = buildSphereArrays(radius: 2, segments: 12, rings: 6);
      final count = arrays.positions.length ~/ 3;
      for (var v = 0; v < count; v++) {
        final nx = arrays.normals![v * 3];
        final ny = arrays.normals![v * 3 + 1];
        final nz = arrays.normals![v * 3 + 2];
        expect(math.sqrt(nx * nx + ny * ny + nz * nz), closeTo(1, 1e-5));
        final px = arrays.positions[v * 3];
        final py = arrays.positions[v * 3 + 1];
        final pz = arrays.positions[v * 3 + 2];
        expect(math.sqrt(px * px + py * py + pz * pz), closeTo(2, 1e-4));
      }
    });

    test('rejects a degenerate tessellation', () {
      expect(
        () => buildSphereArrays(radius: 1, segments: 2, rings: 4),
        throwsArgumentError,
      );
      expect(
        () => buildSphereArrays(radius: 1, segments: 8, rings: 1),
        throwsArgumentError,
      );
    });
  });
}
