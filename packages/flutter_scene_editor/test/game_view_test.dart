// Where the game frame lands. The one thing this view must not do is lie
// about the framing, which is the only thing it is for -- so it letterboxes
// rather than stretching or cropping.

import 'dart:ui';

import 'package:flutter_scene_editor/src/panels/game_view_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('free aspect fills the panel', () {
    final rect = gameFrameRect(const Size(800, 600), null);
    expect(rect, const Rect.fromLTWH(0, 0, 800, 600));
  });

  test('a wide panel letterboxes at the sides, centred', () {
    // 1000x500 holding 16:9 -> the height is the limit.
    final rect = gameFrameRect(const Size(1000, 500), 16 / 9);
    expect(rect.height, 500);
    expect(rect.width, closeTo(500 * 16 / 9, 0.01));
    expect(rect.center.dx, closeTo(500, 0.01));
    expect(rect.left, closeTo(1000 - rect.right, 0.01));
  });

  test('a tall panel letterboxes above and below, centred', () {
    final rect = gameFrameRect(const Size(640, 1000), 16 / 9);
    expect(rect.width, 640);
    expect(rect.height, closeTo(640 * 9 / 16, 0.01));
    expect(rect.center.dy, closeTo(500, 0.01));
  });

  test('an exact fit uses the whole panel', () {
    final rect = gameFrameRect(const Size(1600, 900), 16 / 9);
    expect(rect.width, closeTo(1600, 0.01));
    expect(rect.height, closeTo(900, 0.01));
  });

  test('the frame keeps its ratio, whatever the panel', () {
    for (final size in [
      const Size(300, 900),
      const Size(1200, 200),
      const Size(500, 500),
    ]) {
      final rect = gameFrameRect(size, 4 / 3);
      expect(rect.width / rect.height, closeTo(4 / 3, 0.001), reason: '$size');
    }
  });

  test('the frame never leaves the panel', () {
    for (final size in [const Size(300, 900), const Size(1200, 200)]) {
      final rect = gameFrameRect(size, 21 / 9);
      expect(rect.left, greaterThanOrEqualTo(-0.01));
      expect(rect.top, greaterThanOrEqualTo(-0.01));
      expect(rect.right, lessThanOrEqualTo(size.width + 0.01));
      expect(rect.bottom, lessThanOrEqualTo(size.height + 0.01));
    }
  });

  test('a panel with no size gives nothing to draw, rather than NaNs', () {
    expect(gameFrameRect(Size.zero, 16 / 9), Rect.zero);
    expect(gameFrameRect(const Size(0, 400), 16 / 9), Rect.zero);
  });

  test('a nonsense ratio is treated as free', () {
    expect(
      gameFrameRect(const Size(800, 600), 0),
      const Rect.fromLTWH(0, 0, 800, 600),
    );
    expect(
      gameFrameRect(const Size(800, 600), -2),
      const Rect.fromLTWH(0, 0, 800, 600),
    );
  });

  test('every offered aspect has a label, and only Free is unconstrained', () {
    expect(gameAspects.first.ratio, isNull);
    for (final aspect in gameAspects) {
      expect(aspect.label, isNotEmpty);
    }
    expect(gameAspects.skip(1).every((a) => (a.ratio ?? 0) > 0), isTrue);
  });
}
