/// Laying a UI rectangle out inside its parent.
///
/// The whole of the layout is one function, [solveRect]. A child says where
/// it attaches to its parent ([RectTransformValues.anchorMin] and
/// [RectTransformValues.anchorMax], in fractions of the parent), which point
/// of itself that attachment positions ([RectTransformValues.pivot]), how far
/// from there it sits ([RectTransformValues.anchoredPosition]), and how much
/// bigger than its anchors it is ([RectTransformValues.sizeDelta]).
///
/// Two anchors at the same point make a rectangle of a fixed size that follows
/// that point as the parent resizes. Two anchors apart make one that stretches
/// with the parent, with [RectTransformValues.sizeDelta] as the inset. That
/// one idea covers a centred dialog, a full-bleed backdrop, a bar pinned to
/// the bottom, and a health bar in a corner, without a mode switch between
/// them.
///
/// Coordinates are Y-up, like the rest of the scene: anchor `(0, 0)` is the
/// parent's bottom-left. Flutter's screen space is Y-down, and the conversion
/// happens where a canvas meets Flutter rather than here, so that a
/// world-space canvas -- which is in the scene, where Y is up -- needs no
/// special case.
///
/// Pure geometry: no Flutter, no GPU, so it is the same answer in the editor,
/// at runtime, and in a build hook.
library;

/// An axis-aligned rectangle in a canvas, Y-up.
class UiRect {
  const UiRect({
    required this.left,
    required this.bottom,
    required this.width,
    required this.height,
  });

  /// A rectangle of [width] by [height] with its bottom-left at the origin,
  /// which is what a canvas's own rectangle is.
  const UiRect.size(this.width, this.height) : left = 0, bottom = 0;

  final double left;
  final double bottom;
  final double width;
  final double height;

  double get right => left + width;
  double get top => bottom + height;

  /// The point at [x], [y] fractions across the rectangle: `(0, 0)` is the
  /// bottom-left corner, `(1, 1)` the top-right, `(0.5, 0.5)` the centre.
  (double, double) fractionOf(double x, double y) =>
      (left + width * x, bottom + height * y);

  @override
  String toString() =>
      'UiRect(left: $left, bottom: $bottom, width: $width, height: $height)';

  @override
  bool operator ==(Object other) =>
      other is UiRect &&
      other.left == left &&
      other.bottom == bottom &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, bottom, width, height);
}

/// How a rectangle attaches to its parent.
///
/// The five numbers a `rectTransform` component carries, as plain doubles so
/// this stays free of a vector library.
class RectTransformValues {
  const RectTransformValues({
    this.anchorMinX = 0.5,
    this.anchorMinY = 0.5,
    this.anchorMaxX = 0.5,
    this.anchorMaxY = 0.5,
    this.pivotX = 0.5,
    this.pivotY = 0.5,
    this.anchoredX = 0.0,
    this.anchoredY = 0.0,
    this.sizeDeltaX = 100.0,
    this.sizeDeltaY = 100.0,
  });

  /// Stretches to fill its parent, with [inset] on every side.
  const RectTransformValues.stretch({double inset = 0})
    : anchorMinX = 0,
      anchorMinY = 0,
      anchorMaxX = 1,
      anchorMaxY = 1,
      pivotX = 0.5,
      pivotY = 0.5,
      anchoredX = 0,
      anchoredY = 0,
      sizeDeltaX = -2 * inset,
      sizeDeltaY = -2 * inset;

  /// The lower-left corner of the anchor region, in fractions of the parent.
  final double anchorMinX;
  final double anchorMinY;

  /// The upper-right corner of the anchor region, in fractions of the parent.
  final double anchorMaxX;
  final double anchorMaxY;

  /// The point of this rectangle that [anchoredX]/[anchoredY] positions, in
  /// fractions of its own size.
  final double pivotX;
  final double pivotY;

  /// The pivot's offset from the anchor reference point, in canvas units.
  final double anchoredX;
  final double anchoredY;

  /// Size beyond the anchor region. With anchors at one point this is the
  /// size outright; with anchors apart it is the inset (negative shrinks).
  final double sizeDeltaX;
  final double sizeDeltaY;

  /// Whether the anchors span any width, so the rectangle stretches
  /// horizontally rather than holding a fixed width.
  bool get stretchesHorizontally => anchorMaxX != anchorMinX;

  /// Whether the anchors span any height.
  bool get stretchesVertically => anchorMaxY != anchorMinY;
}

/// The rectangle [values] describes inside [parent].
///
/// The anchor region is the slice of [parent] between the two anchors. The
/// rectangle is that region grown by `sizeDelta`, positioned so its pivot
/// sits `anchored` away from the same fractional point of the anchor region.
/// Taking the reference point at the *pivot's* fraction is what makes a
/// top-right-anchored, top-right-pivoted rectangle hold its distance from the
/// corner it is pinned to.
///
/// Anchors are not clamped or ordered: a max below a min yields a negative
/// span and, with `sizeDelta` covering it, still a sane rectangle. Width and
/// height are clamped at zero, because a negative-size rectangle has no
/// meaning downstream and is a nuisance to guard at every use.
UiRect solveRect(UiRect parent, RectTransformValues values) {
  final anchorLeft = parent.left + parent.width * values.anchorMinX;
  final anchorBottom = parent.bottom + parent.height * values.anchorMinY;
  final anchorWidth = parent.width * (values.anchorMaxX - values.anchorMinX);
  final anchorHeight = parent.height * (values.anchorMaxY - values.anchorMinY);

  final width = anchorWidth + values.sizeDeltaX;
  final height = anchorHeight + values.sizeDeltaY;

  final referenceX = anchorLeft + anchorWidth * values.pivotX;
  final referenceY = anchorBottom + anchorHeight * values.pivotY;
  final pivotXPosition = referenceX + values.anchoredX;
  final pivotYPosition = referenceY + values.anchoredY;

  return UiRect(
    left: pivotXPosition - width * values.pivotX,
    bottom: pivotYPosition - height * values.pivotY,
    width: width < 0 ? 0 : width,
    height: height < 0 ? 0 : height,
  );
}
