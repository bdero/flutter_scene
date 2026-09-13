import 'package:flutter/services.dart' show PhysicalKeyboardKey;

import 'package:flutter_scene_input/src/core/action_set.dart';
import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/bindings.dart';
import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/processors.dart';
import 'package:flutter_scene_input/src/sources/keyboard_source.dart';

/// Ready-made action sets matching the bundled controllers, so a game works
/// before anyone opens a rebinding screen. Each action has `keyboard` (or
/// `mouse`) and `gamepad` slots.
///
/// They are ordinary [ActionSet]s built with the public API, so copying one
/// is the quickest start on a custom set.
/// {@category Actions}
abstract final class DefaultActions {
  /// Planar movement, +Y forward.
  static const move = VectorAction('move');

  /// View rotation, +Y up.
  static const look = DeltaAction('look');

  /// Jump.
  static const jump = ButtonAction('jump');

  /// Held to run or boost.
  static const sprint = ButtonAction('sprint');

  /// Interact or use.
  static const interact = ButtonAction('interact');

  /// Primary fire or attack.
  static const fire = ButtonAction('fire');

  /// Aim or secondary.
  static const aim = ButtonAction('aim');

  /// Open the pause menu.
  static const pause = ButtonAction('pause');

  /// Vertical movement for a fly camera, +1 up.
  static const elevate = AxisAction('elevate');

  /// Orbit displacement for an orbit camera.
  static const orbit = DeltaAction('orbit');

  /// Dolly displacement for an orbit camera, +Y in.
  static const zoom = DeltaAction('zoom');

  /// Pan displacement for an orbit camera.
  static const pan = DeltaAction('pan');

  static final _wasd = DpadBinding(
    up: PhysicalKeyboardKey.keyW.control,
    down: PhysicalKeyboardKey.keyS.control,
    left: PhysicalKeyboardKey.keyA.control,
    right: PhysicalKeyboardKey.keyD.control,
  );

  static const _leftStick = StickBinding(
    GamepadControl.leftStick,
    processors: [Deadzone(0.15)],
  );

  static const _rightStickLook = StickBinding(
    GamepadControl.rightStick,
    processors: [Deadzone(0.15), PerSecond(900)],
  );

  /// A first- or third-person character: `move`, `look`, `jump`, `sprint`,
  /// `interact`, `fire`, `aim`, `pause`.
  static final ActionSet character = ActionSet('character', {
    move: {'keyboard': _wasd, 'gamepad': _leftStick},
    look: {
      'mouse': const DeltaBinding(MouseControl.delta),
      'gamepad': _rightStickLook,
    },
    jump: {
      'keyboard': ButtonBinding(PhysicalKeyboardKey.space.control),
      'gamepad': const ButtonBinding(GamepadControl.south),
    },
    sprint: {
      'keyboard': ButtonBinding(PhysicalKeyboardKey.shiftLeft.control),
      'gamepad': const ButtonBinding(GamepadControl.leftStickPress),
    },
    interact: {
      'keyboard': ButtonBinding(PhysicalKeyboardKey.keyE.control),
      'gamepad': const ButtonBinding(GamepadControl.west),
    },
    fire: {
      'mouse': const ButtonBinding(MouseControl.left),
      'gamepad': const ButtonBinding(
        GamepadControl.rightTrigger,
        pressPoint: 0.3,
        releasePoint: 0.2,
      ),
    },
    aim: {
      'mouse': const ButtonBinding(MouseControl.right),
      'gamepad': const ButtonBinding(
        GamepadControl.leftTrigger,
        pressPoint: 0.3,
        releasePoint: 0.2,
      ),
    },
    pause: {
      'keyboard': ButtonBinding(PhysicalKeyboardKey.escape.control),
      'gamepad': const ButtonBinding(GamepadControl.start),
    },
  });

  /// A fly camera: `move`, `elevate`, `sprint` (boost), `look`. Mouse look
  /// only while the right button is held, for use without pointer lock.
  static final ActionSet flyCamera = ActionSet('flyCamera', {
    move: {'keyboard': _wasd, 'gamepad': _leftStick},
    elevate: {
      'keyboard': AxisPairBinding(
        negative: PhysicalKeyboardKey.keyQ.control,
        positive: PhysicalKeyboardKey.keyE.control,
      ),
      'gamepad': const AxisPairBinding(
        negative: GamepadControl.leftShoulder,
        positive: GamepadControl.rightShoulder,
      ),
    },
    sprint: {
      'keyboard': ButtonBinding(PhysicalKeyboardKey.shiftLeft.control),
      'gamepad': const ButtonBinding(GamepadControl.leftStickPress),
    },
    look: {
      'mouse': const GatedBinding([
        MouseControl.right,
      ], DeltaBinding(MouseControl.delta)),
      'gamepad': _rightStickLook,
    },
  });

  /// An orbit camera: `orbit` (left drag or right stick), `zoom` (scroll or
  /// triggers), `pan` (right drag or left stick).
  static final ActionSet orbitCamera = ActionSet('orbitCamera', {
    orbit: {
      'mouse': const GatedBinding([
        MouseControl.left,
      ], DeltaBinding(MouseControl.delta)),
      'gamepad': _rightStickLook,
    },
    zoom: {
      'mouse': const DeltaBinding(MouseControl.scroll),
      'gamepad': const AxisPairBinding(
        negative: GamepadControl.leftTrigger,
        positive: GamepadControl.rightTrigger,
        processors: [SwapAxes(), PerSecond(600)],
      ),
    },
    pan: {
      'mouse': const GatedBinding([
        MouseControl.right,
      ], DeltaBinding(MouseControl.delta)),
      'gamepad': const StickBinding(
        GamepadControl.leftStick,
        processors: [Deadzone(0.15), PerSecond(600)],
      ),
    },
  });
}
