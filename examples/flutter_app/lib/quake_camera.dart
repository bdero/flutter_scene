import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The movement keys [QuakeCamera] consumes while enabled, so the platform
/// does not beep at held keys.
final Set<LogicalKeyboardKey> quakeCameraMoveKeys = {
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyQ,
  LogicalKeyboardKey.keyE,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

/// A free-look first-person camera: WASD moves on the look plane (strafing
/// ignores pitch, so looking down does not drift into the floor), Q/E moves
/// down/up, holding shift boosts speed, and a drag rotates the view.
///
/// Wire [onKeyEvent] into a [Focus] (autofocus), call [look] from a pan
/// update, call [move] once per frame with the elapsed seconds, and return
/// [camera] from the `SceneView` camera builder.
class QuakeCamera {
  QuakeCamera({vm.Vector3? position, this.yaw = 0.0, this.pitch = 0.0})
    : position = position ?? vm.Vector3(0, 2, 5);

  /// World-space eye position.
  vm.Vector3 position;

  /// Heading around +Y, radians. Zero looks along -Z.
  double yaw;

  /// Elevation, radians, clamped to +-[pitchLimit].
  double pitch;

  /// Maximum pitch magnitude (~86 degrees by default, so the view never
  /// flips over the poles).
  static const double pitchLimit = 1.5;

  /// Movement speed, world units per second. Scale to the scene (a 10 cm
  /// bottle and a 100 m building want very different speeds).
  double speed = 5.0;

  /// Speed multiplier while shift is held.
  double boostMultiplier = 4.0;

  /// Radians per logical pixel of drag.
  double lookSensitivity = 0.005;

  /// Whether [move] advances and [onKeyEvent] consumes movement keys.
  /// Key state is tracked regardless, so toggling on mid-hold works.
  bool enabled = true;

  final Set<LogicalKeyboardKey> _heldKeys = {};
  double _lastElapsed = 0.0;

  /// The unit look direction. At yaw = 0, pitch = 0 this is `(0, 0, -1)`.
  vm.Vector3 get forward {
    final cp = cos(pitch);
    return vm.Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp);
  }

  // Strafe-right unit vector (yaw only).
  vm.Vector3 get _right => vm.Vector3(cos(yaw), 0, -sin(yaw));

  /// The camera for the current pose.
  PerspectiveCamera get camera =>
      PerspectiveCamera(position: position.clone(), target: position + forward);

  /// Tracks held keys; reports movement keys as handled while [enabled].
  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (!quakeCameraMoveKeys.contains(key)) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _heldKeys.add(key);
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(key);
    }
    return enabled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Rotates the view by a drag delta (logical pixels). Horizontal drags
  /// turn the camera (drag right turns left, the drag-the-world
  /// convention); vertical drags pitch (drag down looks down).
  void look(Offset delta) {
    yaw += delta.dx * lookSensitivity;
    pitch = (pitch - delta.dy * lookSensitivity).clamp(-pitchLimit, pitchLimit);
  }

  /// Advances the position by the held movement keys. Call once per frame
  /// with the running elapsed time in seconds; dt is clamped so a dropped
  /// frame or focus pause does not teleport the camera.
  void move(double elapsedSeconds) {
    final dt = (elapsedSeconds - _lastElapsed).clamp(0.0, 0.1);
    _lastElapsed = elapsedSeconds;
    if (!enabled || _heldKeys.isEmpty) return;
    final keys = _heldKeys;
    final velocity = vm.Vector3.zero();
    if (keys.contains(LogicalKeyboardKey.keyW)) velocity.add(forward);
    if (keys.contains(LogicalKeyboardKey.keyS)) velocity.sub(forward);
    // D moves the camera to its own right (toward what's on the right side
    // of the screen). A moves left.
    if (keys.contains(LogicalKeyboardKey.keyD)) velocity.sub(_right);
    if (keys.contains(LogicalKeyboardKey.keyA)) velocity.add(_right);
    if (keys.contains(LogicalKeyboardKey.keyE)) {
      velocity.add(vm.Vector3(0, 1, 0));
    }
    if (keys.contains(LogicalKeyboardKey.keyQ)) {
      velocity.sub(vm.Vector3(0, 1, 0));
    }
    if (velocity.length2 < 1e-12) return;
    velocity.normalize();
    final boosted =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    position += velocity * (speed * (boosted ? boostMultiplier : 1.0) * dt);
  }

  /// Releases all held keys (call when focus is lost or the camera is
  /// toggled away, so keys released elsewhere do not stick).
  void releaseKeys() => _heldKeys.clear();

  /// Adopts [camera]'s pose, so switching to this camera does not jump.
  void syncTo(PerspectiveCamera camera) {
    position = camera.position.clone();
    final look = (camera.target - camera.position)..normalize();
    yaw = atan2(-look.x, -look.z);
    pitch = asin(look.y.clamp(-1.0, 1.0)).clamp(-pitchLimit, pitchLimit);
  }
}
