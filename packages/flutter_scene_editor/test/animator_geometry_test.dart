// Arrow routing. The cases that go wrong are the ones with two states in an
// awkward relationship: an arrow each way, a state pointing at itself, and two
// boxes dragged on top of one another.

import 'package:flutter_scene_editor/src/animator/animator_graph_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final idle = animatorStateRect(const Offset(0, 0));
  final run = animatorStateRect(const Offset(400, 0));

  group('border points', () {
    test('a line leaves the box on the side it is heading for', () {
      final point = animatorBorderPoint(idle, run.center);
      expect(point.dx, closeTo(idle.right, 0.01));
      expect(point.dy, closeTo(idle.center.dy, 0.01));
    });

    test('a line straight up leaves through the top', () {
      final point = animatorBorderPoint(
        idle,
        idle.center - const Offset(0, 500),
      );
      expect(point.dy, closeTo(idle.top, 0.01));
    });

    test('two boxes on the same spot still give a point to draw from', () {
      // Dragged onto each other, the line between the centres never crosses a
      // border. Drawing nothing at all would look like the arrow was deleted.
      final point = animatorBorderPoint(idle, idle.center);
      expect(point, idle.center);
      expect(point.dx.isFinite, isTrue);
    });
  });

  group('arrows', () {
    test('a lone arrow runs between the two borders', () {
      final arrow = animatorArrowBetween(idle, run);
      expect(arrow.start.dx, closeTo(idle.right, 0.01));
      expect(arrow.end.dx, closeTo(run.left, 0.01));
    });

    test('a pair between the same states is drawn either side of the line', () {
      final first = animatorArrowBetween(idle, run, ordinal: 0, count: 2);
      final second = animatorArrowBetween(idle, run, ordinal: 1, count: 2);
      expect(first.start.dy, isNot(closeTo(second.start.dy, 0.5)));
      // Symmetric about the centre line, so neither looks like the odd one.
      final centre = idle.center.dy;
      expect(
        (first.start.dy - centre).abs(),
        closeTo((second.start.dy - centre).abs(), 0.01),
      );
    });

    test('the head points the way the arrow runs', () {
      final head = animatorArrowHead(const Offset(0, 0), const Offset(100, 0));
      expect(head, hasLength(3));
      expect(head.first, const Offset(100, 0));
      // The two base corners sit behind the tip.
      expect(head[1].dx, lessThan(100));
      expect(head[2].dx, lessThan(100));
    });

    test('a zero-length arrow does not produce NaNs', () {
      final arrow = animatorArrowBetween(idle, idle);
      expect(arrow.start.dx.isFinite, isTrue);
      final head = animatorArrowHead(arrow.start, arrow.end);
      expect(head.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    });
  });

  group('picking', () {
    test('a click on the line hits it', () {
      expect(
        animatorArrowHit(
          const Offset(0, 0),
          const Offset(100, 0),
          const Offset(50, 3),
        ),
        isTrue,
      );
    });

    test('a click off the line misses', () {
      expect(
        animatorArrowHit(
          const Offset(0, 0),
          const Offset(100, 0),
          const Offset(50, 40),
        ),
        isFalse,
      );
    });

    test('a click past the end misses, rather than hitting the whole ray', () {
      expect(
        animatorArrowHit(
          const Offset(0, 0),
          const Offset(100, 0),
          const Offset(300, 0),
        ),
        isFalse,
      );
    });
  });

  group('placement', () {
    test('a new state lands somewhere free', () {
      final taken = [const Offset(40, 40)];
      final next = animatorFreePosition(taken);
      expect(next, isNot(const Offset(40, 40)));
    });

    test('states added one after another form a grid, not a pile', () {
      final taken = <Offset>[];
      for (var i = 0; i < 6; i++) {
        taken.add(animatorFreePosition(taken));
      }
      expect(taken.toSet(), hasLength(6));
      // Four to a row, then it wraps.
      expect(taken[4].dy, greaterThan(taken[0].dy));
    });

    test('framing covers every box, not just the positions', () {
      final bounds = animatorGraphBounds([
        const Offset(0, 0),
        const Offset(400, 100),
      ]);
      expect(bounds, isNotNull);
      expect(bounds!.right, 400 + animatorStateSize.width);
      expect(bounds.bottom, 100 + animatorStateSize.height);
    });

    test('an empty machine has nothing to frame', () {
      expect(animatorGraphBounds(const []), isNull);
    });
  });
}
