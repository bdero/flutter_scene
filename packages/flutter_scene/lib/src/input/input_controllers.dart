import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/fly_camera_controller.dart';
import 'package:flutter_scene/src/input/input_manager.dart';
import 'package:flutter_scene/src/kit/character/third_person_controller.dart';

/// Drives a [FlyCameraController] from an [InputManager]'s actions.
///
/// The dependency runs one way: the controller knows nothing about input, and
/// this glue lives in `package:flutter_scene/input.dart` so a project that
/// never imports input carries none of it.
/// {@category Picking and input}
extension FlyCameraInput on FlyCameraController {
  /// Applies one frame of [input] to this controller.
  ///
  /// Call after `InputManager.update` and before the scene's own update:
  ///
  /// ```dart
  /// input.update(dt);
  /// flyCamera.applyInput(input);
  /// scene.update(dt);
  /// ```
  ///
  /// Reads the `move` (vector2, +Y forward), `look` (vector2, +Y up),
  /// `sprint` (button), and `elevate` (axis, +1 up) actions of
  /// [InputMap.defaults]. Pass different names to read a different set, or
  /// null to skip an action entirely; a name that is not in the map throws,
  /// rather than silently doing nothing.
  ///
  /// [lookWhile] gates look on a button action being held. It defaults to
  /// null, meaning the camera turns whenever the pointer moves over the view.
  /// The engine has no pointer capture, so unless the platform hides and locks
  /// the cursor, that reads as the camera drifting on any mouse movement; pass
  /// `'fire'` or `'aim'` for the editor-style drag-to-look instead.
  ///
  /// [lookScale] multiplies the look action before it reaches
  /// [FlyCameraController.lookSensitivity], for a per-camera sensitivity on
  /// top of the shared binding.
  void applyInput(
    InputManager input, {
    String? move = 'move',
    String? look = 'look',
    String? sprint = 'sprint',
    String? elevate = 'elevate',
    String? lookWhile,
    double lookScale = 1.0,
  }) {
    setMoveInput(
      move == null ? Vector2.zero() : input.vector2(move),
      elevate: elevate == null ? 0.0 : input.axis(elevate),
      boost: sprint != null && input.isPressed(sprint),
    );
    if (look == null) return;
    if (lookWhile != null && !input.isPressed(lookWhile)) return;
    final delta = input.vector2(look);
    if (delta.x == 0 && delta.y == 0) return;
    // The look action is +Y up; `look` takes a screen-space drag delta, whose
    // Y grows downward.
    this.look(Offset(delta.x * lookScale, -delta.y * lookScale));
  }
}

/// Drives a [ThirdPersonControllerComponent] from an [InputManager]'s actions.
/// {@category Picking and input}
extension ThirdPersonInput on ThirdPersonControllerComponent {
  /// Applies one frame of [input] to this character.
  ///
  /// Reads `move` (vector2, +Y forward), `sprint` (button), and `jump`
  /// (button, on the frame it goes down so a tap is never dropped). Pass
  /// [cameraHeadingYaw] to move relative to where the camera is facing, the
  /// same argument [setMoveInput] takes.
  void applyInput(
    InputManager input, {
    String? move = 'move',
    String? sprint = 'sprint',
    String? jump = 'jump',
    double? cameraHeadingYaw,
  }) {
    setMoveInput(
      move == null ? Vector2.zero() : input.vector2(move),
      isRunning: sprint != null && input.isPressed(sprint),
      cameraHeadingYaw: cameraHeadingYaw,
    );
    if (jump != null && input.wasPressedThisFrame(jump)) this.jump();
  }
}
