/// Where the boxes and the arrows go.
///
/// Kept apart from the widget that paints them because arrow routing is the
/// part with edge cases in it: a pair of states with an arrow each way, a
/// self-transition, and two boxes overlapping so far that the line between
/// their centres never leaves either one. All of that is testable as
/// arithmetic and none of it needs a frame.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// A state box, drawn at the state's stored position.
const Size animatorStateSize = Size(168, 46);

/// The Any State box, which is wider than it is tall for the same reason a
/// state is: it holds a name.
const Size animatorAnyStateSize = Size(120, 34);

/// How far apart two arrows between the same pair of states are drawn, so
/// A to B and B to A are two lines rather than one.
const double animatorArrowSpread = 9;

/// The box for a state whose stored position is [position].
///
/// The position is the box's top-left, which is what a drag moves.
Rect animatorStateRect(Offset position, [Size size = animatorStateSize]) =>
    position & size;

/// Where a line from [from] toward [to] leaves [from]'s border.
///
/// Returns the centre when the two boxes overlap enough that the line never
/// crosses a border, which keeps a dragged-on-top-of-each-other pair drawing
/// something rather than nothing.
Offset animatorBorderPoint(Rect from, Offset to) {
  final centre = from.center;
  final delta = to - centre;
  if (delta.distanceSquared < 1e-6) return centre;
  // Scale the ray until it meets the nearer of the two border planes.
  final halfWidth = from.width / 2;
  final halfHeight = from.height / 2;
  final scaleX = delta.dx.abs() < 1e-6
      ? double.infinity
      : halfWidth / delta.dx.abs();
  final scaleY = delta.dy.abs() < 1e-6
      ? double.infinity
      : halfHeight / delta.dy.abs();
  final scale = math.min(scaleX, scaleY);
  if (!scale.isFinite) return centre;
  return centre + delta * scale;
}

/// One arrow, resolved to the two points it is drawn between.
typedef AnimatorArrow = ({Offset start, Offset end});

/// Where the arrow for a transition between [from] and [to] runs.
///
/// [ordinal] and [count] spread arrows that share a pair of boxes: with two
/// transitions between the same states, one is drawn to each side of the line
/// between their centres, so neither hides the other.
AnimatorArrow animatorArrowBetween(
  Rect from,
  Rect to, {
  int ordinal = 0,
  int count = 1,
}) {
  final start = animatorBorderPoint(from, to.center);
  final end = animatorBorderPoint(to, from.center);
  if (count <= 1) return (start: start, end: end);
  // Perpendicular to the run of the arrow, centred on zero so a pair sits
  // symmetrically about the line rather than both to one side.
  final along = end - start;
  final length = along.distance;
  if (length < 1e-6) return (start: start, end: end);
  final normal = Offset(-along.dy, along.dx) / length;
  final offset = (ordinal - (count - 1) / 2) * animatorArrowSpread;
  return (start: start + normal * offset, end: end + normal * offset);
}

/// The three points of the arrowhead at [end], pointing along the arrow.
List<Offset> animatorArrowHead(Offset start, Offset end, {double size = 9}) {
  final along = end - start;
  final length = along.distance;
  if (length < 1e-6) return [end, end, end];
  final unit = along / length;
  final normal = Offset(-unit.dy, unit.dx);
  final base = end - unit * size;
  return [end, base + normal * (size * 0.42), base - normal * (size * 0.42)];
}

/// The loop drawn for a transition from a state to itself, as the rectangle
/// an arc is swept through above the box.
Rect animatorSelfLoopBounds(Rect state) =>
    Rect.fromLTWH(state.center.dx - 24, state.top - 30, 48, 38);

/// Where to put a new state so it does not land on one already there.
///
/// Walks right along a row and wraps, which puts a machine built entirely by
/// pressing Add State into a readable grid rather than a single pile.
Offset animatorFreePosition(Iterable<Offset> taken, {int columns = 4}) {
  const gapX = 200.0;
  const gapY = 90.0;
  final used = taken.toSet();
  for (var i = 0; ; i++) {
    final candidate = Offset(
      40 + (i % columns) * gapX,
      40 + (i ~/ columns) * gapY,
    );
    if (!used.any((point) => (point - candidate).distance < 20)) {
      return candidate;
    }
  }
}

/// The bounds every box occupies, for framing the view on the whole machine.
///
/// Null when there is nothing to frame.
Rect? animatorGraphBounds(Iterable<Offset> positions) {
  Rect? bounds;
  for (final position in positions) {
    final rect = animatorStateRect(position);
    bounds = bounds == null ? rect : bounds.expandToInclude(rect);
  }
  return bounds;
}

/// How near the pointer has to be to an arrow to be clicking it.
const double animatorArrowHitSlop = 7;

/// Whether [point] is on the segment from [start] to [end], within
/// [animatorArrowHitSlop].
///
/// An arrow is a line, and a line has no area to hit-test against, so picking
/// one is a distance test rather than a containment one.
bool animatorArrowHit(Offset start, Offset end, Offset point) {
  final along = end - start;
  final lengthSquared = along.distanceSquared;
  if (lengthSquared < 1e-6) {
    return (point - start).distance <= animatorArrowHitSlop;
  }
  final t =
      (((point - start).dx * along.dx + (point - start).dy * along.dy) /
              lengthSquared)
          .clamp(0.0, 1.0);
  final nearest = start + along * t;
  return (point - nearest).distance <= animatorArrowHitSlop;
}
