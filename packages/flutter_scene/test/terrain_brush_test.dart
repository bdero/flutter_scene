// Terrain sculpting. Pure edits over a height field, so the brush behaviour
// is testable without a viewport or a GPU.
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/terrain.dart';
import 'package:flutter_scene/src/geometry/terrain_brush.dart';
import 'package:flutter_test/flutter_test.dart';

/// A flat 21x21 field spanning -10..10 on both axes, one unit per sample.
HeightField flat() => HeightField(
  heights: Float32List(21 * 21),
  columns: 21,
  rows: 21,
  width: 20,
  depth: 20,
);

double at(HeightField f, double x, double z) => f.heightAtWorld(x, z);

void main() {
  group('falloff', () {
    const brush = TerrainBrush(radius: 4, falloff: 0.5);

    test('full strength inside the falloff edge', () {
      expect(brush.weightAt(0), 1.0);
      expect(brush.weightAt(1.9), 1.0);
    });

    test('nothing at or beyond the rim', () {
      expect(brush.weightAt(4), 0.0);
      expect(brush.weightAt(9), 0.0);
    });

    test('eases between the two rather than ramping linearly', () {
      // A linear ramp leaves a cone; the smoothstep leaves a hill. The two
      // agree at the midpoint, so the difference has to be read off the
      // quarter points: eased is above the line near the top and below it
      // near the rim.
      expect(brush.weightAt(3), closeTo(0.5, 1e-6));
      expect(brush.weightAt(2.5), greaterThan(0.75));
      expect(brush.weightAt(3.5), lessThan(0.25));
    });

    test('a zero falloff is a hard edge', () {
      const hard = TerrainBrush(radius: 4, falloff: 0);
      expect(hard.weightAt(3.9), greaterThan(0));
      expect(hard.weightAt(0), 1.0);
    });
  });

  group('raise', () {
    test('lifts the centre most and the rim not at all', () {
      final field = flat();
      sculptTerrain(
        field,
        brush: const TerrainBrush(radius: 4, strength: 2),
        x: 0,
        z: 0,
      );
      expect(at(field, 0, 0), closeTo(2, 1e-5));
      expect(at(field, 3, 0), greaterThan(0));
      expect(at(field, 3, 0), lessThan(2));
      expect(at(field, 9, 0), closeTo(0, 1e-6));
    });

    test('a negative strength digs', () {
      final field = flat();
      sculptTerrain(
        field,
        brush: const TerrainBrush(radius: 4, strength: -2),
        x: 0,
        z: 0,
      );
      expect(at(field, 0, 0), closeTo(-2, 1e-5));
    });

    test('strokes accumulate', () {
      final field = flat();
      const brush = TerrainBrush(radius: 4, strength: 1);
      for (var i = 0; i < 3; i++) {
        sculptTerrain(field, brush: brush, x: 0, z: 0);
      }
      expect(at(field, 0, 0), closeTo(3, 1e-5));
    });

    test('time scales the stroke', () {
      final field = flat();
      sculptTerrain(
        field,
        brush: const TerrainBrush(radius: 4, strength: 2),
        x: 0,
        z: 0,
        deltaSeconds: 0.5,
      );
      expect(at(field, 0, 0), closeTo(1, 1e-5));
    });

    test('it reports only the samples it touched', () {
      final field = flat();
      final range = sculptTerrain(
        field,
        brush: const TerrainBrush(radius: 2, strength: 1),
        x: 0,
        z: 0,
      )!;
      // A radius-2 brush at the centre of a 21-sample grid cannot reach the
      // edges, so a caller can rebuild a fraction of the mesh.
      expect(range.minColumn, greaterThan(0));
      expect(range.maxColumn, lessThan(20));
      expect(range.minRow, greaterThan(0));
      expect(range.maxRow, lessThan(20));
    });

    test('a stroke off the field changes nothing and reports nothing', () {
      final field = flat();
      expect(
        sculptTerrain(
          field,
          brush: const TerrainBrush(radius: 1, strength: 5),
          x: 500,
          z: 500,
        ),
        isNull,
      );
      expect(field.heights.every((h) => h == 0), isTrue);
    });
  });

  group('flatten', () {
    test('pulls the ground toward its target', () {
      final field = flat();
      sculptTerrain(
        field,
        brush: const TerrainBrush(radius: 4, strength: 5),
        x: 0,
        z: 0,
      );
      expect(at(field, 0, 0), greaterThan(4));

      sculptTerrain(
        field,
        brush: const TerrainBrush(
          kind: TerrainBrushKind.flatten,
          radius: 4,
          strength: 1,
          targetHeight: 1,
        ),
        x: 0,
        z: 0,
      );
      expect(at(field, 0, 0), closeTo(1, 1e-5));
    });

    test('it cannot overshoot its target however hard it is pushed', () {
      final field = flat();
      sculptTerrain(
        field,
        brush: const TerrainBrush(
          kind: TerrainBrushKind.flatten,
          radius: 4,
          strength: 50,
          targetHeight: 3,
        ),
        x: 0,
        z: 0,
      );
      expect(at(field, 0, 0), closeTo(3, 1e-5));
    });
  });

  group('smooth', () {
    test('takes the edge off a spike', () {
      final field = flat();
      // One sharp sample, no falloff so only it moves.
      field.heights[10 * 21 + 10] = 10;
      final before = field.heights[10 * 21 + 10];

      sculptTerrain(
        field,
        brush: const TerrainBrush(
          kind: TerrainBrushKind.smooth,
          radius: 3,
          strength: 1,
        ),
        x: 0,
        z: 0,
      );

      final after = field.heights[10 * 21 + 10];
      expect(after, lessThan(before), reason: 'the peak came down');
      expect(
        field.heights[10 * 21 + 11],
        greaterThan(0),
        reason: 'its neighbour came up',
      );
    });

    test(
      'it reads a snapshot, so the result does not depend on scan order',
      () {
        // Smoothing in place would make each sample see its already-smoothed
        // neighbours, which biases the result toward wherever the loop began.
        HeightField spiked() {
          final f = flat();
          f.heights[10 * 21 + 10] = 10;
          return f;
        }

        final left = spiked();
        final right = spiked();
        const brush = TerrainBrush(
          kind: TerrainBrushKind.smooth,
          radius: 3,
          strength: 1,
        );
        sculptTerrain(left, brush: brush, x: 0, z: 0);
        sculptTerrain(right, brush: brush, x: 0, z: 0);
        expect(left.heights, right.heights);

        // And the smoothed peak is the mean of the nine samples around it,
        // which it cannot be if neighbours were read after being changed.
        expect(left.heights[10 * 21 + 10], closeTo(10 / 9, 1e-4));
      },
    );
  });
}
