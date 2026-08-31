import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_pose.dart';

/// Pushes an [RtsCameraController] along when the pointer rests near the edge
/// of the view, the way a strategy game scrolls the map.
///
/// [margin] is the band in logical pixels that counts as "at the edge". The
/// push ramps from nothing at the inner boundary to full [speed] at the very
/// edge, so a pointer resting just inside the band drifts rather than lurches.
/// {@category Scene graph}
class EdgeScroll {
  /// Creates an edge-scroll setting.
  const EdgeScroll({this.margin = 24.0, this.speed = 1.0});

  /// The band at each edge, in logical pixels, that triggers scrolling.
  final double margin;

  /// The scroll rate at the very edge, as a multiple of the controller's
  /// [RtsCameraController.keyboardPanSpeed].
  final double speed;
}

/// A strategy-game camera: it looks down at a point on the ground, pans
/// across the map, rotates around that point, and zooms, with optional
/// orthographic projection.
///
/// This one controller covers the whole family of overhead views, because
/// they differ only in which parts are locked:
///
///  * **RTS / city builder.** The default. Drag or edge-scroll to pan,
///    right-drag to rotate and tilt, wheel to zoom.
///  * **Isometric.** [RtsCameraController.isometric] fixes the pitch at the
///    true isometric angle, turns on the orthographic lens, and starts at a
///    45-degree yaw. Lock rotation by leaving [rotateSpeed] at zero.
///  * **Top-down.** [RtsCameraController.topDown] looks straight down. A
///    look-at camera cannot do this (there is no up vector perpendicular to a
///    straight-down view), so the basis comes from the camera's own yaw
///    instead and a vertical view is just another angle.
///
/// The camera is defined by a [focus] point on the ground, a [yaw] around it,
/// a [pitch] down toward it, and how far back it sits. In perspective mode
/// zooming changes [distance]; in [orthographic] mode distance is fixed and
/// zooming changes [viewHeight], because moving a parallel camera closer does
/// not make anything bigger.
///
/// ```dart
/// final camera = RtsCameraController.isometric(focus: Vector3.zero())
///   ..bounds = Aabb3.minMax(Vector3(-100, 0, -100), Vector3(100, 0, 100))
///   ..edgeScroll = const EdgeScroll();
/// cameraNode.addComponent(camera);
/// ```
/// {@category Scene graph}
class RtsCameraController extends CameraController {
  /// Creates a strategy camera focused on [focus].
  RtsCameraController({
    Vector3? focus,
    double yaw = 0.0,
    double pitch = 0.9,
    double distance = 40.0,
    double viewHeight = 30.0,
    this.orthographic = false,
    this.orthographicDepth = 1000.0,
    this.minDistance = 5.0,
    this.maxDistance = 400.0,
    this.minViewHeight = 4.0,
    this.maxViewHeight = 400.0,
    this.minPitch = 0.2,
    this.maxPitch = _verticalPitch,
    this.rotateSpeed = math.pi,
    this.pitchSpeed = math.pi * 0.5,
    this.zoomSpeed = 0.2,
    this.dragPanSpeed = 1.0,
    this.keyboardPanSpeed = 1.0,
    this.scrollSensitivity = 1 / 120,
    this.bounds,
    this.groundHeightAt,
    this.edgeScroll,
    super.smoothing = 0.14,
  }) : _focus = (focus ?? Vector3.zero()).clone(),
       _focusGoal = (focus ?? Vector3.zero()).clone(),
       _yaw = yaw,
       _yawGoal = yaw,
       _pitch = pitch.clamp(minPitch, maxPitch),
       _pitchGoal = pitch.clamp(minPitch, maxPitch),
       _distance = distance,
       _distanceGoal = distance,
       _viewHeight = viewHeight,
       _viewHeightGoal = viewHeight;

  /// A true isometric camera: the lens is orthographic and the pitch is
  /// `atan(1 / sqrt(2))`, the angle at which the three axes of a cube project
  /// to equal lengths and 120 degrees apart.
  ///
  /// Leave [rotateSpeed] at its default of zero for the fixed viewpoint most
  /// isometric art is drawn for; raise it to allow the classic four-way
  /// rotation.
  factory RtsCameraController.isometric({
    Vector3? focus,
    double yaw = math.pi / 4,
    double viewHeight = 30.0,
    double distance = 200.0,
    double rotateSpeed = 0.0,
    double zoomSpeed = 0.2,
    double? minViewHeight,
    double? maxViewHeight,
    Aabb3? bounds,
    double smoothing = 0.14,
  }) => RtsCameraController(
    focus: focus,
    yaw: yaw,
    pitch: _isometricPitch,
    minPitch: _isometricPitch,
    maxPitch: _isometricPitch,
    distance: distance,
    viewHeight: viewHeight,
    orthographic: true,
    rotateSpeed: rotateSpeed,
    pitchSpeed: 0.0,
    zoomSpeed: zoomSpeed,
    minViewHeight: minViewHeight ?? 4.0,
    maxViewHeight: maxViewHeight ?? 400.0,
    bounds: bounds,
    smoothing: smoothing,
  );

  /// A camera looking straight down at the ground, for a map view, a tactics
  /// grid, or a top-down shooter.
  factory RtsCameraController.topDown({
    Vector3? focus,
    double yaw = 0.0,
    double height = 40.0,
    double viewHeight = 30.0,
    bool orthographic = true,
    double rotateSpeed = 0.0,
    Aabb3? bounds,
    double smoothing = 0.14,
  }) => RtsCameraController(
    focus: focus,
    yaw: yaw,
    pitch: _verticalPitch,
    minPitch: _verticalPitch,
    maxPitch: _verticalPitch,
    distance: height,
    viewHeight: viewHeight,
    orthographic: orthographic,
    rotateSpeed: rotateSpeed,
    pitchSpeed: 0.0,
    bounds: bounds,
    smoothing: smoothing,
  );

  // Straight down. Safe here (unlike a look-at camera) because the basis is
  // built from yaw rather than crossed against a world up.
  static const double _verticalPitch = math.pi / 2;
  static const double _isometricPitch = 0.6154797086703873; // atan(1/sqrt(2))

  /// Whether the camera uses an [OrthographicProjection]. When true, zooming
  /// changes [viewHeight] and [distance] is held fixed.
  bool orthographic;

  /// The depth range the orthographic lens spans, centered on [focus]. Wide
  /// enough by default to contain a large map on any tilt.
  double orthographicDepth;

  /// Zoom clamps for perspective mode.
  double minDistance;
  double maxDistance;

  /// Zoom clamps for orthographic mode.
  double minViewHeight;
  double maxViewHeight;

  /// Tilt clamps, in radians measured down from the horizon. Setting both to
  /// the same value locks the tilt.
  double minPitch;
  double maxPitch;

  /// Radians of rotation per view-width of drag. Zero locks the yaw.
  double rotateSpeed;

  /// Radians of tilt per view-height of drag. Zero locks the pitch.
  double pitchSpeed;

  /// Proportional zoom rate; a step changes the zoom by
  /// `exp(-amount * zoomSpeed)` so it feels the same close in or far out.
  double zoomSpeed;

  /// Pan distance as a multiple of the drag fraction times the visible ground
  /// extent, so dragging keeps the ground under the cursor at any zoom.
  double dragPanSpeed;

  /// Pan rate for [setPanInput] and [edgeScroll], as a multiple of the
  /// visible ground extent per second.
  double keyboardPanSpeed;

  /// Zoom steps per unit of scroll delta.
  double scrollSensitivity;

  /// Optional clamp on where [focus] may go. Only the X and Z extents are
  /// used; the height comes from [groundHeightAt] or stays put.
  Aabb3? bounds;

  /// Optional terrain sampler. When set, [focus] rides the ground height at
  /// its own X/Z rather than staying on a flat plane, so the camera keeps a
  /// constant height over hilly terrain.
  double Function(double x, double z)? groundHeightAt;

  /// Optional edge scrolling. Feed pointer positions to [pointerMoved].
  EdgeScroll? edgeScroll;

  Vector3 _focus;
  Vector3 _focusGoal;
  double _yaw;
  double _yawGoal;
  double _pitch;
  double _pitchGoal;
  double _distance;
  double _distanceGoal;
  double _viewHeight;
  double _viewHeightGoal;
  final Vector2 _panInput = Vector2.zero();
  final Vector2 _edgeInput = Vector2.zero();

  /// The point on the ground the camera looks at (its eased, current value).
  Vector3 get focus => _focus.clone();
  set focus(Vector3 value) {
    _focus = value.clone();
    _focusGoal = value.clone();
  }

  /// The heading, in radians.
  double get yaw => _yaw;

  /// The tilt down from the horizon, in radians.
  double get pitch => _pitch;

  /// The camera's standoff from [focus]. Zooming changes this in perspective
  /// mode; in orthographic mode it is fixed and only positions the eye.
  double get distance => _distance;

  /// The vertical extent of the orthographic view, in world units. Zooming
  /// changes this in orthographic mode.
  double get viewHeight => _viewHeight;

  /// How much ground the view spans vertically right now: the orthographic
  /// height, or a stand-in proportional to distance in perspective mode.
  /// Pan and edge-scroll rates scale with it, so they feel the same at any
  /// zoom.
  double get _groundExtent => orthographic ? _viewHeight : _distance;

  /// The unit horizontal direction the camera faces, for orienting things to
  /// the view (a selection box, a placement ghost).
  Vector3 get planarForward => Vector3(math.sin(_yaw), 0.0, math.cos(_yaw));

  /// The unit horizontal direction to the camera's right.
  Vector3 get planarRight => Vector3(math.cos(_yaw), 0.0, -math.sin(_yaw));

  /// Moves the focus by [delta] in world units on the ground plane.
  void panWorld(Vector2 delta) {
    _focusGoal.x += delta.x;
    _focusGoal.z += delta.y;
    _clampFocus();
  }

  /// Pans by a fraction of the view (components in `[-1, 1]`), scaled so the
  /// ground tracks the drag. Positive [fraction] moves the *view* right and
  /// down, which moves the ground the other way.
  void panByFraction(Offset fraction) {
    final scale = _groundExtent * dragPanSpeed;
    final right = planarRight * (-fraction.dx * scale);
    final forward = planarForward * (fraction.dy * scale);
    panWorld(Vector2(right.x + forward.x, right.z + forward.z));
  }

  /// Sets a held pan direction, applied every frame until changed. `+Y` is
  /// forward (away from the camera), matching the engine's `move` action.
  void setPanInput(Vector2 input) => _panInput.setFrom(input);

  /// Feeds the pointer's position inside the view so [edgeScroll] can push
  /// the camera. Pass null when the pointer leaves the view, or edge
  /// scrolling sticks on.
  void pointerMoved(Offset? position) {
    final config = edgeScroll;
    if (config == null || position == null) {
      _edgeInput.setZero();
      return;
    }
    final size = viewportSize;
    if (size.width <= 0 || size.height <= 0) {
      _edgeInput.setZero();
      return;
    }
    // Ramp from nothing at the inner boundary to full speed at the edge, so
    // resting the pointer inside the band drifts rather than lurches.
    double push(double fromStart, double fromEnd) {
      if (fromStart < config.margin) {
        return -(1.0 - (fromStart / config.margin)).clamp(0.0, 1.0);
      }
      if (fromEnd < config.margin) {
        return (1.0 - (fromEnd / config.margin)).clamp(0.0, 1.0);
      }
      return 0.0;
    }

    _edgeInput.setValues(
      push(position.dx, size.width - position.dx) * config.speed,
      // Screen Y grows downward; moving the pointer to the top of the view
      // should push the camera forward.
      -push(position.dy, size.height - position.dy) * config.speed,
    );
  }

  /// Rotates the camera around [focus] by [radians].
  void rotateBy(double radians) => _yawGoal += radians;

  /// Tilts the camera by [radians] (positive looks further down), clamped to
  /// [minPitch]..[maxPitch].
  void pitchBy(double radians) =>
      _pitchGoal = (_pitchGoal + radians).clamp(minPitch, maxPitch);

  /// Zooms in ([amount] > 0) or out, proportionally. Acts on [viewHeight] in
  /// orthographic mode and on [distance] otherwise.
  void zoomBy(double amount) {
    final factor = math.exp(-amount * zoomSpeed);
    if (orthographic) {
      _viewHeightGoal = (_viewHeightGoal * factor).clamp(
        minViewHeight,
        maxViewHeight,
      );
    } else {
      _distanceGoal = (_distanceGoal * factor).clamp(minDistance, maxDistance);
    }
  }

  /// Moves the focus to [worldPoint] (its ground height is resolved by
  /// [groundHeightAt] when set).
  void focusOn(Vector3 worldPoint) {
    _focusGoal.setFrom(worldPoint);
    _clampFocus();
  }

  /// Centers on [target] and zooms out far enough to contain it.
  void frame(Aabb3 target, {double margin = 1.2}) {
    focusOn(target.center);
    final radius = math.max((target.max - target.min).length * 0.5, 1e-4);
    if (orthographic) {
      _viewHeightGoal = (radius * 2 * margin).clamp(
        minViewHeight,
        maxViewHeight,
      );
    } else {
      _distanceGoal = (radius * 2 * margin).clamp(minDistance, maxDistance);
    }
  }

  /// Drops all easing so the camera is exactly where it has been asked to be.
  void snap() {
    _focus.setFrom(_focusGoal);
    _yaw = _yawGoal;
    _pitch = _pitchGoal;
    _distance = _distanceGoal;
    _viewHeight = _viewHeightGoal;
  }

  @override
  void handleDragUpdate(Offset delta) => panByFraction(
    Offset(delta.dx / viewportSize.height, delta.dy / viewportSize.height),
  );

  @override
  void handleSecondaryDragUpdate(Offset delta) {
    if (rotateSpeed != 0.0) {
      rotateBy(-delta.dx * rotateSpeed / viewportSize.width);
    }
    if (pitchSpeed != 0.0) {
      pitchBy(delta.dy * pitchSpeed / viewportSize.height);
    }
  }

  @override
  void handleScaleUpdate(double scaleFactor, Offset focalDelta) {
    if (scaleFactor != 1.0) zoomBy((scaleFactor - 1.0) / zoomSpeed);
    if (focalDelta != Offset.zero) {
      panByFraction(
        Offset(
          focalDelta.dx / viewportSize.height,
          focalDelta.dy / viewportSize.height,
        ),
      );
    }
  }

  @override
  void handleScroll(double scrollDelta) =>
      zoomBy(-scrollDelta * scrollSensitivity);

  @override
  void releaseInput() {
    _panInput.setZero();
    _edgeInput.setZero();
  }

  void _clampFocus() {
    final limit = bounds;
    if (limit != null) {
      _focusGoal.x = _focusGoal.x.clamp(limit.min.x, limit.max.x);
      _focusGoal.z = _focusGoal.z.clamp(limit.min.z, limit.max.z);
    }
    final ground = groundHeightAt;
    if (ground != null) {
      _focusGoal.y = ground(_focusGoal.x, _focusGoal.z);
    } else if (limit != null) {
      _focusGoal.y = _focusGoal.y.clamp(limit.min.y, limit.max.y);
    }
  }

  @override
  void advance(double deltaSeconds) {
    final held = _panInput + _edgeInput;
    if (held.x != 0.0 || held.y != 0.0) {
      final scale = _groundExtent * keyboardPanSpeed * deltaSeconds;
      final right = planarRight * (held.x * scale);
      final forward = planarForward * (held.y * scale);
      panWorld(Vector2(right.x + forward.x, right.z + forward.z));
    } else if (groundHeightAt != null) {
      // Terrain height still needs resolving on a frame with no pan, in case
      // the sampler itself changed (deforming terrain, a streamed chunk).
      _clampFocus();
    }

    final response = smoothingResponse(deltaSeconds);
    _focus += (_focusGoal - _focus) * response;
    _yaw += (_yawGoal - _yaw) * response;
    _pitch += (_pitchGoal - _pitch) * response;
    _distance += (_distanceGoal - _distance) * response;
    _viewHeight += (_viewHeightGoal - _viewHeight) * response;

    final cosPitch = math.cos(_pitch);
    final forward = Vector3(
      math.sin(_yaw) * cosPitch,
      -math.sin(_pitch),
      math.cos(_yaw) * cosPitch,
    );
    final right = planarRight;
    final up = forward.cross(right);
    final eye = _focus - forward * _distance;

    setPose(
      CameraPose.fromBasis(
        eye,
        right: right,
        up: up,
        forward: forward,
        projection: orthographic
            ? OrthographicProjection(
                height: _viewHeight,
                near: _distance - orthographicDepth * 0.5,
                far: _distance + orthographicDepth * 0.5,
              )
            : null,
      ),
    );
  }
}
