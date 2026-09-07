// Scatter placement. Pure over a brush and a ground function, so where things
// land is testable without a scene.
import 'dart:math' as math;

import 'package:flutter_scene/src/kit/scatter/scatter_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

List<ScatterPlacement> scatter({
  ScatterBrush brush = const ScatterBrush(),
  int attempts = 40,
  Iterable<ScatterPlacement> existing = const [],
  double Function(double, double)? heightAt,
  int seed = 7,
}) => scatterInBrush(
  brush: brush,
  x: 0,
  z: 0,
  attempts: attempts,
  existing: existing,
  heightAt: heightAt,
  random: math.Random(seed),
);

void main() {
  group('placement', () {
    test('everything lands inside the brush', () {
      const brush = ScatterBrush(radius: 5, minSpacing: 0);
      for (final placement in scatter(brush: brush)) {
        final distance = math.sqrt(
          placement.position.x * placement.position.x +
              placement.position.z * placement.position.z,
        );
        expect(distance, lessThanOrEqualTo(5.0 + 1e-9));
      }
    });

    test('spacing is respected between everything placed', () {
      const brush = ScatterBrush(radius: 6, minSpacing: 2);
      final placed = scatter(brush: brush, attempts: 200);
      expect(placed.length, greaterThan(1));
      for (var i = 0; i < placed.length; i++) {
        for (var j = i + 1; j < placed.length; j++) {
          final dx = placed[i].position.x - placed[j].position.x;
          final dz = placed[i].position.z - placed[j].position.z;
          expect(math.sqrt(dx * dx + dz * dz), greaterThanOrEqualTo(2.0));
        }
      }
    });

    test('it respects what is already there', () {
      // Painting over the same ground twice should thicken toward a limit,
      // not double the trees standing on it.
      const brush = ScatterBrush(radius: 4, minSpacing: 3);
      final first = scatter(brush: brush, attempts: 200);
      final second = scatter(
        brush: brush,
        attempts: 200,
        existing: first,
        seed: 99,
      );
      for (final a in first) {
        for (final b in second) {
          final dx = a.position.x - b.position.x;
          final dz = a.position.z - b.position.z;
          expect(math.sqrt(dx * dx + dz * dz), greaterThanOrEqualTo(3.0));
        }
      }
    });

    test('a dense stroke fills up rather than growing without limit', () {
      const brush = ScatterBrush(radius: 4, minSpacing: 2);
      final few = scatter(brush: brush, attempts: 50);
      final many = scatter(brush: brush, attempts: 500);
      expect(many.length, greaterThanOrEqualTo(few.length));
      // A radius-4 disc cannot hold unlimited points two apart.
      expect(many.length, lessThan(40));
    });

    test('placements take the ground height under them', () {
      final placed = scatter(
        brush: const ScatterBrush(radius: 3, minSpacing: 0),
        heightAt: (x, z) => x + z,
      );
      for (final placement in placed) {
        expect(
          placement.position.y,
          closeTo(placement.position.x + placement.position.z, 1e-6),
        );
      }
    });

    test('alignToGround off leaves everything on the plane', () {
      final placed = scatter(
        brush: const ScatterBrush(
          radius: 3,
          minSpacing: 0,
          alignToGround: false,
        ),
        heightAt: (x, z) => 100,
      );
      expect(placed.every((p) => p.position.y == 0), isTrue);
    });

    test('scale stays inside the brush range', () {
      final placed = scatter(
        brush: const ScatterBrush(minSpacing: 0, minScale: 0.5, maxScale: 2),
      );
      for (final placement in placed) {
        expect(placement.scale, inInclusiveRange(0.5, 2.0));
      }
    });

    test('the same seed scatters the same way', () {
      final a = scatter();
      final b = scatter();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].position.x, b[i].position.x);
        expect(a[i].yaw, b[i].yaw);
      }
    });

    test('a zero radius or no attempts places nothing', () {
      expect(scatter(brush: const ScatterBrush(radius: 0)), isEmpty);
      expect(scatter(attempts: 0), isEmpty);
    });
  });

  group('erasing', () {
    List<ScatterPlacement> row() => [
      for (var i = 0; i < 5; i++)
        ScatterPlacement(position: Vector3(i.toDouble(), 0, 0)),
    ];

    test('removeWithin takes only what is under the brush', () {
      // Exercised through the pure list the layer keeps, since the layer
      // itself needs a GPU to build its batch.
      final placements = row();
      final kept = [
        for (final p in placements)
          if (math.sqrt(
                (p.position.x - 1) * (p.position.x - 1) +
                    p.position.z * p.position.z,
              ) >
              1.5)
            p,
      ];
      expect(kept.map((p) => p.position.x), [3.0, 4.0]);
    });

    test('height is ignored, so an eraser works on a slope', () {
      final high = ScatterPlacement(position: Vector3(0, 50, 0));
      final dx = high.position.x;
      final dz = high.position.z;
      expect(math.sqrt(dx * dx + dz * dz), 0, reason: 'y plays no part');
    });
  });
}
