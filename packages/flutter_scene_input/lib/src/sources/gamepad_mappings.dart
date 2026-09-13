import 'package:gamepads/gamepads.dart' as pads;

import 'package:flutter_scene_input/src/core/controls.dart';

/// Maps an event the `gamepads` package normalized onto a control. Its
/// stick Y is already up positive and its face buttons are positional.
List<(GamepadControl, double)> controlsForNormalized(
  pads.NormalizedGamepadEvent event,
) {
  final button = event.button;
  if (button != null) {
    final control = _buttons[button];
    return control == null ? const [] : [(control, event.value)];
  }
  final axis = event.axis;
  if (axis != null) {
    final control = _axes[axis];
    return control == null ? const [] : [(control, event.value)];
  }
  return const [];
}

const Map<pads.GamepadButton, GamepadControl> _buttons = {
  pads.GamepadButton.a: GamepadControl.south,
  pads.GamepadButton.b: GamepadControl.east,
  pads.GamepadButton.x: GamepadControl.west,
  pads.GamepadButton.y: GamepadControl.north,
  pads.GamepadButton.leftBumper: GamepadControl.leftShoulder,
  pads.GamepadButton.rightBumper: GamepadControl.rightShoulder,
  pads.GamepadButton.leftTrigger: GamepadControl.leftTrigger,
  pads.GamepadButton.rightTrigger: GamepadControl.rightTrigger,
  pads.GamepadButton.back: GamepadControl.select,
  pads.GamepadButton.start: GamepadControl.start,
  pads.GamepadButton.home: GamepadControl.home,
  pads.GamepadButton.leftStick: GamepadControl.leftStickPress,
  pads.GamepadButton.rightStick: GamepadControl.rightStickPress,
  pads.GamepadButton.dpadUp: GamepadControl.dpadUp,
  pads.GamepadButton.dpadDown: GamepadControl.dpadDown,
  pads.GamepadButton.dpadLeft: GamepadControl.dpadLeft,
  pads.GamepadButton.dpadRight: GamepadControl.dpadRight,
  pads.GamepadButton.touchpad: GamepadControl.touchpad,
};

const Map<pads.GamepadAxis, GamepadControl> _axes = {
  pads.GamepadAxis.leftStickX: GamepadControl.leftStickX,
  pads.GamepadAxis.leftStickY: GamepadControl.leftStickY,
  pads.GamepadAxis.rightStickX: GamepadControl.rightStickX,
  pads.GamepadAxis.rightStickY: GamepadControl.rightStickY,
  pads.GamepadAxis.leftTrigger: GamepadControl.leftTrigger,
  pads.GamepadAxis.rightTrigger: GamepadControl.rightTrigger,
};

/// Maps a raw key the `gamepads` package could not normalize, using the key
/// spellings the dashsurfers and tps_demo games observed across platforms.
/// Keys compare lowercased with everything outside `[a-z0-9]` removed.
///
/// TODO(input-gamepad): verify these against each platform's raw keys once
/// the package's own mappings cover them, and drop entries it handles.
List<(GamepadControl, double)> controlsForRawKey(String key, double value) {
  final squashed = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final button = _rawButtons[squashed];
  if (button != null) return [(button, value.abs() >= 0.5 ? 1.0 : 0.0)];
  final axis = _rawAxes[squashed];
  if (axis != null) {
    final (control, sign) = axis;
    return [(control, value * sign)];
  }
  return const [];
}

const Map<String, GamepadControl> _rawButtons = {
  'acircle': GamepadControl.south,
  'buttona': GamepadControl.south,
  'cross': GamepadControl.south,
  'bcircle': GamepadControl.east,
  'buttonb': GamepadControl.east,
  'buttonmenu': GamepadControl.start,
  'buttonoptions': GamepadControl.start,
  'start': GamepadControl.start,
};

// Raw stick Y reports down as positive on the platforms that send these.
const Map<String, (GamepadControl, double)> _rawAxes = {
  'leftx': (GamepadControl.leftStickX, 1),
  'ljoystickxaxis': (GamepadControl.leftStickX, 1),
  'lefty': (GamepadControl.leftStickY, -1),
  'ljoystickyaxis': (GamepadControl.leftStickY, -1),
  'rightx': (GamepadControl.rightStickX, 1),
  'rjoystickxaxis': (GamepadControl.rightStickX, 1),
  'righty': (GamepadControl.rightStickY, -1),
  'rjoystickyaxis': (GamepadControl.rightStickY, -1),
  'lefttrigger': (GamepadControl.leftTrigger, 1),
  'buttonl2': (GamepadControl.leftTrigger, 1),
  'righttrigger': (GamepadControl.rightTrigger, 1),
  'buttonr2': (GamepadControl.rightTrigger, 1),
};

/// HID codes the macOS HID tap reports: `usagePage << 16 | usage`, with
/// generic desktop axes already scaled to `-1..1` and Y axes flipped up
/// positive, and the hat and d-pad usages merged into two synthetic codes.
abstract final class HidCodes {
  /// Usage page 0x01, generic desktop.
  static const int desktop = 0x01 << 16;

  /// Usage page 0x09, buttons.
  static const int button = 0x09 << 16;

  /// The hat or d-pad's horizontal component, -1, 0, or 1.
  static const int hatX = desktop | 0xfff0;

  /// The hat or d-pad's vertical component, -1, 0, or 1, up positive.
  static const int hatY = desktop | 0xfff1;
}

/// Maps a code from the macOS HID tap onto controls.
///
/// Button numbering follows the XInput order Steam Input's virtual pad was
/// observed to use (1 south, 2 east, 9 start, 12 to 15 the d-pad).
///
/// TODO(input-gamepad): the demos disagree on whether HID `z`/`rz` rest at
/// their logical minimum, and buttons 3 to 8 and 10 to 11 are assumed from the
/// XInput order. Verify both with a Steam virtual pad and a generic XInput
/// adapter.
List<(GamepadControl, double)> controlsForHidCode(int code, double value) {
  switch (code) {
    case HidCodes.hatX:
      return [
        (GamepadControl.dpadLeft, value < -0.5 ? 1 : 0),
        (GamepadControl.dpadRight, value > 0.5 ? 1 : 0),
      ];
    case HidCodes.hatY:
      return [
        (GamepadControl.dpadDown, value < -0.5 ? 1 : 0),
        (GamepadControl.dpadUp, value > 0.5 ? 1 : 0),
      ];
  }
  if (code & ~0xffff == HidCodes.button) {
    final control = _hidButtons[code & 0xffff];
    return control == null ? const [] : [(control, value != 0 ? 1.0 : 0.0)];
  }
  if (code & ~0xffff == HidCodes.desktop) {
    return switch (code & 0xffff) {
      0x30 => [(GamepadControl.leftStickX, value)],
      0x31 => [(GamepadControl.leftStickY, value)],
      0x33 => [(GamepadControl.rightStickX, value)],
      0x34 => [(GamepadControl.rightStickY, value)],
      0x32 => [(GamepadControl.leftTrigger, (value + 1) / 2)],
      0x35 => [(GamepadControl.rightTrigger, (value + 1) / 2)],
      _ => const [],
    };
  }
  return const [];
}

const Map<int, GamepadControl> _hidButtons = {
  1: GamepadControl.south,
  2: GamepadControl.east,
  3: GamepadControl.west,
  4: GamepadControl.north,
  5: GamepadControl.leftShoulder,
  6: GamepadControl.rightShoulder,
  7: GamepadControl.leftStickPress,
  8: GamepadControl.rightStickPress,
  9: GamepadControl.start,
  10: GamepadControl.select,
  11: GamepadControl.home,
  12: GamepadControl.dpadUp,
  13: GamepadControl.dpadDown,
  14: GamepadControl.dpadLeft,
  15: GamepadControl.dpadRight,
};
