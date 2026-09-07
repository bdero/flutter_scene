/// Solving a canvas subtree into rectangles.
///
/// One pass, parents before children, because a child's rectangle is measured
/// against its parent's and nothing else. A node with a
/// [RectTransformComponent] but no rect-bearing ancestor under the canvas
/// lays out against the canvas itself, which is what "put this on the HUD"
/// should mean without an intervening panel.
///
/// The result is Y-up canvas units. Converting to Flutter's Y-down screen
/// space is the drawing layer's job, not this one's.
library;

import 'package:flutter_scene/src/components/canvas_component.dart';
import 'package:flutter_scene/src/components/rect_transform_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:scene/scene.dart' show UiRect;

/// One laid-out node.
class LaidOutRect {
  const LaidOutRect(this.node, this.rect);

  final Node node;
  final UiRect rect;
}

/// Lays out [canvasNode]'s subtree, given the view's logical size.
///
/// Returns the nodes carrying a [RectTransformComponent], in the order they
/// should be drawn: parents before children, siblings in scene order. Nodes
/// without one are still descended through, so a plain grouping node between
/// a panel and its contents does not break the chain — it passes its parent's
/// rectangle down.
///
/// Returns an empty list when [canvasNode] carries no [CanvasComponent].
List<LaidOutRect> layOutCanvas(
  Node canvasNode, {
  required double viewWidth,
  required double viewHeight,
}) {
  final canvas = canvasNode.getComponent<CanvasComponent>();
  if (canvas == null) return const [];

  final out = <LaidOutRect>[];
  void visit(Node node, UiRect parentRect) {
    var rect = parentRect;
    final transform = node.getComponent<RectTransformComponent>();
    if (transform != null) {
      rect = transform.solveIn(parentRect);
      out.add(LaidOutRect(node, rect));
    }
    for (final child in node.children) {
      // A nested canvas is a root of its own: it decides its own size, so it
      // does not inherit a rectangle from above.
      if (child.getComponent<CanvasComponent>() != null) continue;
      visit(child, rect);
    }
  }

  final canvasRect = canvas.rect(viewWidth: viewWidth, viewHeight: viewHeight);
  for (final child in canvasNode.children) {
    if (child.getComponent<CanvasComponent>() != null) continue;
    visit(child, canvasRect);
  }
  return out;
}
