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
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

/// A free-look first-person camera: WASD moves on the look plane,
/// space/shift moves up/down, and a drag rotates the view.
///
/// Wire [onKeyEvent] into a [Focus] (autofocus), call [look] from a pan
/// update, call [move] once per frame with the elapsed seconds, and return
/// [camera] from the `SceneView` camera builder.
class QuakeCamera {
  QuakeCamera({vm.Vector3? position, this.yaw = 0.0, this.pitch = 0.0})
    : position = position ?? vm.Vector3(0, 2, 8);

  /// World-space eye position.
  vm.Vector3 position;

  /// Heading around +Y, radians. Zero looks along +Z.
  double yaw;

  /// Elevation, radians, clamped to (-1.5, 1.5).
  double pitch;

  /// Movement speed, world units per second.
  double speed = 20.0;

  /// Radians per logical pixel of drag.
  double lookSensitivity = 0.005;

  /// Whether [move] advances and [onKeyEvent] consumes movement keys.
  /// Key state is tracked regardless, so toggling on mid-hold works.
  bool enabled = true;

  final Set<LogicalKeyboardKey> _heldKeys = {};
  double _lastElapsed = 0.0;

  /// The unit look direction from [yaw] (around Y) and [pitch].
  vm.Vector3 get forward =>
      vm.Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch));

  /// The camera for the current pose.
  PerspectiveCamera get camera =>
      PerspectiveCamera(position: position.clone(), target: position + forward);

  /// Tracks held keys; reports movement keys as handled while [enabled].
  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _heldKeys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(event.logicalKey);
    }
    return enabled && quakeCameraMoveKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// Rotates the view by a drag delta (logical pixels).
  void look(Offset delta) {
    yaw += delta.dx * lookSensitivity;
    pitch = (pitch - delta.dy * lookSensitivity).clamp(-1.5, 1.5);
  }

  /// Advances the position by the held movement keys. Call once per frame
  /// with the running elapsed time in seconds.
  void move(double elapsedSeconds) {
    final dt = (elapsedSeconds - _lastElapsed).clamp(0.0, 0.1);
    _lastElapsed = elapsedSeconds;
    if (!enabled) return;
    final keys = _heldKeys;
    final forward = this.forward;
    final right = vm.Vector3(0, 1, 0).cross(forward)..normalize();
    final movement = vm.Vector3.zero();
    if (keys.contains(LogicalKeyboardKey.keyW)) movement.add(forward);
    if (keys.contains(LogicalKeyboardKey.keyS)) movement.sub(forward);
    if (keys.contains(LogicalKeyboardKey.keyD)) movement.add(right);
    if (keys.contains(LogicalKeyboardKey.keyA)) movement.sub(right);
    if (keys.contains(LogicalKeyboardKey.space)) {
      movement.add(vm.Vector3(0, 1, 0));
    }
    if (keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight)) {
      movement.sub(vm.Vector3(0, 1, 0));
    }
    if (movement.length2 > 1e-6) {
      movement.normalize();
      position += movement * (speed * dt);
    }
  }

  /// Releases all held keys (call when focus is lost or the camera is
  /// toggled away, so keys released elsewhere do not stick).
  void releaseKeys() => _heldKeys.clear();

  /// Adopts [camera]'s pose, so switching to this camera does not jump.
  void syncTo(PerspectiveCamera camera) {
    position = camera.position.clone();
    final look = (camera.target - camera.position)..normalize();
    yaw = atan2(look.x, look.z);
    pitch = asin(look.y.clamp(-1.0, 1.0));
  }
}
