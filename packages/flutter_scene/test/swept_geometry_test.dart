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
  });
}
