/// Drawing UI layout in the viewport.
///
/// A canvas has nothing to render until something is put on it, so without
/// this a UI layout is invisible while you build it: the hierarchy fills up
/// and the scene stays empty. This draws the rectangles — the canvas itself
/// and every rect transform under it — so where a label or a button will sit
/// is something you can see and drag toward rather than infer from ten
/// numbers in the inspector.
///
/// Rectangles come from the document rather than the realized scene, so they
/// follow an inspector edit on the same frame, the way the component gizmos
/// do. World transforms come from the live node, which is the only place
/// they exist.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart' as doc;
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import 'component_gizmos.dart' show GizmoPreferences;
import 'transform_gizmo.dart' show projectToScreen;

/// The gizmo type name this layer draws for, so the View menu can hide it
/// alongside the component gizmos.
const String canvasGizmoType = 'canvas';

const Color _canvasColor = Color(0xCC4E86DE);
const Color _rectColor = Color(0x99B9C4CE);
const Color _selectedColor = Color(0xFFFF8C1A);

/// Below this many pixels a rectangle is too small to label legibly, so it
/// gets its outline and nothing else.
const double _labelMinimumSize = 44;

/// Draws every canvas in the scene and the rectangles laid out on it.
class CanvasOverlayPainter extends CustomPainter {
  CanvasOverlayPainter({
    required this.controller,
    required this.camera,
    required this.preferences,
  }) : super(repaint: preferences);

  final EditorController controller;
  final Camera camera;
  final GizmoPreferences preferences;

  @override
  void paint(Canvas canvas, Size size) {
    if (!preferences.isTypeVisible(canvasGizmoType)) return;
    _visit(controller.scene.root, canvas, size);
  }

  void _visit(Node node, Canvas canvas, Size size) {
    final component = node.getComponent<CanvasComponent>();
    if (component != null) {
      _paintCanvas(node, component, canvas, size);
      // A canvas's subtree is drawn by that canvas, but a canvas nested
      // deeper is its own root and still needs visiting.
    }
    for (final child in node.children) {
      _visit(child, canvas, size);
    }
  }

  void _paintCanvas(
    Node node,
    CanvasComponent component,
    Canvas canvas,
    Size size,
  ) {
    final sourceId = controller.sourceIdForLiveNode(node);
    if (sourceId == null) return;
    final spec = controller.document.node(sourceId);
    if (spec == null) return;
    final canvasRect = doc.canvasRectOf(spec);
    if (canvasRect == null) return;

    final rects = doc.solveCanvasLayout(controller.document, sourceId);
    final worldSpace = component.renderMode == CanvasRenderMode.worldSpace;

    // A projection from canvas units to the viewport, whichever mode this
    // canvas is in. Returns null for a corner behind the camera.
    List<Offset>? cornersOf(doc.UiRect rect) => worldSpace
        ? _projectWorldRect(node, component, rect, size)
        : _fitScreenRect(component, rect, size);

    final canvasCorners = cornersOf(canvasRect);
    if (canvasCorners != null) {
      _strokeQuad(
        canvas,
        canvasCorners,
        _isSelected(sourceId) ? _selectedColor : _canvasColor,
        _isSelected(sourceId) ? 2.0 : 1.5,
      );
      _label(canvas, canvasCorners, spec.name, _canvasColor);
    }

    for (final solved in rects) {
      final corners = cornersOf(solved.rect);
      if (corners == null) continue;
      final selected = _isSelected(solved.node);
      _strokeQuad(
        canvas,
        corners,
        selected ? _selectedColor : _rectColor,
        selected ? 2.0 : 1.0,
      );
      if (selected) _paintPivot(canvas, node, component, solved, size);
      final name = controller.document.node(solved.node)?.name ?? '';
      if (name.isNotEmpty) {
        _label(canvas, corners, name, selected ? _selectedColor : _rectColor);
      }
    }
  }

  bool _isSelected(doc.LocalId id) => controller.selection.contains(id);

  /// The four corners of [rect] for a screen-space canvas, letterboxed into
  /// the viewport exactly as the canvas will be, and flipped: canvas
  /// coordinates are Y-up, the viewport is Y-down.
  List<Offset> _fitScreenRect(
    CanvasComponent component,
    doc.UiRect rect,
    Size size,
  ) {
    final scale = component.scaleFor(
      viewWidth: size.width,
      viewHeight: size.height,
    );
    final drawnWidth = component.referenceWidth * scale;
    final drawnHeight = component.referenceHeight * scale;
    final originX = (size.width - drawnWidth) / 2;
    final originY = (size.height - drawnHeight) / 2;

    double x(double canvasX) => originX + canvasX * scale;
    double y(double canvasY) =>
        originY + (component.referenceHeight - canvasY) * scale;

    return [
      Offset(x(rect.left), y(rect.top)),
      Offset(x(rect.right), y(rect.top)),
      Offset(x(rect.right), y(rect.bottom)),
      Offset(x(rect.left), y(rect.bottom)),
    ];
  }

  /// The four corners of [rect] for a world-space canvas, through the camera.
  ///
  /// The canvas is centred on its node, so a canvas node behaves like
  /// anything else in the scene: it is where you put it, not offset by half
  /// its size from there.
  List<Offset>? _projectWorldRect(
    Node node,
    CanvasComponent component,
    doc.UiRect rect,
    Size size,
  ) {
    final transform = node.globalTransform;
    final halfWidth = component.worldWidth / 2;
    final halfHeight = component.worldHeight / 2;

    Offset? project(double canvasX, double canvasY) {
      final local = vm.Vector3(canvasX - halfWidth, canvasY - halfHeight, 0);
      return projectToScreen(transform.transformed3(local), camera, size);
    }

    final corners = [
      project(rect.left, rect.top),
      project(rect.right, rect.top),
      project(rect.right, rect.bottom),
      project(rect.left, rect.bottom),
    ];
    // Any corner behind the camera makes the whole quad meaningless on
    // screen; drawing three of four would draw a shape that is not there.
    if (corners.any((corner) => corner == null)) return null;
    return corners.cast<Offset>();
  }

  void _strokeQuad(
    Canvas canvas,
    List<Offset> corners,
    Color color,
    double width,
  ) {
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  /// A cross at the pivot of the selected rectangle: the point its position
  /// is measured from, which is otherwise invisible and is what makes an
  /// offset behave the way it does.
  void _paintPivot(
    Canvas canvas,
    Node node,
    CanvasComponent component,
    doc.SolvedRect solved,
    Size size,
  ) {
    final transform = controller.document
        .node(solved.node)
        ?.components
        .where((c) => c.type == doc.rectTransformComponentType)
        .firstOrNull;
    if (transform == null) return;
    double read(String key, double fallback) =>
        switch (transform.properties[key]) {
          doc.DoubleValue(:final value) => value,
          _ => fallback,
        };
    final (pivotX, pivotY) = solved.rect.fractionOf(
      read('pivotX', 0.5),
      read('pivotY', 0.5),
    );
    final point = component.renderMode == CanvasRenderMode.worldSpace
        ? _projectWorldRect(
            node,
            component,
            doc.UiRect(left: pivotX, bottom: pivotY, width: 0, height: 0),
            size,
          )?.first
        : _fitScreenRect(
            component,
            doc.UiRect(left: pivotX, bottom: pivotY, width: 0, height: 0),
            size,
          ).first;
    if (point == null) return;

    final paint = Paint()
      ..color = _selectedColor
      ..strokeWidth = 1.5;
    const arm = 5.0;
    canvas
      ..drawLine(point.translate(-arm, 0), point.translate(arm, 0), paint)
      ..drawLine(point.translate(0, -arm), point.translate(0, arm), paint);
  }

  void _label(Canvas canvas, List<Offset> corners, String text, Color color) {
    if (text.isEmpty) return;
    final topLeft = corners[0];
    final width = (corners[1] - corners[0]).distance;
    final height = (corners[3] - corners[0]).distance;
    if (width < _labelMinimumSize || height < _labelMinimumSize) return;

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width - 6);
    painter.paint(canvas, topLeft.translate(3, 2));
  }

  @override
  bool shouldRepaint(CanvasOverlayPainter old) => true;
}
