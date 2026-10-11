import 'package:flutter_scene_xr/src/viewport_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizedViewportFromGl', () {
    test('maps the left eye of a side-by-side framebuffer', () {
      final rect = normalizedViewportFromGl(
        x: 0,
        y: 0,
        width: 1680,
        height: 1760,
        targetWidth: 3360,
        targetHeight: 1760,
      );
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.width, 0.5);
      expect(rect.height, 1);
    });

    test('maps the right eye of a side-by-side framebuffer', () {
      final rect = normalizedViewportFromGl(
        x: 1680,
        y: 0,
        width: 1680,
        height: 1760,
        targetWidth: 3360,
        targetHeight: 1760,
      );
      expect(rect.left, 0.5);
      expect(rect.right, 1);
    });

    test('flips a bottom-left pixel rect to a top-left origin', () {
      // A 100 px tall strip sitting 300 px above the GL bottom of a 1000 px
      // target starts 600 px from the top.
      final rect = normalizedViewportFromGl(
        x: 250,
        y: 300,
        width: 500,
        height: 100,
        targetWidth: 1000,
        targetHeight: 1000,
      );
      expect(rect.left, 0.25);
      expect(rect.top, closeTo(0.6, 1e-12));
      expect(rect.width, 0.5);
      expect(rect.height, closeTo(0.1, 1e-12));
    });

    test('an empty target yields the whole rect', () {
      final rect = normalizedViewportFromGl(
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        targetWidth: 0,
        targetHeight: 0,
      );
      expect(rect.width, 1);
      expect(rect.height, 1);
    });
  });
}
