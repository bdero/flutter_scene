import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A smooth third-person orbit camera.
///
/// It orbits a follow target at a [yaw] (azimuth) and [pitch] (elevation),
/// [distance] away, easing toward that pose each frame so motion stays
/// fluid. [orbit] rotates it (driven by drag or keys), and the horizontal
/// [forward] / [right] basis is exposed so movement input stays
/// camera-relative (pressing "forward" walks away from the camera no
/// matter which way it currently faces).
class ThirdPersonCamera {
  ThirdPersonCamera({
    this.distance = 9.0,
    this.lookHeight = 1.4,
    this.stiffness = 12.0,
    this.yaw = 0.0,
    this.pitch = 0.42,
    this.minPitch = -0.15,
    this.maxPitch = 1.3,
    Vector3? initialTarget,
  }) : _target = (initialTarget ?? Vector3.zero()).clone() {
    _position = _desiredPosition(_target);
  }

  /// Distance from the follow target to the camera.
  final double distance;

  /// Height above the target's base that the camera looks at.
  final double lookHeight;

  /// Follow responsiveness; higher snaps faster. Frame-rate independent.
  final double stiffness;

  /// Orbit azimuth around the target, radians.
  double yaw;

  /// Orbit elevation, radians (0 = level, positive = looking down).
  double pitch;

  /// Pitch clamp range.
  final double minPitch;
  final double maxPitch;

  late Vector3 _position;
  Vector3 _target;

  /// The camera to render with this frame.
  Camera get camera =>
      PerspectiveCamera(position: _position.clone(), target: _target.clone());

  /// Unit horizontal direction the camera looks along (away from it).
  Vector3 get forward => Vector3(math.sin(yaw), 0.0, math.cos(yaw));

  /// Unit horizontal direction to the camera's right.
  Vector3 get right => Vector3(0.0, 1.0, 0.0).cross(forward)..normalize();

  /// Rotates the camera around its target.
  void orbit(double deltaYaw, double deltaPitch) {
    yaw += deltaYaw;
    pitch = (pitch + deltaPitch).clamp(minPitch, maxPitch);
  }

  Vector3 _desiredPosition(Vector3 lookAt) {
    // Sit behind the look direction (opposite [forward]) and raised by the
    // pitch, on a sphere of radius [distance] around the look point.
    final horizontal = math.cos(pitch) * distance;
    return lookAt +
        Vector3(-math.sin(yaw), 0.0, -math.cos(yaw)) * horizontal +
        Vector3(0.0, math.sin(pitch) * distance, 0.0);
  }

  /// Eases the camera toward following [targetBase] (the character's foot
  /// position) over [dt] seconds.
  void follow(Vector3 targetBase, double dt) {
    final lookAt = targetBase + Vector3(0.0, lookHeight, 0.0);
    final desiredPosition = _desiredPosition(lookAt);
    final t = 1.0 - math.exp(-stiffness * dt);
    _position += (desiredPosition - _position) * t;
    _target += (lookAt - _target) * t;
  }
}
