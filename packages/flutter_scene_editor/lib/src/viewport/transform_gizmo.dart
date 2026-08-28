import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../shell/editor_theme.dart';

/// Axis index constants. [axisUniform] is the scale gizmo's center handle.
const int axisX = 0;
const int axisY = 1;
const int axisZ = 2;
const int axisUniform = 3;

/// The transform the gizmo edits.
enum GizmoMode { translate, rotate, scale }

/// The coordinate space used to orient and apply a transform gizmo.
enum TransformSpace { global, local }

/// Projects a global-space point to screen pixels. Returns null when behind the
/// camera.
Offset? projectToScreen(vm.Vector3 globalPoint, Camera camera, Size viewSize) {
  final vp = camera.getViewTransform(viewSize);
  final clip = vp.transform(
    vm.Vector4(globalPoint.x, globalPoint.y, globalPoint.z, 1),
  );
  if (clip.w <= 0) return null;
  return Offset(
    (clip.x / clip.w * 0.5 + 0.5) * viewSize.width,
    (1 - (clip.y / clip.w * 0.5 + 0.5)) * viewSize.height,
  );
}

double _distToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final ap = point - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-6) return (point - a).distance;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (point - (a + Offset(ab.dx * t, ab.dy * t))).distance;
}

vm.Vector3 _globalAxisDir(int axis) => switch (axis) {
  axisX => vm.Vector3(1, 0, 0),
  axisY => vm.Vector3(0, 1, 0),
  _ => vm.Vector3(0, 0, 1),
};

/// Returns global directions for the three axes of [space].
List<vm.Vector3> transformSpaceAxes(
  TransformSpace space,
  vm.Matrix4 globalTransform,
) {
  if (space == TransformSpace.global) {
    return [
      _globalAxisDir(axisX),
      _globalAxisDir(axisY),
      _globalAxisDir(axisZ),
    ];
  }
  return [
    for (var axis = 0; axis < 3; axis++)
      _normalizedTransformAxis(globalTransform, axis),
  ];
}

vm.Vector3 _normalizedTransformAxis(vm.Matrix4 transform, int axis) {
  final direction = vm.Vector3(
    transform.entry(0, axis),
    transform.entry(1, axis),
    transform.entry(2, axis),
  );
  if (direction.length2 < 1e-12) return _globalAxisDir(axis);
  return direction..normalize();
}

/// Solves the local transform for a desired global transform.
vm.Matrix4 globalToLocalTransform(
  vm.Matrix4 desiredGlobal,
  vm.Matrix4 parentGlobalInverse,
) => parentGlobalInverse * desiredGlobal;

/// Converts an interaction angle about a displayed local axis into the
/// node's local quaternion angle. A mirrored global basis reverses rotation.
double localAxisRotationAngle(
  double interactionAngle,
  vm.Matrix4 globalTransform,
) => globalTransform.determinant() < 0 ? -interactionAngle : interactionAngle;

const _axisColors = editorAxisColors;
const _activeColor = Color(0xFFFFDD44);
const _uniformColor = Color(0xFFCCCCCC);
const double _armGlobalUnits = 1.2;

double _gizmoScale(vm.Vector3 origin, Camera camera, Size size) {
  final dist = (camera.position - origin).length;
  return dist * 40 / (size.height * 0.7);
}

/// Points around the ring of [axis] (a circle of [radius] in the plane
/// perpendicular to the axis), in global space.
List<vm.Vector3> _ringPoints(
  vm.Vector3 origin,
  int axis,
  double radius, [
  List<vm.Vector3>? axes,
]) {
  final basis =
      axes ??
      [_globalAxisDir(axisX), _globalAxisDir(axisY), _globalAxisDir(axisZ)];
  final u = basis[(axis + 1) % 3] * radius;
  final v = basis[(axis + 2) % 3] * radius;
  return [
    for (var i = 0; i <= 48; i++)
      origin + u * cos(i / 48 * 2 * pi) + v * sin(i / 48 * 2 * pi),
  ];
}

/// Draws the transform gizmo for the active [mode] at global [origin].
class TransformGizmoPainter extends CustomPainter {
  TransformGizmoPainter({
    required this.origin,
    required this.mode,
    required this.axes,
    required this.camera,
    required this.activeAxis,
  });

  final vm.Vector3 origin;
  final GizmoMode mode;
  final List<vm.Vector3> axes;
  final Camera camera;
  final int? activeAxis;

  @override
  void paint(Canvas canvas, Size size) {
    final originScreen = projectToScreen(origin, camera, size);
    if (originScreen == null) return;
    final scale = _gizmoScale(origin, camera, size) * _armGlobalUnits;

    switch (mode) {
      case GizmoMode.translate:
        _paintArrows(canvas, size, originScreen, scale);
      case GizmoMode.rotate:
        _paintRings(canvas, size, scale);
      case GizmoMode.scale:
        _paintScaleHandles(canvas, size, originScreen, scale);
    }
    canvas.drawCircle(
      originScreen,
      4,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  Color _color(int axis) =>
      activeAxis == axis ? _activeColor : _axisColors[axis];

  void _paintArrows(Canvas canvas, Size size, Offset o, double scale) {
    for (var axis = 0; axis < 3; axis++) {
      final tip = projectToScreen(origin + axes[axis] * scale, camera, size);
      if (tip == null) continue;
      final color = _color(axis);
      canvas.drawLine(
        o,
        tip,
        Paint()
          ..color = color
          ..strokeWidth = activeAxis == axis ? 3 : 2.5
          ..strokeCap = StrokeCap.round,
      );
      final dir = tip - o;
      final len = dir.distance;
      if (len < 1e-3) continue;
      final norm = dir / len;
      final perp = Offset(-norm.dy, norm.dx);
      final base = tip - norm * min(12, len * 0.3);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + perp.dx * 4, base.dy + perp.dy * 4)
          ..lineTo(base.dx - perp.dx * 4, base.dy - perp.dy * 4)
          ..close(),
        Paint()..color = color,
      );
    }
  }

  void _paintRings(Canvas canvas, Size size, double radius) {
    for (var axis = 0; axis < 3; axis++) {
      final path = Path();
      var started = false;
      for (final p in _ringPoints(origin, axis, radius, axes)) {
        final s = projectToScreen(p, camera, size);
        if (s == null) continue;
        if (started) {
          path.lineTo(s.dx, s.dy);
        } else {
          path.moveTo(s.dx, s.dy);
          started = true;
        }
      }
      if (!started) continue;
      canvas.drawPath(
        path,
        Paint()
          ..color = _color(axis)
          ..strokeWidth = activeAxis == axis ? 3 : 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintScaleHandles(Canvas canvas, Size size, Offset o, double scale) {
    for (var axis = 0; axis < 3; axis++) {
      final tip = projectToScreen(origin + axes[axis] * scale, camera, size);
      if (tip == null) continue;
      final color = _color(axis);
      canvas.drawLine(
        o,
        tip,
        Paint()
          ..color = color
          ..strokeWidth = activeAxis == axis ? 3 : 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawRect(
        Rect.fromCenter(center: tip, width: 9, height: 9),
        Paint()..color = color,
      );
    }
    // Uniform-scale center handle.
    canvas.drawRect(
      Rect.fromCenter(center: o, width: 11, height: 11),
      Paint()
        ..color = activeAxis == axisUniform ? _activeColor : _uniformColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;
}

/// Hit-tests the gizmo and accumulates a drag as a translation, a rotation
/// (angle about [axisVec]), or a per-axis scale, depending on [mode].
class GizmoController {
  GizmoMode mode = GizmoMode.translate;
  int? activeAxis;

  // Raw accumulated drag since [grab]. The viewport reads the snapped
  // getters below; snapping the running total rather than each delta is what
  // keeps a dragged node on the grid instead of drifting off it by a
  // fraction of a step per frame.
  vm.Vector3 _translation = vm.Vector3.zero();
  double _angle = 0;
  vm.Vector3 _scale = vm.Vector3(1, 1, 1);

  vm.Vector3 axisVec = vm.Vector3.zero();

  /// Translation step in world units; zero moves freely.
  double translateSnap = 0;

  /// Rotation step in radians; zero turns freely.
  double rotateSnap = 0;

  /// Scale step; zero scales freely.
  double scaleSnap = 0;

  /// Suppresses snapping for the current drag, for a hold-to-override key.
  bool snapSuppressed = false;

  /// The drag so far, on the grid when [translateSnap] is set.
  vm.Vector3 get translation => _snapVector(_translation, translateSnap);

  /// The turn so far, on the step when [rotateSnap] is set.
  double get angle => _snapValue(_angle, rotateSnap);

  /// The scale so far, on the step when [scaleSnap] is set.
  ///
  /// Snapped toward the step but never to zero: a node scaled to nothing is
  /// invisible and hard to recover, so the smallest it lands on is one step.
  vm.Vector3 get scale {
    if (_step(scaleSnap) <= 0) return _scale;
    final snapped = _snapVector(_scale, scaleSnap);
    final step = scaleSnap;
    return vm.Vector3(
      snapped.x.abs() < step ? step : snapped.x,
      snapped.y.abs() < step ? step : snapped.y,
      snapped.z.abs() < step ? step : snapped.z,
    );
  }

  /// Sets the accumulated drag directly. For tests, which have no viewport to
  /// drag in.
  @visibleForTesting
  void debugSetAccumulated({
    vm.Vector3? translation,
    double? angle,
    vm.Vector3? scale,
  }) {
    if (translation != null) _translation = translation.clone();
    if (angle != null) _angle = angle;
    if (scale != null) _scale = scale.clone();
  }

  /// Adds to the accumulated translation, as a sequence of drags would.
  @visibleForTesting
  void debugAddTranslation(vm.Vector3 delta) => _translation += delta;

  double _step(double snap) => snapSuppressed || snap <= 0 ? 0 : snap;

  double _snapValue(double value, double snap) {
    final step = _step(snap);
    return step <= 0 ? value : (value / step).roundToDouble() * step;
  }

  vm.Vector3 _snapVector(vm.Vector3 value, double snap) {
    final step = _step(snap);
    if (step <= 0) return value;
    return vm.Vector3(
      (value.x / step).roundToDouble() * step,
      (value.y / step).roundToDouble() * step,
      (value.z / step).roundToDouble() * step,
    );
  }

  Offset _origin = Offset.zero;
  Offset _tip = Offset.zero;
  Offset _lastPos = Offset.zero;
  Offset _grabPos = Offset.zero;
  double _lastAngle = 0;
  double _scaleStartDist = 1;

  static const double _hitRadius = 12.0;

  /// Tries to grab a handle at [pos]. Returns true and starts a drag when one
  /// is hit. Call on pointer-down.
  bool grab(
    Offset pos,
    vm.Vector3 origin,
    List<vm.Vector3> axes,
    Camera camera,
    Size size,
  ) {
    final originScreen = projectToScreen(origin, camera, size);
    if (originScreen == null) return false;
    final scaleLen = _gizmoScale(origin, camera, size) * _armGlobalUnits;

    int? hit;
    if (mode == GizmoMode.rotate) {
      double best = _hitRadius;
      for (var axis = 0; axis < 3; axis++) {
        final pts = [
          for (final p in _ringPoints(origin, axis, scaleLen, axes))
            projectToScreen(p, camera, size),
        ].whereType<Offset>().toList();
        for (var i = 0; i + 1 < pts.length; i++) {
          final d = _distToSegment(pos, pts[i], pts[i + 1]);
          if (d < best) {
            best = d;
            hit = axis;
          }
        }
      }
    } else {
      // translate / scale: axis segments, plus the uniform center for scale.
      if (mode == GizmoMode.scale &&
          (pos - originScreen).distance < _hitRadius) {
        hit = axisUniform;
      } else {
        double best = _hitRadius;
        for (var axis = 0; axis < 3; axis++) {
          final tip = projectToScreen(
            origin + axes[axis] * scaleLen,
            camera,
            size,
          );
          if (tip == null) continue;
          final d = _distToSegment(pos, originScreen, tip);
          if (d < best) {
            best = d;
            hit = axis;
          }
        }
      }
    }
    if (hit == null) return false;

    activeAxis = hit;
    _translation = vm.Vector3.zero();
    _angle = 0;
    _scale = vm.Vector3(1, 1, 1);
    axisVec = hit == axisUniform ? vm.Vector3.zero() : axes[hit].clone();
    _origin = originScreen;
    _lastPos = pos;
    _grabPos = pos;
    _lastAngle = atan2(pos.dy - originScreen.dy, pos.dx - originScreen.dx);
    _scaleStartDist = max(1.0, (pos - originScreen).distance);
    if (hit != axisUniform) {
      _tip =
          projectToScreen(origin + axisVec * scaleLen, camera, size) ??
          originScreen;
    }
    return true;
  }

  /// Updates the accumulated drag for [pos]. Call on pointer-move.
  void update(Offset pos, vm.Vector3 origin, Camera camera, Size size) {
    final axis = activeAxis;
    if (axis == null) return;
    switch (mode) {
      case GizmoMode.translate:
        _updateTranslate(pos, origin, camera, size);
      case GizmoMode.rotate:
        _updateRotate(pos, origin, camera);
      case GizmoMode.scale:
        _updateScale(pos, axis);
    }
    _lastPos = pos;
  }

  void _updateTranslate(
    Offset pos,
    vm.Vector3 origin,
    Camera camera,
    Size size,
  ) {
    final axisSc = _tip - _origin;
    final len2 = axisSc.dx * axisSc.dx + axisSc.dy * axisSc.dy;
    if (len2 < 1e-6) return;
    final drag = pos - _lastPos;
    final dot = (drag.dx * axisSc.dx + drag.dy * axisSc.dy) / sqrt(len2);
    final globalLen = _armGlobalUnits * _gizmoScale(origin, camera, size);
    final pixelToGlobal = sqrt(len2) > 1e-3 ? globalLen / sqrt(len2) : 0.0;
    _translation += axisVec * (dot * pixelToGlobal);
  }

  void _updateRotate(Offset pos, vm.Vector3 origin, Camera camera) {
    final a = atan2(pos.dy - _origin.dy, pos.dx - _origin.dx);
    var delta = a - _lastAngle;
    if (delta > pi) delta -= 2 * pi;
    if (delta < -pi) delta += 2 * pi;
    _lastAngle = a;
    // Screen y is down, so a clockwise screen drag is negative math angle;
    // flip by whether the axis points toward or away from the camera so the
    // rotation tracks the pointer.
    final viewDir = (origin - camera.position)..normalize();
    final facing = axisVec.dot(viewDir) >= 0 ? 1.0 : -1.0;
    _angle += -delta * facing;
  }

  void _updateScale(Offset pos, int axis) {
    if (axis == axisUniform) {
      final factor = max(0.01, (pos - _origin).distance / _scaleStartDist);
      _scale = vm.Vector3(factor, factor, factor);
      return;
    }
    // Factor is the ratio of the pointer's projection on the screen axis now
    // vs. at grab time (both measured from the origin).
    final axisSc = _tip - _origin;
    final len2 = axisSc.dx * axisSc.dx + axisSc.dy * axisSc.dy;
    if (len2 < 1e-6) return;
    double proj(Offset p) =>
        ((p - _origin).dx * axisSc.dx + (p - _origin).dy * axisSc.dy) / len2;
    final start = proj(_grabPos);
    if (start.abs() < 1e-3) return;
    final mult = vm.Vector3(1, 1, 1);
    mult[axis] = max(0.01, proj(pos) / start);
    _scale = mult;
  }

  void end() {
    activeAxis = null;
    _translation = vm.Vector3.zero();
    _angle = 0;
    _scale = vm.Vector3(1, 1, 1);
  }
}
