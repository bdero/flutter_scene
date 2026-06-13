import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Spherical-coordinates orbit camera state with pan and zoom.
///
/// Driven by pointer/scroll events from the viewport. Mutable in place;
/// call [camera] to get the current [PerspectiveCamera].
class OrbitCamera {
  OrbitCamera({
    this.azimuth = 0.4,
    this.elevation = 0.4,
    this.radius = 8.0,
    vm.Vector3? target,
  }) : target = target ?? vm.Vector3.zero();

  double azimuth; // horizontal angle, radians
  double elevation; // vertical angle, radians (clamped away from poles)
  double radius; // distance from target
  vm.Vector3 target; // world-space look-at point

  static const double _minElevation = -pi / 2 + 0.05;
  static const double _maxElevation = pi / 2 - 0.05;
  static const double _minRadius = 0.5;

  /// Orbits by [deltaX] and [deltaY] pixel deltas.
  void orbit(double deltaX, double deltaY) {
    azimuth += deltaX * 0.006;
    elevation = (elevation + deltaY * 0.006).clamp(
      _minElevation,
      _maxElevation,
    );
  }

  /// Pans the target by screen-space pixel deltas, scaled to world units by
  /// [radius] so panning feels consistent at any zoom level. Dragging right
  /// moves the scene right (grab-the-world feel).
  void pan(double deltaX, double deltaY) {
    final scale = radius * 0.001;
    final right = _rightVec();
    final up = _upVec();
    target += right * (deltaX * scale);
    target += up * (deltaY * scale);
  }

  /// Zooms by a scroll delta (positive = zoom in).
  void zoom(double delta) {
    radius = (radius * pow(0.99, delta)).clamp(_minRadius, double.infinity);
  }

  /// Returns the world-space eye position.
  vm.Vector3 get position {
    return target +
        vm.Vector3(
          cos(elevation) * sin(azimuth) * radius,
          sin(elevation) * radius,
          cos(elevation) * cos(azimuth) * radius,
        );
  }

  vm.Vector3 _rightVec() {
    return vm.Vector3(cos(azimuth), 0, -sin(azimuth))..normalize();
  }

  vm.Vector3 _upVec() {
    final fwd = (target - position).normalized();
    final right = _rightVec();
    return right.cross(fwd)..normalize();
  }

  PerspectiveCamera get camera => PerspectiveCamera(
    position: position,
    target: target,
    up: vm.Vector3(0, 1, 0),
  );
}

/// Wraps a child widget and routes pointer events to an [OrbitCamera].
///
/// Left-drag = orbit. Middle-drag or Shift+left-drag = pan.
/// Scroll = zoom.
class OrbitCameraController extends StatefulWidget {
  const OrbitCameraController({
    super.key,
    required this.camera,
    required this.onChanged,
    required this.child,
    this.isLocked,
  });

  final OrbitCamera camera;
  final VoidCallback onChanged;
  final Widget child;

  /// When this returns true (for example when a gizmo is active), the
  /// controller ignores drags so camera navigation does not fire on top of
  /// an active interaction.
  final bool Function()? isLocked;

  @override
  State<OrbitCameraController> createState() => _OrbitCameraControllerState();
}

class _OrbitCameraControllerState extends State<OrbitCameraController> {
  Offset? _lastDrag;
  bool _isPanning = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (widget.isLocked?.call() ?? false) {
          _lastDrag = null;
          _isPanning = false;
          return;
        }
        _lastDrag = e.localPosition;
        _isPanning =
            e.buttons == kMiddleMouseButton ||
            (e.buttons == kPrimaryMouseButton &&
                HardwareKeyboard.instance.isShiftPressed);
      },
      onPointerMove: (e) {
        if (widget.isLocked?.call() ?? false) return;
        final last = _lastDrag;
        if (last == null) return;
        final delta = e.localPosition - last;
        _lastDrag = e.localPosition;
        if (_isPanning) {
          widget.camera.pan(delta.dx, delta.dy);
        } else if (e.buttons & kPrimaryMouseButton != 0) {
          widget.camera.orbit(delta.dx, delta.dy);
        }
        widget.onChanged();
      },
      onPointerUp: (e) => _lastDrag = null,
      onPointerCancel: (e) => _lastDrag = null,
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          widget.camera.zoom(e.scrollDelta.dy);
          widget.onChanged();
        }
      },
      onPointerPanZoomUpdate: (e) {
        widget.camera.zoom(-e.panDelta.dy * 0.5);
        widget.camera.orbit(e.panDelta.dx * 0.5, 0);
        widget.onChanged();
      },
      child: widget.child,
    );
  }
}
