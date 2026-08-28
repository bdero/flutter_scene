import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_pose.dart';

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

  // Movement intent from [setMoveInput], held until the caller changes it,
  // the same shape as ThirdPersonControllerComponent.setMoveInput. It sums
  // with the held keys rather than replacing them, so a project can drive
  // this controller from an InputManager, from raw key events, or from both
  // at once without either source cancelling the other.
  final Vector2 _moveInput = Vector2.zero();
  double _elevateInput = 0.0;
  bool _boostInput = false;

  /// World-space eye position.
  Vector3 get position => _position.clone();
  set position(Vector3 value) => _position = value.clone();

  /// Rotation around world up, in radians (its eased, current value).
  double get yaw => _yaw;

  /// Look elevation, in radians (its eased, current value), within
  /// +/-[pitchLimit]. Positive looks up.
  double get pitch => _pitch;

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

  /// Feeds device-agnostic movement intent, held until the next call.
  ///
  /// [move] is planar, `-1..1` on each axis with **+Y forward**, matching
  /// `ThirdPersonControllerComponent.setMoveInput` and the engine's `move`
  /// input action rather than Flutter's screen space. [elevate] is `-1..1`
  /// with +1 up, and is ignored when [moveVertical] is false. [boost] applies
  /// [boostMultiplier].
  ///
  /// This is the hook an `InputManager` drives (see `applyInput` in
  /// `package:flutter_scene/input.dart`); it is independent of
  /// [handleKeyEvent], and the two sum, so a rebindable action set and the
  /// built-in WASD handling can coexist.
  void setMoveInput(Vector2 move, {double elevate = 0.0, bool boost = false}) {
    _moveInput.setFrom(move);
    _elevateInput = elevate;
    _boostInput = boost;
  }

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
    _moveInput.setZero();
    _elevateInput = 0.0;
    _boostInput = false;
    _velocity.setZero();
  }

  @override
  void advance(double deltaSeconds) {
    final lookR = smoothingResponse(deltaSeconds);
    _yaw += (_yawGoal - _yaw) * lookR;
    _pitch += (_pitchGoal - _pitch) * lookR;

    final moveForward = moveVertical
        ? forward
        : (Vector3(forward.x, 0.0, forward.z)..normalize());

    // Forward and strafe amounts, summed from the held keys and the intent
    // set through [setMoveInput]. D moves toward the camera's right side of
    // the screen; A moves left.
    var alongForward = _moveInput.y;
    var alongRight = _moveInput.x;
    var alongUp = moveVertical ? _elevateInput : 0.0;
    if (_heldKeys.contains(LogicalKeyboardKey.keyW)) alongForward += 1.0;
    if (_heldKeys.contains(LogicalKeyboardKey.keyS)) alongForward -= 1.0;
    if (_heldKeys.contains(LogicalKeyboardKey.keyD)) alongRight += 1.0;
    if (_heldKeys.contains(LogicalKeyboardKey.keyA)) alongRight -= 1.0;
    if (moveVertical) {
      if (_heldKeys.contains(LogicalKeyboardKey.keyE)) alongUp += 1.0;
      if (_heldKeys.contains(LogicalKeyboardKey.keyQ)) alongUp -= 1.0;
    }

    final targetVelocity = Vector3.zero();
    if (alongForward != 0.0) {
      targetVelocity.addScaled(moveForward, alongForward);
    }
    // _right points to the camera's left in world space, hence the negation.
    if (alongRight != 0.0) {
      targetVelocity.addScaled(_right, -alongRight);
    }
    if (alongUp != 0.0) {
      targetVelocity.y += alongUp;
    }

    final boosted =
        _boostInput ||
        _heldKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        _heldKeys.contains(LogicalKeyboardKey.shiftRight);
    final length = targetVelocity.length;
    if (length > 1e-6) {
      // Clamped rather than normalized, so analog input (a stick pushed
      // halfway) keeps its magnitude while any combination of held keys still
      // reaches full speed, exactly as before.
      targetVelocity.scale(
        speed * (boosted ? boostMultiplier : 1.0) / math.max(length, 1.0),
      );
    }
    final moveR = settleResponse(movementSmoothing, deltaSeconds);
    _velocity.addScaled(targetVelocity - _velocity, moveR);
    if (_velocity.length2 > 1e-12) _position.addScaled(_velocity, deltaSeconds);

    setPose(CameraPose.lookAt(_position, _position + forward));
  }
}
