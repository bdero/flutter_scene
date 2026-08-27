// Covers the terrain height field and the mesh arrays built from it. Both are
// pure, so they run without a GPU; the geometry object itself needs one.
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/terrain.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 3x3 field over a 2x2 patch: a ramp rising along +X, flat along Z.
HeightField rampField() => HeightField(
  heights: Float32List.fromList([0, 1, 2, 0, 1, 2, 0, 1, 2]),
  columns: 3,
  rows: 3,
  width: 2,
  depth: 2,
);

void main() {
  group('sampling', () {
    test('reads a sample at a grid position', () {
      final field = rampField();
      expect(field.sample(0, 0), 0);
      expect(field.sample(2, 0), 2);
      expect(field.sample(1, 2), 1);
    });

    test('clamps to the edge instead of wrapping', () {
      // Wrapping would read the far side of the map, which is a seam in the
      // normals along every border.
      final field = rampField();
      expect(field.sample(-1, 0), field.sample(0, 0));
      expect(field.sample(99, 0), field.sample(2, 0));
      expect(field.sample(0, -5), field.sample(0, 0));
    });

    test('interpolates between samples in world space', () {
      final field = rampField();
      // The patch spans -1..1 on each axis, so the centre is the middle
      // sample and a quarter across is halfway to the next one.
      expect(field.heightAtWorld(-1, 0), closeTo(0, 1e-6));
      expect(field.heightAtWorld(0, 0), closeTo(1, 1e-6));
      expect(field.heightAtWorld(1, 0), closeTo(2, 1e-6));
      expect(field.heightAtWorld(-0.5, 0), closeTo(0.5, 1e-6));
    });

    test('a query off the patch reads the edge, not a hole', () {
      // A character walking off the end walks level rather than falling
      // through the world.
      final field = rampField();
      expect(field.heightAtWorld(-99, 0), closeTo(0, 1e-6));
      expect(field.heightAtWorld(99, 0), closeTo(2, 1e-6));
      expect(field.heightAtWorld(0, 99), closeTo(1, 1e-6));
    });
  });

  group('noise fields', () {
    test('the same seed gives the same ground', () {
      // This is what lets a document carry eight numbers instead of a
      // megabyte of samples.
      HeightField build(int seed) => HeightField.noise(
        width: 32,
        depth: 32,
        columns: 17,
        rows: 17,
        seed: seed,
      );
      expect(build(7).heights, build(7).heights);
      expect(build(7).heights, isNot(build(8).heights));
    });

    test('amplitude bounds the range', () {
      final field = HeightField.noise(
        width: 32,
        depth: 32,
        columns: 33,
        rows: 33,
        amplitude: 3,
      );
      for (final height in field.heights) {
        expect(height.abs(), lessThanOrEqualTo(3.0 + 1e-5));
      }
      // And it is not simply flat.
      expect(field.heights.any((h) => h.abs() > 0.05), isTrue);
    });

    test('an octave count below one is treated as one', () {
      expect(
        () => HeightField.noise(
          width: 8,
          depth: 8,
          columns: 5,
          rows: 5,
          octaves: 0,
        ),
        returnsNormally,
      );
    });
  });

  group('mesh arrays', () {
    test('one vertex per sample and two triangles per quad', () {
      final arrays = buildTerrainArrays(rampField());
      expect(arrays.positions.length, 9 * 3);
      expect(arrays.texCoords!.length, 9 * 2);
      // 2x2 quads, two triangles each, three indices each.
      expect(arrays.indices.length, 2 * 2 * 2 * 3);
    });

    test('positions carry the field height and span the patch', () {
      final arrays = buildTerrainArrays(rampField());
      // First vertex: low corner, height 0.
      expect(arrays.positions[0], closeTo(-1, 1e-6));
      expect(arrays.positions[1], closeTo(0, 1e-6));
      expect(arrays.positions[2], closeTo(-1, 1e-6));
      // Third vertex: high-X edge of the first row, height 2.
      expect(arrays.positions[6], closeTo(1, 1e-6));
      expect(arrays.positions[7], closeTo(2, 1e-6));
    });

    test('normals lean away from the slope and stay unit length', () {
      final arrays = buildTerrainArrays(rampField());
      for (var v = 0; v < 9; v++) {
        final x = arrays.normals![v * 3];
        final y = arrays.normals![v * 3 + 1];
        final z = arrays.normals![v * 3 + 2];
        expect(x * x + y * y + z * z, closeTo(1, 1e-5));
        // The ramp climbs toward +X, so every normal tips toward -X, and
        // none tips along Z because the field is flat that way.
        expect(x, lessThan(0));
        expect(z, closeTo(0, 1e-6));
        expect(y, greaterThan(0), reason: 'the surface faces up');
      }
    });

    test('a flat field gives flat-up normals', () {
      final flat = HeightField(
        heights: Float32List(9),
        columns: 3,
        rows: 3,
        width: 2,
        depth: 2,
      );
      final arrays = buildTerrainArrays(flat);
      for (var v = 0; v < 9; v++) {
        expect(arrays.normals![v * 3 + 1], closeTo(1, 1e-6));
      }
    });
  });
}
