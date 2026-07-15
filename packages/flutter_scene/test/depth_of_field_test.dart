import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepthOfField CoC math', () {
    test('focal length derives from the FOV and sensor height', () {
      final dof = DepthOfField()..sensorHeight = 0.024;
      final fov = math.pi / 3; // 60 degrees
      final f = dof.resolveFocalLength(fov);
      expect(f, closeTo(0.5 * 0.024 / math.tan(fov / 2), 1e-12));
      dof.focalLength = 0.05;
      expect(dof.resolveFocalLength(fov), 0.05);
    });

    test('cocScale matches the thin-lens formula', () {
      final dof = DepthOfField()
        ..focusDistance = 10.0
        ..fStop = 2.8
        ..focalLength = 0.05
        ..sensorHeight = 0.024;
      const heightPx = 540.0;
      final k = dof.cocScale(math.pi / 3, heightPx);
      // Radius in pixels at depth d: k * (1 - S/d). Cross-check against the
      // raw formula c = A*f*|d-S| / (d*(S-f)) scaled to pixels.
      const d = 25.0;
      const s = 10.0;
      const f = 0.05;
      const a = f / 2.8;
      final sensorDiameter = a * f * (d - s) / (d * (s - f));
      final expectedRadiusPx = sensorDiameter / 0.024 * heightPx / 2;
      expect(k * (1 - s / d), closeTo(expectedRadiusPx, 1e-9));
    });

    test('blur scales with aperture', () {
      final wide = DepthOfField()
        ..fStop = 1.4
        ..focalLength = 0.05;
      final narrow = DepthOfField()
        ..fStop = 5.6
        ..focalLength = 0.05;
      expect(
        wide.cocScale(math.pi / 3, 540),
        closeTo(narrow.cocScale(math.pi / 3, 540) * 4, 1e-9),
      );
    });
  });

  group('DepthOfField gather kernel', () {
    test('taps stay within the unit disc and match the quality tier', () {
      for (final quality in DepthOfFieldQuality.values) {
        final dof = DepthOfField()..quality = quality;
        final taps = dof.buildKernel();
        expect(taps.length, dof.tapCount * 2);
        for (var i = 0; i < taps.length; i += 2) {
          final r = math.sqrt(taps[i] * taps[i] + taps[i + 1] * taps[i + 1]);
          expect(r, lessThanOrEqualTo(1.0 + 1e-6));
        }
      }
    });

    test('a polygonal aperture pulls taps inside the circle', () {
      final circle = (DepthOfField()..bladeCount = 0).buildKernel();
      final hex =
          (DepthOfField()
                ..bladeCount = 6
                ..bladeCurvature = 0.0)
              .buildKernel();
      double meanRadius(List<double> taps) {
        var sum = 0.0;
        for (var i = 0; i < taps.length; i += 2) {
          sum += math.sqrt(taps[i] * taps[i] + taps[i + 1] * taps[i + 1]);
        }
        return sum / (taps.length / 2);
      }

      expect(meanRadius(hex), lessThan(meanRadius(circle)));
      // Full curvature rounds the polygon back into the circle.
      final rounded =
          (DepthOfField()
                ..bladeCount = 6
                ..bladeCurvature = 1.0)
              .buildKernel();
      expect(meanRadius(rounded), closeTo(meanRadius(circle), 1e-9));
    });

    test('the packed gather block is memoized until parameters change', () {
      final dof = DepthOfField();
      final a = dof.gatherInfoBlock(960, 540);
      expect(identical(a, dof.gatherInfoBlock(960, 540)), isTrue);
      dof.bladeCount = 6;
      expect(identical(a, dof.gatherInfoBlock(960, 540)), isFalse);
    });
  });
}
