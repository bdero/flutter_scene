import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';

/// Orbits the camera around a fixed [target] point: drag rotates, scroll or
/// pinch dollies in and out, and a two-finger or secondary drag pans the
/// target across the view.
///
/// The camera rides a turntable, an [azimuth] around world up and a [polar]
/// elevation clamped just short of straight up/down, so the horizon stays
/// level and the view never flips over the poles. Distance-scaled dolly keeps
/// the zoom feeling constant whether the camera is close or far.
///
/// Attach it to a node that also carries a [CameraComponent]. Drive it with a
/// [CameraControls] widget, or call [orbitBy] / [dollyBy] / [panBy] directly.
/// {@category Scene graph}
class OrbitCameraController extends CameraController {
  /// Creates an orbit controller framing [target] from [distance] at the given
  /// [azimuth] and [polar] angles (radians).
  OrbitCameraController({
    Vector3? target,
    double distance = 6.0,
    double azimuth = 0.0,
    double polar = 0.3,
    this.minDistance = 0.1,
    this.maxDistance = double.infinity,
    this.minPolar = -_polarLimit,
    this.maxPolar = _polarLimit,
    this.rotateSpeed = math.pi,
    this.dollySpeed = 0.15,
    this.panSpeed = 1.0,
    this.scrollSensitivity = 1 / 120,
    super.smoothing,
  }) : _target = (target ?? Vector3.zero()).clone(),
       _targetGoal = (target ?? Vector3.zero()).clone(),
       _distance = distance,
       _distanceGoal = distance,
       _azimuth = azimuth,
       _azimuthGoal = azimuth,
       _polar = polar.clamp(minPolar, maxPolar),
       _polarGoal = polar.clamp(minPolar, maxPolar);

  static const double _polarLimit = math.pi / 2 - 0.02;

  /// Closest and farthest the camera may dolly. [minDistance] must be > 0.
  double minDistance;
  double maxDistance;

  /// Elevation clamp (radians), kept just inside +-pi/2 so the view never
  /// flips over the poles.
  double minPolar;
  double maxPolar;

  /// Radians of orbit per view-height of drag.
  double rotateSpeed;

  /// Proportional dolly rate; the distance changes by `exp(-amount*dollySpeed)`
  /// so a step feels the same near or far.
  double dollySpeed;

  /// Pan distance as a multiple of the drag fraction times the orbit distance.
  double panSpeed;

  /// Dolly steps per unit of scroll delta.
  double scrollSensitivity;

  Vector3 _target;
  Vector3 _targetGoal;
  double _distance;
  double _distanceGoal;
  double _azimuth;
  double _azimuthGoal;
  double _polar;
  double _polarGoal;

  /// The point the camera orbits (its eased, current value).
  Vector3 get target => _target.clone();
  set target(Vector3 value) {
    _target = value.clone();
    _targetGoal = value.clone();
  }

  /// Distance from [target] to the camera.
  double get distance => _distance;

  /// Rotates the orbit by [deltaAzimuth] (around world up) and [deltaPolar]
  /// (elevation), radians. Polar is clamped to [[minPolar], [maxPolar]].
  void orbitBy(double deltaAzimuth, double deltaPolar) {
    _azimuthGoal += deltaAzimuth;
    _polarGoal = (_polarGoal + deltaPolar).clamp(minPolar, maxPolar);
  }

  /// Dollies toward ([amount] > 0) or away from ([amount] < 0) the target,
  /// proportional to the current distance and clamped to the distance limits.
  void dollyBy(double amount) {
    _distanceGoal = (_distanceGoal * math.exp(-amount * dollySpeed)).clamp(
      minDistance,
      maxDistance,
    );
  }

  /// Pans the target across the view by [fraction] of the viewport (its
  /// components in `[-1, 1]`), scaled by distance so the world tracks the drag.
  void panBy(Offset fraction) {
    final forward = (_targetGoal - _eyeFor(_targetGoal)).normalized();
    final right = Vector3(0.0, 1.0, 0.0).cross(forward)..normalize();
    final up = forward.cross(right)..normalize();
    final shift =
        (right * -fraction.dx + up * fraction.dy) * (_distance * panSpeed);
    _targetGoal += shift;
  }

  /// Frames [bounds] by centering the target and dollying to fit its bounding
  /// sphere, with [margin] padding.
  // TODO(camera): make framing field-of-view aware (needs the CameraComponent
  // projection) so it fills the view exactly, like PerspectiveCamera.framing.
  void frame(Aabb3 bounds, {double margin = 1.5}) {
    _targetGoal = bounds.center;
    final radius = math.max((bounds.max - bounds.min).length * 0.5, 1e-4);
    _distanceGoal = (radius * 2 * margin).clamp(minDistance, maxDistance);
  }

  @override
  void handleDragUpdate(Offset delta) {
    final k = rotateSpeed / viewportSize.height;
    orbitBy(-delta.dx * k, -delta.dy * k);
  }

  @override
  void handleSecondaryDragUpdate(Offset delta) {
    panBy(
      Offset(delta.dx / viewportSize.height, delta.dy / viewportSize.height),
    );
  }

  @override
  void handleScaleUpdate(double scaleFactor, Offset focalDelta) {
    if (scaleFactor != 1.0) dollyBy(scaleFactor - 1.0);
    if (focalDelta != Offset.zero) {
      panBy(
        Offset(
          focalDelta.dx / viewportSize.height,
          focalDelta.dy / viewportSize.height,
        ),
      );
    }
  }

  @override
  void handleScroll(double scrollDelta) =>
      dollyBy(-scrollDelta * scrollSensitivity);

  @override
  void update(double deltaSeconds) {
    final r = smoothingResponse(clampDeltaSeconds(deltaSeconds));
    _azimuth += (_azimuthGoal - _azimuth) * r;
    _polar += (_polarGoal - _polar) * r;
    _distance += (_distanceGoal - _distance) * r;
    _target += (_targetGoal - _target) * r;
    node.lookAtFrom(_eyeFor(_target), _target);
  }

  // The camera eye for a given pivot, from the current azimuth/polar/distance.
  Vector3 _eyeFor(Vector3 pivot) {
    final horizontal = math.cos(_polar) * _distance;
    return pivot +
        Vector3(-math.sin(_azimuth), 0.0, -math.cos(_azimuth)) * horizontal +
        Vector3(0.0, math.sin(_polar) * _distance, 0.0);
  }
}
