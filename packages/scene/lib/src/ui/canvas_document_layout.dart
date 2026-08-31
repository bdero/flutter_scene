/// Solving a canvas layout straight from a document.
///
/// The runtime lays out live nodes; the editor has to lay out what the
/// document says right now, before any of it is realized, so a rectangle
/// dragged in the inspector moves in the viewport on the same frame. Same
/// arithmetic either way — [solveRect] — over a different tree.
library;

import 'package:scene/src/id.dart';
import 'package:scene/src/property_value.dart';
import 'package:scene/src/scene_document.dart';
import 'package:scene/src/specs.dart';
import 'package:scene/src/ui/rect_layout.dart';

/// The component type that makes a node a canvas.
const String canvasComponentType = 'canvas';

/// The component type that gives a node a rectangle inside one.
const String rectTransformComponentType = 'rectTransform';

/// One node's solved rectangle, and how deep under the canvas it sits.
class SolvedRect {
  const SolvedRect({
    required this.node,
    required this.rect,
    required this.depth,
  });

  /// The node this rectangle belongs to.
  final LocalId node;

  /// Its rectangle in canvas units, Y-up.
  final UiRect rect;

  /// How many rectangles deep it is, the canvas being 0. Lets a drawing
  /// layer fade nesting without walking the tree again.
  final int depth;
}

/// The canvas rectangle of [node], or null when it carries no canvas.
///
/// Screen-space canvases report the reference size they were authored
/// against; a world-space canvas reports its size in world units. This
/// mirrors `CanvasComponent.rect` and is kept in step with it by
/// `canvas_layout_parity_test.dart`.
UiRect? canvasRectOf(NodeSpec node) {
  final canvas = _componentOfType(node, canvasComponentType);
  if (canvas == null) return null;
  final worldSpace =
      _string(canvas, 'renderMode', 'screenSpaceOverlay') == 'worldSpace';
  return worldSpace
      ? UiRect.size(
          _number(canvas, 'worldWidth', 1.6),
          _number(canvas, 'worldHeight', 0.9),
        )
      : UiRect.size(
          _positive(_number(canvas, 'referenceWidth', 1920)),
          _positive(_number(canvas, 'referenceHeight', 1080)),
        );
}

/// Whether [node] is a canvas.
bool isCanvasNode(NodeSpec node) =>
    _componentOfType(node, canvasComponentType) != null;

/// Solves every rectangle under the canvas at [canvasNode].
///
/// Parents before children, siblings in document order, which is also the
/// order they should be drawn in. A node with no rectangle of its own still
/// passes its parent's down, so a grouping node does not break the chain, and
/// a nested canvas is left for its own pass.
///
/// Returns an empty list when [canvasNode] is missing or is not a canvas.
List<SolvedRect> solveCanvasLayout(SceneDocument document, LocalId canvasNode) {
  final root = document.node(canvasNode);
  if (root == null) return const [];
  final canvasRect = canvasRectOf(root);
  if (canvasRect == null) return const [];

  final out = <SolvedRect>[];
  // Guards a document whose children form a cycle, which a hand-edited or
  // partially merged file can. Without it the walk never returns.
  final seen = <LocalId>{canvasNode};

  void visit(LocalId id, UiRect parentRect, int depth) {
    if (!seen.add(id)) return;
    final node = document.node(id);
    if (node == null) return;
    if (isCanvasNode(node)) return;

    var rect = parentRect;
    var childDepth = depth;
    final transform = _componentOfType(node, rectTransformComponentType);
    if (transform != null) {
      rect = solveRect(parentRect, _valuesOf(transform));
      out.add(SolvedRect(node: id, rect: rect, depth: depth));
      childDepth = depth + 1;
    }
    for (final child in node.children) {
      visit(child, rect, childDepth);
    }
  }

  for (final child in root.children) {
    visit(child, canvasRect, 1);
  }
  return out;
}

RectTransformValues _valuesOf(ComponentSpec spec) => RectTransformValues(
  anchorMinX: _number(spec, 'anchorMinX', 0.5),
  anchorMinY: _number(spec, 'anchorMinY', 0.5),
  anchorMaxX: _number(spec, 'anchorMaxX', 0.5),
  anchorMaxY: _number(spec, 'anchorMaxY', 0.5),
  pivotX: _number(spec, 'pivotX', 0.5),
  pivotY: _number(spec, 'pivotY', 0.5),
  anchoredX: _number(spec, 'anchoredX', 0),
  anchoredY: _number(spec, 'anchoredY', 0),
  sizeDeltaX: _number(spec, 'sizeDeltaX', 100),
  sizeDeltaY: _number(spec, 'sizeDeltaY', 100),
);

ComponentSpec? _componentOfType(NodeSpec node, String type) {
  for (final component in node.components) {
    if (component.type == type) return component;
  }
  return null;
}

double _number(ComponentSpec spec, String key, double fallback) =>
    switch (spec.properties[key]) {
      DoubleValue(:final value) => value,
      IntValue(:final value) => value.toDouble(),
      _ => fallback,
    };

String _string(ComponentSpec spec, String key, String fallback) =>
    switch (spec.properties[key]) {
      StringValue(:final value) => value,
      _ => fallback,
    };

/// A reference size of zero would make every layout infinite; the component
/// refuses one and so does this.
double _positive(double value) => value <= 0 ? 1 : value;
