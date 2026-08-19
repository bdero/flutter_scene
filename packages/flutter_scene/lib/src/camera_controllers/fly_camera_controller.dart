import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';

/// A free-look flying camera: drag to look, WASD to move on the look plane
/// (strafing ignores pitch so looking down does not drift into the floor),
/// Q/E to move down/up, and shift to boost speed.
///
/// Yaw and a pitch clamped short of vertical drive the view, with roll pinned
/// level, so it never rolls or flips over the poles. Set [moveVertical] false
/// for a grounded first-person camera: Q/E are ignored and forward/back stays
/// horizontal.
///
/// Attach it to a node that also carries a [CameraComponent]. Drive it with a
/// [CameraControls] widget, or call [look] and set the move keys directly.
/// {@category Scene graph}
class FlyCameraController extends CameraController {
  /// Creates a fly controller starting at [position] with the given [yaw] and
  /// [pitch] (radians).
  FlyCameraController({
    Vector3? position,
    double yaw = 0.0,
    double pitch = 0.0,
    this.speed = 5.0,
    this.boostMultiplier = 4.0,
    this.lookSensitivity = 0.005,
    this.movementSmoothing = 0.0,
    this.moveVertical = true,
    this.pitchLimit = _defaultPitchLimit,
    super.smoothing = 0.0,
  }) : _position = (position ?? Vector3(0.0, 2.0, 5.0)).clone(),
       _yaw = yaw,
       _yawGoal = yaw,
       _pitch = pitch.clamp(-_defaultPitchLimit, _defaultPitchLimit),
       _pitchGoal = pitch.clamp(-_defaultPitchLimit, _defaultPitchLimit);

  static const double _defaultPitchLimit = 1.5; // ~86 degrees

  /// The movement keys this controller consumes.
  static final Set<LogicalKeyboardKey> moveKeys = {
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  /// Movement speed, world units per second.
  double speed;

  /// Speed multiplier while shift is held.
  double boostMultiplier;

  /// Radians of look per logical pixel of drag.
  double lookSensitivity;

  /// Settle time in seconds for the velocity easing (0 moves instantly).
  double movementSmoothing;

  /// Whether Q/E move vertically and forward/back follows pitch. When false the
  /// camera is grounded (first-person): Q/E ignored, forward/back stays level.
  bool moveVertical;

  /// Maximum pitch magnitude (radians), kept short of vertical.
  double pitchLimit;

  Vector3 _position;
  double _yaw;
  double _yawGoal;
  double _pitch;
  double _pitchGoal;
  final Set<LogicalKeyboardKey> _heldKeys = {};
  final Vector3 _velocity = Vector3.zero();

  /// World-space eye position.
  Vector3 get position => _position.clone();
  set position(Vector3 value) => _position = value.clone();

  /// The unit look direction. At yaw 0, pitch 0 this is `(0, 0, -1)`.
  Vector3 get forward {
    final cp = math.cos(_pitch);
    return Vector3(
      -math.sin(_yaw) * cp,
      math.sin(_pitch),
      -math.cos(_yaw) * cp,
    );
  }

  Vector3 get _right => Vector3(math.cos(_yaw), 0.0, -math.sin(_yaw));

  /// Rotates the view by a drag delta (logical pixels). Horizontal drags turn,
  /// vertical drags pitch (clamped short of vertical).
  void look(Offset delta) {
    _yawGoal += delta.dx * lookSensitivity;
    _pitchGoal = (_pitchGoal - delta.dy * lookSensitivity).clamp(
      -pitchLimit,
      pitchLimit,
    );
  }

  @override
  void handleDragUpdate(Offset delta) => look(delta);

  @override
  bool handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (!moveKeys.contains(key)) return false;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _heldKeys.add(key);
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(key);
    }
    return true;
  }

  @override
  void releaseInput() {
    _heldKeys.clear();
    _velocity.setZero();
  }

  @override
  void update(double deltaSeconds) {
    final dt = clampDeltaSeconds(deltaSeconds);
    final lookR = smoothingResponse(dt);
    _yaw += (_yawGoal - _yaw) * lookR;
    _pitch += (_pitchGoal - _pitch) * lookR;

    final moveForward = moveVertical
        ? forward
        : (Vector3(forward.x, 0.0, forward.z)..normalize());
    final targetVelocity = Vector3.zero();
    if (_heldKeys.contains(LogicalKeyboardKey.keyW)) {
      targetVelocity.add(moveForward);
    }
    if (_heldKeys.contains(LogicalKeyboardKey.keyS)) {
      targetVelocity.sub(moveForward);
    }
    // D moves toward the camera's right side of the screen; A moves left.
    if (_heldKeys.contains(LogicalKeyboardKey.keyD)) targetVelocity.sub(_right);
    if (_heldKeys.contains(LogicalKeyboardKey.keyA)) targetVelocity.add(_right);
    if (moveVertical) {
      if (_heldKeys.contains(LogicalKeyboardKey.keyE)) {
        targetVelocity.add(Vector3(0.0, 1.0, 0.0));
      }
      if (_heldKeys.contains(LogicalKeyboardKey.keyQ)) {
        targetVelocity.sub(Vector3(0.0, 1.0, 0.0));
      }
    }
    final boosted =
        _heldKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        _heldKeys.contains(LogicalKeyboardKey.shiftRight);
    if (targetVelocity.length2 > 1e-12) {
      targetVelocity
        ..normalize()
        ..scale(speed * (boosted ? boostMultiplier : 1.0));
    }
    final moveR = settleResponse(movementSmoothing, dt);
    _velocity.addScaled(targetVelocity - _velocity, moveR);
    if (_velocity.length2 > 1e-12) _position.addScaled(_velocity, dt);

    node.lookAtFrom(_position, _position + forward);
  }
}
