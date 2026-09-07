import 'package:flutter_scene/src/components/component.dart';
import 'package:scene/scene.dart' show RectTransformValues, UiRect, solveRect;

/// Where a node's rectangle sits inside the one containing it.
///
/// Attaches a node to its parent rectangle rather than giving it a position:
/// two anchors at one point make a fixed size that follows that point, two
/// anchors apart make a rectangle that stretches. See [solveRect], which is
/// the whole of the layout.
///
/// A node with this component and no ancestor carrying a `CanvasComponent`
/// has nothing to lay out against and is skipped.
/// {@category UI}
class RectTransformComponent extends Component {
  RectTransformComponent({
    this.anchorMinX = 0.5,
    this.anchorMinY = 0.5,
    this.anchorMaxX = 0.5,
    this.anchorMaxY = 0.5,
    this.pivotX = 0.5,
    this.pivotY = 0.5,
    this.anchoredX = 0,
    this.anchoredY = 0,
    this.sizeDeltaX = 100,
    this.sizeDeltaY = 100,
  });

  /// Fills the parent rectangle, with [inset] on every side.
  RectTransformComponent.stretch({double inset = 0})
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

  double anchorMinX;
  double anchorMinY;
  double anchorMaxX;
  double anchorMaxY;
  double pivotX;
  double pivotY;
  double anchoredX;
  double anchoredY;
  double sizeDeltaX;
  double sizeDeltaY;

  /// This component's numbers, for [solveRect].
  RectTransformValues get values => RectTransformValues(
    anchorMinX: anchorMinX,
    anchorMinY: anchorMinY,
    anchorMaxX: anchorMaxX,
    anchorMaxY: anchorMaxY,
    pivotX: pivotX,
    pivotY: pivotY,
    anchoredX: anchoredX,
    anchoredY: anchoredY,
    sizeDeltaX: sizeDeltaX,
    sizeDeltaY: sizeDeltaY,
  );

  /// This rectangle inside [parent].
  UiRect solveIn(UiRect parent) => solveRect(parent, values);
}
