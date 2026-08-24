import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoissonDiscSampler', () {
    test('samples points satisfying minimum distance constraint', () {
      const minDistance = 2.0;
      final points = PoissonDiscSampler.sampleRect(
        20.0,
        20.0,
        minDistance,
        seed: 123,
      );

      expect(points.length, greaterThan(10));

      for (var i = 0; i < points.length; i++) {
        for (var j = i + 1; j < points.length; j++) {
          final dist = (points[i] - points[j]).length;
          expect(dist, greaterThanOrEqualTo(minDistance * 0.999));
        }
      }
    });

    test('throws ArgumentError on invalid dimensions or distance', () {
      expect(
        () => PoissonDiscSampler.sampleRect(10, 10, 0.0),
        throwsArgumentError,
      );
      expect(
        () => PoissonDiscSampler.sampleRect(-5, 10, 1.0),
        throwsArgumentError,
      );
    });

    test('generates different layouts when unseeded', () {
      final p1 = PoissonDiscSampler.sampleRect(10.0, 10.0, 2.0);
      final p2 = PoissonDiscSampler.sampleRect(10.0, 10.0, 2.0);

      expect(p1.first == p2.first, isFalse);
    });
  });
}
