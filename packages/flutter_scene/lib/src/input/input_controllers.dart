import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/first_person_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/fly_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/rts_camera_controller.dart';
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

/// Drives a [FirstPersonCameraController] from an [InputManager]'s actions.
/// {@category Picking and input}
extension FirstPersonCameraInput on FirstPersonCameraController {
  /// Applies one frame of [input] to this camera.
  ///
  /// Reads the `look` action (vector2, +Y up) of [InputMap.defaults], scaled
  /// by [lookScale] on top of [FirstPersonCameraController.lookSensitivity].
  ///
  /// A mouse reports movement in logical pixels and a gamepad stick reports a
  /// `-1..1` push, so the same action means different things per device.
  /// [stickDegreesPerSecond] converts a stick push into a turn rate, which is
  /// what makes a pad feel right; leave [deltaSeconds] null and the whole
  /// action is treated as a pixel delta (correct for mouse-only input).
  ///
  /// [lookWhile] gates looking on a button being held, for a game that does
  /// not capture the cursor. Leave it null for a normal first-person game,
  /// where the pointer is locked and every movement is a look.
  void applyInput(
    InputManager input, {
    String? look = 'look',
    String? lookWhile,
    double lookScale = 1.0,
    double? deltaSeconds,
    double stickDegreesPerSecond = 180.0,
  }) {
    if (look == null) return;
    if (lookWhile != null && !input.isPressed(lookWhile)) return;
    final delta = input.vector2(look);
    if (delta.x == 0 && delta.y == 0) return;
    if (deltaSeconds == null) {
      // Pixels: route through look(), which applies lookSensitivity exactly
      // as a drag would. The action is +Y up and look() takes a screen-space
      // delta, whose Y grows downward.
      this.look(Offset(delta.x * lookScale, -delta.y * lookScale));
      return;
    }
    // A stick push is a rate, so it turns by an angle per second rather than
    // by an angle per unit of push.
    final rate = stickDegreesPerSecond * degrees2Radians * deltaSeconds;
    lookBy(delta.x * lookScale * rate, delta.y * lookScale * rate);
  }
}

/// Drives an [RtsCameraController] from an [InputManager]'s actions.
/// {@category Picking and input}
extension RtsCameraInput on RtsCameraController {
  /// Applies one frame of [input] to this camera.
  ///
  /// Reads `move` (vector2, +Y pans away from the camera), `rotate` (axis,
  /// +1 turns right) and `zoom` (axis, +1 zooms in) from
  /// [InputMap.strategyDefaults]. Pass null for any of them to leave that
  /// motion to something else; a name that is not in the map throws rather
  /// than silently doing nothing.
  ///
  /// [deltaSeconds] scales the rotate and zoom rates, which are per second.
  /// Panning does not need it: the controller applies the held direction on
  /// its own clock.
  void applyInput(
    InputManager input, {
    required double deltaSeconds,
    String? move = 'move',
    String? rotate = 'rotate',
    String? zoom = 'zoom',
    double rotateRadiansPerSecond = 1.6,
    double zoomStepsPerSecond = 8.0,
  }) {
    setPanInput(move == null ? Vector2.zero() : input.vector2(move));
    if (rotate != null) {
      final amount = input.axis(rotate);
      if (amount != 0.0) {
        rotateBy(amount * rotateRadiansPerSecond * deltaSeconds);
      }
    }
    if (zoom != null) {
      final amount = input.axis(zoom);
      // The wheel binding reports a whole notch in one frame rather than a
      // held rate, so it is applied as a step rather than scaled by time.
      if (amount != 0.0) zoomBy(amount * zoomStepsPerSecond * deltaSeconds);
    }
  }
}
