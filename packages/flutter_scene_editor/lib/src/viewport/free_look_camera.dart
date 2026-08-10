import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

final Set<LogicalKeyboardKey> freeLookMoveKeys = {
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyQ,
  LogicalKeyboardKey.keyE,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

/// A first-person viewport camera active during temporary free look.
class FreeLookCamera {
  FreeLookCamera({vm.Vector3? position, this.yaw = 0, this.pitch = 0})
    : position = position ?? vm.Vector3(0, 2, 5);

  vm.Vector3 position;
  double yaw;
  double pitch;
  double speed = 5;
  double boostMultiplier = 4;
  double lookSensitivity = 0.005;
  double fovRadiansY = 45 * pi / 180;
  double fovNear = 0.1;
  double fovFar = 1000;

  static const double pitchLimit = 1.5;

  final Set<LogicalKeyboardKey> _heldKeys = {};

  vm.Vector3 get forward {
    final cp = cos(pitch);
    return vm.Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp);
  }

  vm.Vector3 get right => vm.Vector3(-cos(yaw), 0, sin(yaw));

  PerspectiveCamera get camera => PerspectiveCamera(
    position: position.clone(),
    target: position + forward,
    up: vm.Vector3(0, 1, 0),
    fovRadiansY: fovRadiansY,
    fovNear: fovNear,
    fovFar: fovFar,
  );

  KeyEventResult onKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (!freeLookMoveKeys.contains(key)) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _heldKeys.add(key);
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(key);
    }
    return KeyEventResult.handled;
  }

  void look(Offset delta) {
    yaw += delta.dx * lookSensitivity;
    pitch = (pitch - delta.dy * lookSensitivity).clamp(-pitchLimit, pitchLimit);
  }

  /// Advances held-key movement and reports whether the pose changed.
  bool move(double deltaSeconds) {
    final dt = deltaSeconds.clamp(0.0, 0.1);
    if (dt <= 0) return false;

    final direction = vm.Vector3.zero();
    if (_heldKeys.contains(LogicalKeyboardKey.keyW)) direction.add(forward);
    if (_heldKeys.contains(LogicalKeyboardKey.keyS)) direction.sub(forward);
    if (_heldKeys.contains(LogicalKeyboardKey.keyD)) direction.add(right);
    if (_heldKeys.contains(LogicalKeyboardKey.keyA)) direction.sub(right);
    if (_heldKeys.contains(LogicalKeyboardKey.keyE)) direction.y += 1;
    if (_heldKeys.contains(LogicalKeyboardKey.keyQ)) direction.y -= 1;
    if (direction.length2 <= 1e-12) return false;

    direction.normalize();
    final boosted =
        _heldKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        _heldKeys.contains(LogicalKeyboardKey.shiftRight);
    position.addScaled(direction, speed * (boosted ? boostMultiplier : 1) * dt);
    return true;
  }

  void adjustSpeed(double scrollDelta) {
    if (scrollDelta == 0) return;
    speed = (speed * pow(1.15, -scrollDelta.sign)).clamp(0.01, 100000.0);
  }

  void releaseKeys() => _heldKeys.clear();

  void syncTo(Camera camera) {
    position = camera.position.clone();
    final look = camera.forward.normalized();
    yaw = atan2(-look.x, -look.z);
    pitch = asin(look.y.clamp(-1.0, 1.0));
    final projection = camera.projection;
    if (projection is PerspectiveProjection) {
      fovRadiansY = projection.fovRadiansY;
      fovNear = projection.near;
      fovFar = projection.far;
    }
    releaseKeys();
  }
}
