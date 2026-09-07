/// The UI rect solve, against the arrangements it exists to serve.
library;

import 'package:scene/scene.dart';
import 'package:test/test.dart';

/// A 1000 x 600 canvas, bottom-left at the origin.
const _canvas = UiRect.size(1000, 600);

void _expectRect(
  UiRect actual, {
  required double left,
  required double bottom,
  required double width,
  required double height,
}) {
  expect(actual.left, closeTo(left, 1e-9), reason: 'left of $actual');
  expect(actual.bottom, closeTo(bottom, 1e-9), reason: 'bottom of $actual');
  expect(actual.width, closeTo(width, 1e-9), reason: 'width of $actual');
  expect(actual.height, closeTo(height, 1e-9), reason: 'height of $actual');
}

void main() {
  group('anchors at one point hold a size', () {
    test('centred', () {
      final rect = solveRect(
        _canvas,
        const RectTransformValues(sizeDeltaX: 300, sizeDeltaY: 200),
      );

      _expectRect(rect, left: 350, bottom: 200, width: 300, height: 200);
    });

    test('the size is held as the parent grows', () {
      const values = RectTransformValues(sizeDeltaX: 300, sizeDeltaY: 200);
      final small = solveRect(const UiRect.size(1000, 600), values);
      final large = solveRect(const UiRect.size(2000, 1200), values);

      expect(large.width, small.width);
      expect(large.height, small.height);
      // Centred in each, so it moves with the centre rather than staying put.
      expect(large.left, 850);
      expect(large.bottom, 500);
    });

    test('pinned to a corner, it keeps its distance from that corner', () {
      // Top-right anchor, top-right pivot: the offset is measured from the
      // corner, so the rectangle holds its inset however the parent resizes.
      const values = RectTransformValues(
        anchorMinX: 1,
        anchorMinY: 1,
        anchorMaxX: 1,
        anchorMaxY: 1,
        pivotX: 1,
        pivotY: 1,
        anchoredX: -16,
        anchoredY: -16,
        sizeDeltaX: 120,
        sizeDeltaY: 40,
      );

      final small = solveRect(const UiRect.size(1000, 600), values);
      _expectRect(small, left: 864, bottom: 544, width: 120, height: 40);

      final large = solveRect(const UiRect.size(2000, 1200), values);
      expect(large.right, 2000 - 16, reason: 'same inset from the right edge');
      expect(large.top, 1200 - 16, reason: 'same inset from the top edge');
    });

    test('the pivot decides which point the offset positions', () {
      // Same anchor and offset, opposite pivots: the rectangle lands on
      // either side of the same point.
      const shared = (anchoredX: 100.0, anchoredY: 100.0);
      final leftPivot = solveRect(
        _canvas,
        RectTransformValues(
          anchorMinX: 0,
          anchorMinY: 0,
          anchorMaxX: 0,
          anchorMaxY: 0,
          pivotX: 0,
          pivotY: 0,
          anchoredX: shared.anchoredX,
          anchoredY: shared.anchoredY,
          sizeDeltaX: 80,
          sizeDeltaY: 80,
        ),
      );
      final rightPivot = solveRect(
        _canvas,
        RectTransformValues(
          anchorMinX: 0,
          anchorMinY: 0,
          anchorMaxX: 0,
          anchorMaxY: 0,
          pivotX: 1,
          pivotY: 1,
          anchoredX: shared.anchoredX,
          anchoredY: shared.anchoredY,
          sizeDeltaX: 80,
          sizeDeltaY: 80,
        ),
      );

      expect(leftPivot.left, 100);
      expect(rightPivot.right, 100);
    });
  });

  group('anchors apart stretch', () {
    test('full bleed fills the parent exactly', () {
      final rect = solveRect(_canvas, const RectTransformValues.stretch());

      _expectRect(rect, left: 0, bottom: 0, width: 1000, height: 600);
    });

    test('an inset is taken off every side', () {
      final rect = solveRect(
        _canvas,
        const RectTransformValues.stretch(inset: 16),
      );

      _expectRect(rect, left: 16, bottom: 16, width: 968, height: 568);
    });

    test('stretching one axis holds a size on the other', () {
      // A bar across the bottom: full width, fixed height.
      const values = RectTransformValues(
        anchorMinX: 0,
        anchorMinY: 0,
        anchorMaxX: 1,
        anchorMaxY: 0,
        pivotX: 0.5,
        pivotY: 0,
        sizeDeltaX: 0,
        sizeDeltaY: 48,
      );

      _expectRect(
        solveRect(_canvas, values),
        left: 0,
        bottom: 0,
        width: 1000,
        height: 48,
      );
      // Twice as wide a parent, same bar height.
      final wide = solveRect(const UiRect.size(2000, 600), values);
      expect(wide.width, 2000);
      expect(wide.height, 48);
    });

    test('a stretched rect tracks the parent, not its own old size', () {
      const values = RectTransformValues.stretch(inset: 10);
      final grown = solveRect(const UiRect.size(2000, 1200), values);

      _expectRect(grown, left: 10, bottom: 10, width: 1980, height: 1180);
    });
  });

  group('nesting', () {
    test('a child solves against its parent rect, not the canvas', () {
      // A panel inset in the canvas, and a button pinned to that panel's
      // bottom-left. The button must follow the panel.
      final panel = solveRect(
        _canvas,
        const RectTransformValues.stretch(inset: 100),
      );
      final button = solveRect(
        panel,
        const RectTransformValues(
          anchorMinX: 0,
          anchorMinY: 0,
          anchorMaxX: 0,
          anchorMaxY: 0,
          pivotX: 0,
          pivotY: 0,
          anchoredX: 8,
          anchoredY: 8,
          sizeDeltaX: 60,
          sizeDeltaY: 24,
        ),
      );

      _expectRect(panel, left: 100, bottom: 100, width: 800, height: 400);
      _expectRect(button, left: 108, bottom: 108, width: 60, height: 24);
    });
  });

  group('degenerate input', () {
    test('a negative size clamps to zero rather than inverting', () {
      // A stretch inset larger than the parent. A negative width has no
      // meaning downstream and would otherwise need guarding at every use.
      final rect = solveRect(
        const UiRect.size(100, 100),
        const RectTransformValues.stretch(inset: 80),
      );

      expect(rect.width, 0);
      expect(rect.height, 0);
    });

    test('a zero-sized parent still solves', () {
      final rect = solveRect(
        const UiRect.size(0, 0),
        const RectTransformValues.stretch(),
      );

      _expectRect(rect, left: 0, bottom: 0, width: 0, height: 0);
    });

    test('anchors out of order do not throw', () {
      final rect = solveRect(
        _canvas,
        const RectTransformValues(
          anchorMinX: 0.8,
          anchorMaxX: 0.2,
          anchorMinY: 0,
          anchorMaxY: 1,
          sizeDeltaX: 700,
          sizeDeltaY: 0,
        ),
      );

      // The span is -600, and sizeDelta covers it: 100 wide, full height.
      expect(rect.width, closeTo(100, 1e-9));
      expect(rect.height, closeTo(600, 1e-9));
    });
  });

  group('the canvas rect itself', () {
    test('is its size at the origin', () {
      const rect = UiRect.size(1920, 1080);

      expect(rect.left, 0);
      expect(rect.bottom, 0);
      expect(rect.right, 1920);
      expect(rect.top, 1080);
    });

    test('fractionOf reads Y-up, so (0,0) is bottom-left', () {
      const rect = UiRect(left: 10, bottom: 20, width: 100, height: 200);

      expect(rect.fractionOf(0, 0), (10.0, 20.0));
      expect(rect.fractionOf(1, 1), (110.0, 220.0));
      expect(rect.fractionOf(0.5, 0.5), (60.0, 120.0));
    });
  });
}
