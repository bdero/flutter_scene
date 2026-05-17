// Covers the swept-geometry generators. Pure logic, no GPU context;
// the RibbonGeometry class itself uploads to the GPU and is exercised
// by the example app.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/swept_geometry.dart';
import 'package:flutter_scene/src/scene_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

double _distance(Float32List positions, int a, int b) {
  final dx = positions[a * 3] - positions[b * 3];
  final dy = positions[a * 3 + 1] - positions[b * 3 + 1];
  final dz = positions[a * 3 + 2] - positions[b * 3 + 2];
  return math.sqrt(dx * dx + dy * dy + dz * dz);
}

// Right-hand-rule normal of a triangle. The engine treats the side
// opposite this normal as the front face.
Vector3 _triangleNormal(
  Float32List positions,
  List<int> indices,
  int triangle,
) {
  Vector3 at(int v) =>
      Vector3(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2]);
  final a = at(indices[triangle * 3]);
  final b = at(indices[triangle * 3 + 1]);
  final c = at(indices[triangle * 3 + 2]);
  return (b - a).cross(c - a);
}

void main() {
  group('evenlySpacedFrames', () {
    test('returns the requested count spaced by arc length', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(10, 0, 0)]);
      final frames = evenlySpacedFrames(path, 5);
      expect(frames, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(frames[i].position.x, closeTo(i * 2.5, 1e-5));
      }
    });
  });

  group('stitchRings', () {
    test('connects two rings into a quad', () {
      final accumulator =
          MeshAccumulator()
            ..addVertex(Vector3(0, 0, 0), Vector3(0, 1, 0), 0, 0)
            ..addVertex(Vector3(1, 0, 0), Vector3(0, 1, 0), 1, 0)
            ..addVertex(Vector3(0, 0, 1), Vector3(0, 1, 0), 0, 1)
            ..addVertex(Vector3(1, 0, 1), Vector3(0, 1, 0), 1, 1);
      stitchRings(accumulator, [0, 2], 2);
      // One quad is two triangles.
      expect(accumulator.toArrays().indices, hasLength(6));
    });
  });

  group('buildRibbonArrays', () {
    test('rejects fewer than two stations', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(1, 0, 0)]);
      expect(
        () => buildRibbonArrays(
          path,
          width: 1,
          stations: 1,
          alignment: RibbonAlignment.ground,
          up: Vector3(0, 1, 0),
        ),
        throwsArgumentError,
      );
    });

    test('emits two vertices per station and a quad per gap', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(10, 0, 0)]);
      final arrays = buildRibbonArrays(
        path,
        width: 2,
        stations: 4,
        alignment: RibbonAlignment.ground,
        up: Vector3(0, 1, 0),
      );
      expect(arrays.positions, hasLength(4 * 2 * 3));
      expect(arrays.indices, hasLength(3 * 6));
    });

    test('ground alignment makes every normal point up', () {
      final path = PolylinePath([
        Vector3(0, 0, 0),
        Vector3(4, 0, 0),
        Vector3(8, 0, 4),
      ]);
      final arrays = buildRibbonArrays(
        path,
        width: 1,
        stations: 6,
        alignment: RibbonAlignment.ground,
        up: Vector3(0, 1, 0),
      );
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        expect(arrays.normals[v * 3], closeTo(0, 1e-6));
        expect(arrays.normals[v * 3 + 1], closeTo(1, 1e-6));
        expect(arrays.normals[v * 3 + 2], closeTo(0, 1e-6));
      }
    });

    test('the two edge vertices of a station are width apart', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(10, 0, 0)]);
      final arrays = buildRibbonArrays(
        path,
        width: 3,
        stations: 2,
        alignment: RibbonAlignment.ground,
        up: Vector3(0, 1, 0),
      );
      expect(_distance(arrays.positions, 0, 1), closeTo(3, 1e-5));
    });

    test('a ground ribbon is wound so the surface faces +Y', () {
      final arrays = buildRibbonArrays(
        PolylinePath([Vector3(0, 0, 0), Vector3(10, 0, 0)]),
        width: 2,
        stations: 2,
        alignment: RibbonAlignment.ground,
        up: Vector3(0, 1, 0),
      );
      // A +Y-facing surface has a -Y geometric normal.
      expect(
        _triangleNormal(arrays.positions, arrays.indices, 0).y,
        lessThan(0),
      );
    });
  });

  group('buildTubeArrays', () {
    SweptArrays tube({required bool caps}) => buildTubeArrays(
      PolylinePath([Vector3(0, 0, 0), Vector3(10, 0, 0)]),
      radius: 2,
      radialSegments: 8,
      stations: 3,
      caps: caps,
    );

    test('rejects a degenerate tessellation', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(1, 0, 0)]);
      expect(
        () => buildTubeArrays(
          path,
          radius: 1,
          radialSegments: 2,
          stations: 3,
          caps: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildTubeArrays(
          path,
          radius: 1,
          radialSegments: 8,
          stations: 1,
          caps: false,
        ),
        throwsArgumentError,
      );
    });

    test('side surface vertex and index counts follow the tessellation', () {
      final arrays = tube(caps: false);
      // stations * (radialSegments + 1) vertices.
      expect(arrays.positions, hasLength(3 * 9 * 3));
      // (stations - 1) * radialSegments quads.
      expect(arrays.indices, hasLength(2 * 8 * 6));
    });

    test('caps add a fan at each end', () {
      final withCaps = tube(caps: true);
      // Side surface plus a center and ring per cap.
      expect(withCaps.positions, hasLength((3 * 9 + 2 * 9) * 3));
      expect(withCaps.indices, hasLength(2 * 8 * 6 + 2 * 8 * 3));
    });

    test('side vertices sit at the radius from the centerline', () {
      final arrays = tube(caps: false);
      final count = arrays.positions.length ~/ 3;
      for (var v = 0; v < count; v++) {
        final y = arrays.positions[v * 3 + 1];
        final z = arrays.positions[v * 3 + 2];
        expect(math.sqrt(y * y + z * z), closeTo(2, 1e-5));
      }
    });

    test('every normal is unit length', () {
      final arrays = tube(caps: true);
      final count = arrays.normals.length ~/ 3;
      for (var v = 0; v < count; v++) {
        final nx = arrays.normals[v * 3];
        final ny = arrays.normals[v * 3 + 1];
        final nz = arrays.normals[v * 3 + 2];
        expect(math.sqrt(nx * nx + ny * ny + nz * nz), closeTo(1, 1e-5));
      }
    });
  });

  group('buildExtrudeArrays', () {
    final square = [
      Vector2(-1, -1),
      Vector2(1, -1),
      Vector2(1, 1),
      Vector2(-1, 1),
    ];

    SweptArrays extrude({required bool caps}) => buildExtrudeArrays(
      PolylinePath([Vector3(0, 0, 0), Vector3(10, 0, 0)]),
      profile: square,
      stations: 3,
      caps: caps,
    );

    test('rejects a profile with fewer than three points', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(1, 0, 0)]);
      expect(
        () => buildExtrudeArrays(
          path,
          profile: [Vector2(0, 0), Vector2(1, 0)],
          stations: 2,
          caps: false,
        ),
        throwsArgumentError,
      );
    });

    test('rejects fewer than two stations', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(1, 0, 0)]);
      expect(
        () =>
            buildExtrudeArrays(path, profile: square, stations: 1, caps: false),
        throwsArgumentError,
      );
    });

    test('side surface vertex and index counts follow the profile', () {
      final arrays = extrude(caps: false);
      // stations * (profilePoints + 1) vertices.
      expect(arrays.positions, hasLength(3 * 5 * 3));
      // (stations - 1) * profilePoints quads.
      expect(arrays.indices, hasLength(2 * 4 * 6));
    });

    test('caps add a fan at each end', () {
      final arrays = extrude(caps: true);
      expect(arrays.positions, hasLength((3 * 5 + 2 * 5) * 3));
      expect(arrays.indices, hasLength(2 * 4 * 6 + 2 * 4 * 3));
    });

    test('every normal is unit length', () {
      final arrays = extrude(caps: true);
      final count = arrays.normals.length ~/ 3;
      for (var v = 0; v < count; v++) {
        final nx = arrays.normals[v * 3];
        final ny = arrays.normals[v * 3 + 1];
        final nz = arrays.normals[v * 3 + 2];
        expect(math.sqrt(nx * nx + ny * ny + nz * nz), closeTo(1, 1e-5));
      }
    });
  });
}
