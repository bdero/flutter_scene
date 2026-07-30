import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A parallel projection, sized by the world-space [height] visible in the
/// view. The engine ships only [PerspectiveProjection]; this implements the
/// same clip conventions (depth 0..1, +Z into the screen).
class OrthographicProjection extends CameraProjection {
  OrthographicProjection({
    required this.height,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// World-space height of the view volume.
  final double height;

  final double near;
  final double far;

  @override
  vm.Matrix4 getProjectionMatrix(double aspectRatio) {
    final halfHeight = height / 2;
    final halfWidth = halfHeight * aspectRatio;
    return vm.Matrix4(
      1 / halfWidth,
      0,
      0,
      0, //
      0,
      1 / halfHeight,
      0,
      0, //
      0,
      0,
      1 / (far - near),
      0, //
      0,
      0,
      -near / (far - near),
      1,
    );
  }
}

/// A [PerspectiveCamera] whose lens can be swapped for a custom projection
/// (the orbit camera's orthographic mode) while keeping the eye/target view.
class _ProjectionCamera extends PerspectiveCamera {
  _ProjectionCamera({
    super.position,
    super.target,
    super.up,
    this.customProjection,
  });

  final CameraProjection? customProjection;

  @override
  CameraProjection get projection => customProjection ?? super.projection;
}

/// Spherical-coordinates orbit camera state with pan and zoom.
///
/// Driven by pointer/scroll events from the viewport. Mutable in place;
/// call [camera] to get the current [PerspectiveCamera].
class OrbitCamera {
  OrbitCamera({
    this.azimuth = 0.4,
    this.elevation = 0.4,
    this.radius = 8.0,
    this.orthographic = false,
    vm.Vector3? target,
  }) : target = target ?? vm.Vector3.zero();

  double azimuth; // horizontal angle, radians
  double elevation; // vertical angle, radians (clamped away from poles)
  double radius; // distance from target
  vm.Vector3 target; // world-space look-at point

  /// Renders with a parallel projection. Zoom still adjusts [radius], which
  /// scales the orthographic view height so it matches the perspective
  /// framing at the same distance.
  bool orthographic;

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
  /// moves the scene right (grab-the-world feel), so the target moves the
  /// opposite way along the screen axes.
  void pan(double deltaX, double deltaY) {
    final scale = radius * 0.001;
    target -= rightVector * (deltaX * scale);
    target += upVector * (deltaY * scale);
  }

  /// Zooms by a scroll delta (positive = zoom in).
  void zoom(double delta) {
    radius = (radius * pow(0.99, delta)).clamp(_minRadius, double.infinity);
  }

  /// Zooms by a pinch scale factor (>1 zooms in).
  void zoomScale(double factor) {
    if (factor <= 0) return;
    radius = (radius / factor).clamp(_minRadius, double.infinity);
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

  /// Snaps to a straight-on view down [axis] (0 = X, 1 = Y, 2 = Z), from the
  /// positive side unless [negative]. Switches to [orthographic], the reason
  /// these views exist.
  void snapAxisView(int axis, {bool negative = false}) {
    switch (axis) {
      case 0:
        azimuth = negative ? -pi / 2 : pi / 2;
        elevation = 0;
      case 1:
        elevation = negative ? -pi / 2 : pi / 2;
      case 2:
        azimuth = negative ? pi : 0;
        elevation = 0;
    }
    orthographic = true;
  }

  /// The camera's screen-right direction (always horizontal). Matches the
  /// renderer's view basis (`up cross forward`), so projecting a world
  /// direction onto this maps to on-screen horizontal movement.
  vm.Vector3 get rightVector =>
      vm.Vector3(-cos(azimuth), 0, sin(azimuth))..normalize();

  /// The camera's screen-up direction, the elevation tangent of the orbit
  /// sphere. Matches a constant world-up for ordinary elevations and stays
  /// well-defined at the poles (top/bottom axis views), where a constant up
  /// would be parallel to the view direction.
  vm.Vector3 get upVector => vm.Vector3(
    -sin(elevation) * sin(azimuth),
    cos(elevation),
    -sin(elevation) * cos(azimuth),
  )..normalize();

  /// The view direction, from the eye toward [target].
  vm.Vector3 get forwardVector => (target - position).normalized();

  PerspectiveCamera get camera => _ProjectionCamera(
    position: position,
    target: target,
    up: upVector,
    customProjection: orthographic
        // Height that matches the perspective framing (45 degree vertical
        // fov) of the plane through the target, so toggling projections
        // keeps the subject the same apparent size.
        ? OrthographicProjection(height: 2 * radius * tan(pi / 8))
        : null,
  );
}

/// Wraps a child widget and routes pointer events to an [OrbitCamera].
///
/// Left-drag = orbit. Middle-drag or Shift+left-drag = pan.
/// Two-finger scroll = orbit; with Ctrl/Cmd = zoom; with Shift = pan.
/// Pinch = zoom.
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
  double _lastPinchScale = 1.0;

  /// Routes a two-finger scroll [delta] (in [PointerScrollEvent] sign
  /// convention, content moving down is positive dy) by the held modifiers:
  /// plain scroll orbits, Ctrl/Cmd zooms, Shift pans. The negations give
  /// scrolling the same feel as the equivalent drag.
  void _handleScroll(Offset delta) {
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      widget.camera.zoom(delta.dy);
    } else if (keys.isShiftPressed) {
      widget.camera.pan(-delta.dx, -delta.dy);
    } else {
      widget.camera.orbit(-delta.dx, -delta.dy);
    }
    widget.onChanged();
  }

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
        // Mouse wheels (and trackpads on platforms without gesture events)
        // arrive here as discrete scrolls.
        if (e is PointerScrollEvent) _handleScroll(e.scrollDelta);
      },
      onPointerPanZoomStart: (e) => _lastPinchScale = 1.0,
      onPointerPanZoomUpdate: (e) {
        // Trackpad gestures: the pinch scale drives zoom; two-finger pans
        // route through the modifier-aware scroll handler. The pan delta's
        // sign convention is opposite the scroll one.
        if ((e.scale - _lastPinchScale).abs() > 1e-4) {
          widget.camera.zoomScale(e.scale / _lastPinchScale);
          _lastPinchScale = e.scale;
          widget.onChanged();
        }
        if (e.panDelta != Offset.zero) _handleScroll(-e.panDelta);
      },
      child: widget.child,
    );
  }
}
