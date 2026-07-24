import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Axis index constants. [axisUniform] is the scale gizmo's center handle.
const int axisX = 0;
const int axisY = 1;
const int axisZ = 2;
const int axisUniform = 3;

/// The transform the gizmo edits.
enum GizmoMode { translate, rotate, scale }

/// Projects a world-space point to screen pixels. Returns null when behind the
/// camera.
Offset? projectToScreen(vm.Vector3 worldPoint, Camera camera, Size viewSize) {
  final vp = camera.getViewTransform(viewSize);
  final clip = vp.transform(
    vm.Vector4(worldPoint.x, worldPoint.y, worldPoint.z, 1),
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

vm.Vector3 _axisDir(int axis) => switch (axis) {
  axisX => vm.Vector3(1, 0, 0),
  axisY => vm.Vector3(0, 1, 0),
  _ => vm.Vector3(0, 0, 1),
};

const _axisColors = [
  Color(0xFFE84040), // X red
  Color(0xFF40C840), // Y green
  Color(0xFF4080E8), // Z blue
];
const _activeColor = Color(0xFFFFDD44);
const _uniformColor = Color(0xFFCCCCCC);
const double _armWorldUnits = 1.2;

double _gizmoScale(vm.Vector3 origin, Camera camera, Size size) {
  final dist = (camera.position - origin).length;
  return dist * 40 / (size.height * 0.7);
}

/// Points around the ring of [axis] (a circle of [radius] in the plane
/// perpendicular to the axis), in world space.
List<vm.Vector3> _ringPoints(vm.Vector3 origin, int axis, double radius) {
  final u = _axisDir((axis + 1) % 3) * radius;
  final v = _axisDir((axis + 2) % 3) * radius;
  return [
    for (var i = 0; i <= 48; i++)
      origin + u * cos(i / 48 * 2 * pi) + v * sin(i / 48 * 2 * pi),
  ];
}

/// Draws the transform gizmo for the active [mode] at world [origin].
class TransformGizmoPainter extends CustomPainter {
  TransformGizmoPainter({
    required this.origin,
    required this.mode,
    required this.camera,
    required this.activeAxis,
  });

  final vm.Vector3 origin;
  final GizmoMode mode;
  final Camera camera;
  final int? activeAxis;

  @override
  void paint(Canvas canvas, Size size) {
    final originScreen = projectToScreen(origin, camera, size);
    if (originScreen == null) return;
    final scale = _gizmoScale(origin, camera, size) * _armWorldUnits;

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
      final tip = projectToScreen(
        origin + _axisDir(axis) * scale,
        camera,
        size,
      );
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
      for (final p in _ringPoints(origin, axis, radius)) {
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
      final tip = projectToScreen(
        origin + _axisDir(axis) * scale,
        camera,
        size,
      );
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

const _volumeColor = Color(0xFF34D6C8);
const _volumeBlendColor = Color(0x5534D6C8);

/// Draws wireframe regions for the scene's environment-volume components: the
/// node-local box edges or sphere great circles transformed by the owning
/// node, plus a fainter shell at the blend distance where each volume starts
/// fading in. Painted from the live components so a region follows an inspector
/// edit or a transform-gizmo drag immediately.
class EnvironmentVolumeComponentPainter extends CustomPainter {
  EnvironmentVolumeComponentPainter({
    required this.volumes,
    required this.camera,
  });

  final List<EnvironmentVolumeComponent> volumes;
  final Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    for (final v in volumes) {
      if (!v.isAttached) continue;
      final transform = v.node.globalTransform;
      _paintRegion(canvas, size, v, transform, 0, _volumeColor, 1.5);
      if (v.blendDistance > 0) {
        _paintRegion(
          canvas,
          size,
          v,
          transform,
          v.blendDistance,
          _volumeBlendColor,
          1.0,
        );
      }
    }
  }

  // Draws a volume's region (in the node's local space, mapped to world by
  // [transform]) expanded outward by [pad] (the blend shell when non-zero).
  void _paintRegion(
    Canvas canvas,
    Size size,
    EnvironmentVolumeComponent v,
    vm.Matrix4 transform,
    double pad,
    Color color,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    switch (v.shape) {
      case EnvironmentVolumeShape.box:
        _paintBox(
          canvas,
          size,
          transform,
          v.extents + vm.Vector3.all(pad),
          paint,
        );
      case EnvironmentVolumeShape.sphere:
        for (var axis = 0; axis < 3; axis++) {
          _paintPolyline(canvas, size, [
            for (final p in _ringPoints(
              vm.Vector3.zero(),
              axis,
              v.radius + pad,
            ))
              transform.transformed3(p),
          ], paint);
        }
    }
  }

  void _paintBox(
    Canvas canvas,
    Size size,
    vm.Matrix4 transform,
    vm.Vector3 halfExtents,
    Paint paint,
  ) {
    final corners = <Offset?>[
      for (var c = 0; c < 8; c++)
        projectToScreen(
          transform.transformed3(
            vm.Vector3(
              (c & 1) == 0 ? -halfExtents.x : halfExtents.x,
              (c & 2) == 0 ? -halfExtents.y : halfExtents.y,
              (c & 4) == 0 ? -halfExtents.z : halfExtents.z,
            ),
          ),
          camera,
          size,
        ),
    ];
    // Edges connect corners differing in exactly one axis bit.
    for (var a = 0; a < 8; a++) {
      for (final bit in const [1, 2, 4]) {
        final b = a | bit;
        if (b == a) continue;
        final p = corners[a];
        final q = corners[b];
        if (p != null && q != null) canvas.drawLine(p, q, paint);
      }
    }
  }

  void _paintPolyline(
    Canvas canvas,
    Size size,
    List<vm.Vector3> points,
    Paint paint,
  ) {
    Offset? previous;
    for (final point in points) {
      final screen = projectToScreen(point, camera, size);
      if (previous != null && screen != null) {
        canvas.drawLine(previous, screen, paint);
      }
      previous = screen;
    }
  }

  @override
  bool shouldRepaint(EnvironmentVolumeComponentPainter old) => true;
}

/// Hit-tests the gizmo and accumulates a drag as a translation, a rotation
/// (angle about [axisVec]), or a per-axis scale, depending on [mode].
class GizmoController {
  GizmoMode mode = GizmoMode.translate;
  int? activeAxis;

  // Accumulated drag result since [grab], consumed by the viewport.
  vm.Vector3 translation = vm.Vector3.zero();
  double angle = 0;
  vm.Vector3 axisVec = vm.Vector3.zero();
  vm.Vector3 scale = vm.Vector3(1, 1, 1);

  Offset _origin = Offset.zero;
  Offset _tip = Offset.zero;
  Offset _lastPos = Offset.zero;
  Offset _grabPos = Offset.zero;
  double _lastAngle = 0;
  double _scaleStartDist = 1;

  static const double _hitRadius = 12.0;

  /// Tries to grab a handle at [pos]. Returns true and starts a drag when one
  /// is hit. Call on pointer-down.
  bool grab(Offset pos, vm.Vector3 origin, Camera camera, Size size) {
    final originScreen = projectToScreen(origin, camera, size);
    if (originScreen == null) return false;
    final scaleLen = _gizmoScale(origin, camera, size) * _armWorldUnits;

    int? hit;
    if (mode == GizmoMode.rotate) {
      double best = _hitRadius;
      for (var axis = 0; axis < 3; axis++) {
        final pts = [
          for (final p in _ringPoints(origin, axis, scaleLen))
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
            origin + _axisDir(axis) * scaleLen,
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
    translation = vm.Vector3.zero();
    angle = 0;
    scale = vm.Vector3(1, 1, 1);
    axisVec = hit == axisUniform ? vm.Vector3.zero() : _axisDir(hit);
    _origin = originScreen;
    _lastPos = pos;
    _grabPos = pos;
    _lastAngle = atan2(pos.dy - originScreen.dy, pos.dx - originScreen.dx);
    _scaleStartDist = max(1.0, (pos - originScreen).distance);
    if (hit != axisUniform) {
      _tip =
          projectToScreen(origin + _axisDir(hit) * scaleLen, camera, size) ??
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
        _updateTranslate(pos, axis, origin, camera, size);
      case GizmoMode.rotate:
        _updateRotate(pos, axis, origin, camera);
      case GizmoMode.scale:
        _updateScale(pos, axis);
    }
    _lastPos = pos;
  }

  void _updateTranslate(
    Offset pos,
    int axis,
    vm.Vector3 origin,
    Camera camera,
    Size size,
  ) {
    final axisSc = _tip - _origin;
    final len2 = axisSc.dx * axisSc.dx + axisSc.dy * axisSc.dy;
    if (len2 < 1e-6) return;
    final drag = pos - _lastPos;
    final dot = (drag.dx * axisSc.dx + drag.dy * axisSc.dy) / sqrt(len2);
    final worldLen = _armWorldUnits * _gizmoScale(origin, camera, size);
    final pixelToWorld = sqrt(len2) > 1e-3 ? worldLen / sqrt(len2) : 0.0;
    translation += _axisDir(axis) * (dot * pixelToWorld);
  }

  void _updateRotate(Offset pos, int axis, vm.Vector3 origin, Camera camera) {
    final a = atan2(pos.dy - _origin.dy, pos.dx - _origin.dx);
    var delta = a - _lastAngle;
    if (delta > pi) delta -= 2 * pi;
    if (delta < -pi) delta += 2 * pi;
    _lastAngle = a;
    // Screen y is down, so a clockwise screen drag is negative math angle;
    // flip by whether the axis points toward or away from the camera so the
    // rotation tracks the pointer.
    final viewDir = (origin - camera.position)..normalize();
    final facing = _axisDir(axis).dot(viewDir) >= 0 ? 1.0 : -1.0;
    angle += -delta * facing;
  }

  void _updateScale(Offset pos, int axis) {
    if (axis == axisUniform) {
      final factor = max(0.01, (pos - _origin).distance / _scaleStartDist);
      scale = vm.Vector3(factor, factor, factor);
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
    scale = mult;
  }

  void end() {
    activeAxis = null;
    translation = vm.Vector3.zero();
    angle = 0;
    scale = vm.Vector3(1, 1, 1);
  }
}
