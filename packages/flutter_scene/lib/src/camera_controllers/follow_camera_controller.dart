import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/node.dart';

/// A third-person camera that eases toward following [followTarget], orbiting
/// it at [yaw] / [pitch] / [distance] and looking at a point [lookHeight] above
/// its origin. Drag orbits, scroll dollies.
///
/// Position and look point both ease each frame, so the camera trails a moving
/// target smoothly instead of rigidly. Pitch is clamped so the view stays
/// upright. The horizontal [forward] / [right] basis is exposed so movement
/// input can stay camera-relative (pressing forward walks away from the
/// camera whichever way it faces).
///
/// Attach it to a node that also carries a [CameraComponent]. Drive it with a
/// [CameraControls] widget, or call [orbitBy] / [dollyBy] directly.
/// {@category Scene graph}
class FollowCameraController extends CameraController {
  /// Creates a follow controller trailing [followTarget].
  FollowCameraController({
    this.followTarget,
    this.distance = 9.0,
    this.lookHeight = 1.4,
    double yaw = 0.0,
    double pitch = 0.42,
    this.minPitch = -0.15,
    this.maxPitch = 1.3,
    this.minDistance = 0.5,
    this.maxDistance = double.infinity,
    this.rotateSpeed = math.pi,
    this.dollySpeed = 0.15,
    this.scrollSensitivity = 1 / 120,
    super.smoothing = 0.08,
  }) : _yaw = yaw,
       _pitch = pitch.clamp(minPitch, maxPitch);

  /// The node to follow. Its world-space position drives the camera; null
  /// parks the camera around the origin.
  // TODO(camera): optional collision retraction (pull in when geometry
  // occludes the target, via Scene.raycast) and an optional separate look-at
  // target distinct from the follow target.
  Node? followTarget;

  /// Distance from the look point to the camera.
  double distance;

  /// Height above the target's origin that the camera looks at.
  double lookHeight;

  /// Pitch clamp (radians).
  double minPitch;
  double maxPitch;

  /// Dolly distance clamp. [minDistance] must be > 0.
  double minDistance;
  double maxDistance;

  /// Radians of orbit per view-height of drag.
  double rotateSpeed;

  /// Proportional dolly rate (see [OrbitCameraController.dollySpeed]).
  double dollySpeed;

  /// Dolly steps per unit of scroll delta.
  double scrollSensitivity;

  double _yaw;
  double _pitch;
  final Vector3 _position = Vector3.zero();
  final Vector3 _target = Vector3.zero();
  bool _initialized = false;

  /// Orbit azimuth around the target (radians).
  double get yaw => _yaw;

  /// Orbit elevation (radians).
  double get pitch => _pitch;

  /// Unit horizontal direction the camera looks along (away from it).
  Vector3 get forward => Vector3(math.sin(_yaw), 0.0, math.cos(_yaw));

  /// Unit horizontal direction to the camera's right.
  Vector3 get right => Vector3(0.0, 1.0, 0.0).cross(forward)..normalize();

  /// Rotates the orbit by [deltaYaw] and [deltaPitch] (radians); pitch clamps.
  void orbitBy(double deltaYaw, double deltaPitch) {
    _yaw += deltaYaw;
    _pitch = (_pitch + deltaPitch).clamp(minPitch, maxPitch);
  }

  /// Dollies toward ([amount] > 0) or away from the target, proportional to
  /// the current distance and clamped to the distance limits.
  void dollyBy(double amount) {
    distance = (distance * math.exp(-amount * dollySpeed)).clamp(
      minDistance,
      maxDistance,
    );
  }

  @override
  void handleDragUpdate(Offset delta) {
    final k = rotateSpeed / viewportSize.height;
    orbitBy(-delta.dx * k, -delta.dy * k);
  }

  @override
  void handleScroll(double scrollDelta) =>
      dollyBy(-scrollDelta * scrollSensitivity);

  @override
  void update(double deltaSeconds) {
    final base =
        followTarget?.globalTransform.getTranslation() ?? Vector3.zero();
    final lookAt = base + Vector3(0.0, lookHeight, 0.0);
    final desired = _desiredPosition(lookAt);
    if (!_initialized) {
      _position.setFrom(desired);
      _target.setFrom(lookAt);
      _initialized = true;
    } else {
      final r = smoothingResponse(clampDeltaSeconds(deltaSeconds));
      _position.addScaled(desired - _position, r);
      _target.addScaled(lookAt - _target, r);
    }
    node.lookAtFrom(_position, _target);
  }

  Vector3 _desiredPosition(Vector3 lookAt) {
    final horizontal = math.cos(_pitch) * distance;
    return lookAt +
        Vector3(-math.sin(_yaw), 0.0, -math.cos(_yaw)) * horizontal +
        Vector3(0.0, math.sin(_pitch) * distance, 0.0);
  }
}
