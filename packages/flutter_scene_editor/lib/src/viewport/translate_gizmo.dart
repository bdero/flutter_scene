import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Axis index constants.
const int axisX = 0;
const int axisY = 1;
const int axisZ = 2;

/// Projects a world-space point to screen pixels for the given camera and view
/// size. Returns null when the point is behind the camera.
Offset? projectToScreen(vm.Vector3 worldPoint, Camera camera, Size viewSize) {
  final vp = camera.getViewTransform(viewSize);
  final clip = vp.transform(
    vm.Vector4(worldPoint.x, worldPoint.y, worldPoint.z, 1),
  );
  if (clip.w <= 0) return null;
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  return Offset(
    (ndcX * 0.5 + 0.5) * viewSize.width,
    (1 - (ndcY * 0.5 + 0.5)) * viewSize.height,
  );
}

double _distToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final ap = point - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-6) return (point - a).distance;
  final t = (ap.dx * ab.dx + ap.dy * ab.dy) / len2;
  final clamped = t.clamp(0.0, 1.0);
  final closest = a + Offset(ab.dx * clamped, ab.dy * clamped);
  return (point - closest).distance;
}

/// A translate gizmo overlaid as a [CustomPainter] on the viewport.
///
/// Draws three axis handles (+X = red, +Y = green, +Z = blue) anchored at
/// [nodePosition] in world space. Reports which axis is active through
/// [activeAxis].
class TranslateGizmoPainter extends CustomPainter {
  TranslateGizmoPainter({
    required this.nodePosition,
    required this.camera,
    required this.activeAxis,
  });

  final vm.Vector3 nodePosition;
  final Camera camera;
  final int? activeAxis;

  static const double _armWorldUnits = 1.2;

  vm.Vector3 get _origin => nodePosition;

  double _scaleForScreen(Size size) {
    final dist = (camera.position - _origin).length;
    return dist * 80 / (size.height * 0.7);
  }

  vm.Vector3 _tip(int axis, double scale) {
    return switch (axis) {
      axisX => _origin + vm.Vector3(scale * _armWorldUnits, 0, 0),
      axisY => _origin + vm.Vector3(0, scale * _armWorldUnits, 0),
      _ => _origin + vm.Vector3(0, 0, scale * _armWorldUnits),
    };
  }

  static const _colors = [
    Color(0xFFE84040), // X red
    Color(0xFF40C840), // Y green
    Color(0xFF4080E8), // Z blue
  ];

  static const _activeColor = Color(0xFFFFDD44);

  @override
  void paint(Canvas canvas, Size size) {
    final origin = projectToScreen(_origin, camera, size);
    if (origin == null) return;

    final scale = _scaleForScreen(size);

    for (var axis = 0; axis < 3; axis++) {
      final tip = projectToScreen(_tip(axis, scale), camera, size);
      if (tip == null) continue;

      final isActive = activeAxis == axis;
      final color = isActive ? _activeColor : _colors[axis];
      final paint = Paint()
        ..color = color
        ..strokeWidth = isActive ? 3.0 : 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(origin, tip, paint);

      final dir = tip - origin;
      final len = dir.distance;
      if (len < 1e-3) continue;
      final norm = dir / len;
      final perp = Offset(-norm.dy, norm.dx);
      final headBase = tip - norm * min(12, len * 0.3);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(headBase.dx + perp.dx * 4, headBase.dy + perp.dy * 4)
        ..lineTo(headBase.dx - perp.dx * 4, headBase.dy - perp.dy * 4)
        ..close();
      canvas.drawPath(path, Paint()..color = color);

      final label = switch (axis) {
        axisX => 'X',
        axisY => 'Y',
        _ => 'Z',
      };
      final labelOffset = tip + norm * 8;
      _drawLabel(canvas, label, labelOffset, color);
    }

    canvas.drawCircle(origin, 4, Paint()..color = const Color(0xFFFFFFFF));
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 20);
    tp.paint(canvas, pos - const Offset(5, 6));
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;
}

/// State manager for gizmo hit-testing and drag.
///
/// Call [hitTest] on pointer-down to see which axis (if any) was clicked.
/// Call [dragDelta] on pointer-move to compute the world-space translation
/// for the active axis.
class GizmoController {
  int? activeAxis;

  Offset? _dragStart;
  Offset? _axisTipScreen;
  Offset? _axisOriginScreen;

  static const double _hitRadius = 12.0;
  static const double _armWorldUnits = 1.2;

  vm.Vector3 _tip(vm.Vector3 origin, int axis, double scale) {
    return switch (axis) {
      axisX => origin + vm.Vector3(scale * _armWorldUnits, 0, 0),
      axisY => origin + vm.Vector3(0, scale * _armWorldUnits, 0),
      _ => origin + vm.Vector3(0, 0, scale * _armWorldUnits),
    };
  }

  double _scaleForScreen(vm.Vector3 origin, Camera camera, Size viewSize) {
    final dist = (camera.position - origin).length;
    return dist * 80 / (viewSize.height * 0.7);
  }

  /// Tests [screenPos] against the gizmo handles. Returns the axis index (0-2)
  /// or null if no handle was hit. Call on pointer-down.
  int? hitTest(
    Offset screenPos,
    vm.Vector3 nodePosition,
    Camera camera,
    Size viewSize,
  ) {
    final origin = projectToScreen(nodePosition, camera, viewSize);
    if (origin == null) return null;

    final scale = _scaleForScreen(nodePosition, camera, viewSize);
    int? bestAxis;
    double bestDist = _hitRadius;

    for (var axis = 0; axis < 3; axis++) {
      final tip = projectToScreen(
        _tip(nodePosition, axis, scale),
        camera,
        viewSize,
      );
      if (tip == null) continue;
      final d = _distToSegment(screenPos, origin, tip);
      if (d < bestDist) {
        bestDist = d;
        bestAxis = axis;
      }
    }

    if (bestAxis != null) {
      activeAxis = bestAxis;
      _dragStart = screenPos;
      _axisOriginScreen = origin;
      _axisTipScreen = projectToScreen(
        _tip(nodePosition, bestAxis, scale),
        camera,
        viewSize,
      );
    }
    return bestAxis;
  }

  /// Converts a screen-space pointer position to a world-space translation
  /// delta along [activeAxis]. Returns zero if no axis is active.
  vm.Vector3 dragDelta(
    Offset currentPos,
    vm.Vector3 nodePosition,
    Camera camera,
    Size viewSize,
  ) {
    final axis = activeAxis;
    if (axis == null) return vm.Vector3.zero();

    final origin = _axisOriginScreen;
    final tip = _axisTipScreen;
    if (origin == null || tip == null) return vm.Vector3.zero();

    final axisSc = tip - origin;
    final len2 = axisSc.dx * axisSc.dx + axisSc.dy * axisSc.dy;
    if (len2 < 1e-6) return vm.Vector3.zero();

    final start = _dragStart ?? origin;
    final drag = currentPos - start;
    final dot = (drag.dx * axisSc.dx + drag.dy * axisSc.dy) / sqrt(len2);

    final screenLen = sqrt(len2);
    final worldLen =
        _armWorldUnits * _scaleForScreen(nodePosition, camera, viewSize);
    final pixelToWorld = screenLen > 1e-3 ? worldLen / screenLen : 0.0;
    final worldDist = dot * pixelToWorld;

    _dragStart = currentPos;

    return switch (axis) {
      axisX => vm.Vector3(worldDist, 0, 0),
      axisY => vm.Vector3(0, worldDist, 0),
      _ => vm.Vector3(0, 0, worldDist),
    };
  }

  void endDrag() {
    activeAxis = null;
    _dragStart = null;
    _axisOriginScreen = null;
    _axisTipScreen = null;
  }
}
