// Covers the terrain height field and the mesh arrays built from it. Both are
// pure, so they run without a GPU; the geometry object itself needs one.
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/terrain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

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

  group('stored heightmaps', () {
    test('a field survives the byte round trip exactly', () {
      // Sculpted terrain is stored as packed floats, so this is the format
      // a saved scene actually carries.
      final field = HeightField.noise(
        width: 16,
        depth: 24,
        columns: 9,
        rows: 13,
        seed: 99,
      );
      final back = HeightField.fromBytes(
        field.toBytes(),
        columns: 9,
        rows: 13,
        width: 16,
        depth: 24,
      )!;
      expect(back.heights, field.heights);
      expect(back.width, 16);
      expect(back.depth, 24);
      expect(back.heightAtWorld(2, -3), field.heightAtWorld(2, -3));
    });

    test('the samples are copied, not aliased onto the payload buffer', () {
      // Sculpting mutates the field in place; if it were a view over the
      // document's bytes it would edit the saved copy behind the scenes.
      final field = rampField();
      final bytes = field.toBytes();
      final loaded = HeightField.fromBytes(
        bytes,
        columns: 3,
        rows: 3,
        width: 2,
        depth: 2,
      )!;
      loaded.heights[0] = 99;
      expect(field.heights[0], 0, reason: 'the original is untouched');
    });

    test('a heightmap of the wrong size is refused, not stretched', () {
      // Reading a truncated map would put a cliff wherever it ran out.
      final field = rampField();
      expect(
        HeightField.fromBytes(
          field.toBytes(),
          columns: 4,
          rows: 4,
          width: 2,
          depth: 2,
        ),
        isNull,
      );
    });

    test('a degenerate grid is refused', () {
      expect(
        HeightField.fromBytes(
          Float32List(1).buffer.asUint8List(),
          columns: 1,
          rows: 1,
          width: 1,
          depth: 1,
        ),
        isNull,
      );
    });
  });

  group('raycasting', () {
    /// A flat field at height zero spanning -10..10.
    HeightField flat() => HeightField(
      heights: Float32List(21 * 21),
      columns: 21,
      rows: 21,
      width: 20,
      depth: 20,
    );

    test('a ray straight down lands on the ground under it', () {
      final hit = flat().raycast(Vector3(3, 10, -4), Vector3(0, -1, 0))!;
      expect(hit.x, closeTo(3, 1e-3));
      expect(hit.y, closeTo(0, 1e-3));
      expect(hit.z, closeTo(-4, 1e-3));
    });

    test('it finds the raised ground, not the old flat level', () {
      final field = flat();
      // A plateau two units up around the middle.
      for (var r = 8; r <= 12; r++) {
        for (var c = 8; c <= 12; c++) {
          field.heights[r * 21 + c] = 2;
        }
      }
      final hit = field.raycast(Vector3(0, 10, 0), Vector3(0, -1, 0))!;
      expect(hit.y, closeTo(2, 1e-3));
    });

    test('a ray angled across the ground still lands on it', () {
      final hit = flat().raycast(Vector3(-8, 6, 0), Vector3(1, -1, 0))!;
      expect(hit.y, closeTo(0, 1e-3));
      expect(hit.x, closeTo(-2, 1e-2), reason: 'it fell six units over six');
    });

    test('a ray pointing away from the ground misses', () {
      expect(flat().raycast(Vector3(0, 5, 0), Vector3(0, 1, 0)), isNull);
    });

    test('a ray that runs out of distance misses', () {
      expect(
        flat().raycast(Vector3(0, 5, 0), Vector3(0, -1, 0), maxDistance: 1),
        isNull,
      );
    });

    test('a ray starting underground reports where it started', () {
      // Rather than hunting forward for a crossing that is behind it.
      final hit = flat().raycast(Vector3(1, -3, 1), Vector3(0, -1, 0))!;
      expect(hit.y, closeTo(-3, 1e-9));
    });

    test('it hits a slope at the right height', () {
      // The ramp field rises along +X from 0 to 2 across -1..1.
      final hit = rampField().raycast(Vector3(0, 5, 0), Vector3(0, -1, 0))!;
      expect(hit.y, closeTo(1, 1e-3), reason: 'the middle of the ramp');
    });
  });
}
