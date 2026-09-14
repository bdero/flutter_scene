import 'package:flutter_scene_input/src/core/key_codes.g.dart';

/// The kind of device a control belongs to.
/// {@category Controls}
enum DeviceKind {
  /// A keyboard. All keyboards act as one logical device.
  keyboard,

  /// A mouse or trackpad. All pointing devices act as one logical device.
  mouse,

  /// A gamepad. Each connected pad is its own device.
  gamepad,
}

/// The shape of the value a control reports.
/// {@category Controls}
enum ControlKind {
  /// 0 or 1. Keys, mouse buttons, pad buttons.
  digital,

  /// A scalar, `-1..1` for stick axes or `0..1` for triggers.
  analog,

  /// A 2D vector with magnitude up to 1, read from two analog axes.
  stick,

  /// An unbounded 2D displacement that accumulates between reads. Mouse
  /// movement and scrolling.
  delta,
}

/// One addressable input on a device.
///
/// Every 2D control reports +Y up, mouse movement included, so a mouse and a
/// stick bound to one action agree without per-binding inversion.
///
/// [path] is the persisted spelling (`keyboard/KeyW`, `gamepad/leftStick/x`),
/// used by profiles and display; code refers to controls by value.
/// {@category Controls}
sealed class Control {
  /// Parses a [path]. Returns null for an unknown or malformed path.
  static Control? tryParse(String path) {
    final split = path.indexOf('/');
    if (split <= 0) return null;
    final device = path.substring(0, split);
    final id = path.substring(split + 1);
    switch (device) {
      case 'keyboard':
        return KeyControl.tryParse(id);
      case 'mouse':
        for (final control in MouseControl.values) {
          if (control._id == id) return control;
        }
      case 'gamepad':
        for (final control in GamepadControl.values) {
          if (control._id == id) return control;
        }
    }
    return null;
  }

  /// The device kind this control belongs to.
  DeviceKind get device;

  /// The shape of the value this control reports.
  ControlKind get kind;

  /// The persisted spelling of this control.
  String get path;
}

/// The control an explicitly cleared slot or part reads: never actuated.
/// Internal; profiles persist it as `null`.
final class UnboundControl implements Control {
  const UnboundControl._();

  /// The single unbound control.
  static const UnboundControl instance = UnboundControl._();

  @override
  DeviceKind get device => DeviceKind.keyboard;

  @override
  ControlKind get kind => ControlKind.digital;

  @override
  String get path => 'unbound';
}

/// A keyboard key, identified by its USB HID usage (its physical position).
///
/// Physical rather than logical, so WASD stays in place on every keyboard
/// layout and a saved profile survives a layout change.
/// {@category Controls}
final class KeyControl implements Control {
  /// The key with USB HID [usage], the value Flutter exposes as
  /// `PhysicalKeyboardKey.usbHidUsage`.
  const KeyControl(this.usage);

  /// Parses a W3C UI Events `code` name (`KeyW`, `ShiftLeft`), or a raw
  /// `usb:0x...` usage for a key without a name.
  static KeyControl? tryParse(String code) {
    if (code.startsWith('usb:0x')) {
      final usage = int.tryParse(code.substring(6), radix: 16);
      return usage == null ? null : KeyControl(usage);
    }
    final usage = _usageForCode[code];
    return usage == null ? null : KeyControl(usage);
  }

  /// The USB HID usage.
  final int usage;

  /// The W3C UI Events `code` name, or null for a key without one.
  String? get code => kKeyCodeNames[usage];

  @override
  DeviceKind get device => DeviceKind.keyboard;

  @override
  ControlKind get kind => ControlKind.digital;

  @override
  String get path =>
      'keyboard/${code ?? 'usb:0x${usage.toRadixString(16).padLeft(8, '0')}'}';

  @override
  bool operator ==(Object other) => other is KeyControl && other.usage == usage;

  @override
  int get hashCode => usage.hashCode;

  @override
  String toString() => 'KeyControl($path)';
}

final Map<String, int> _usageForCode = {
  for (final entry in kKeyCodeNames.entries) entry.value: entry.key,
};

/// A mouse or trackpad control.
/// {@category Controls}
enum MouseControl implements Control {
  /// The primary button.
  left('left', ControlKind.digital),

  /// The secondary button.
  right('right', ControlKind.digital),

  /// The middle button or wheel press.
  middle('middle', ControlKind.digital),

  /// The back side button.
  back('back', ControlKind.digital),

  /// The forward side button.
  forward('forward', ControlKind.digital),

  /// Pointer movement in logical pixels, +Y up.
  delta('delta', ControlKind.delta),

  /// Scroll movement in logical pixels, +Y up (away from the user).
  scroll('scroll', ControlKind.delta);

  const MouseControl(this._id, this.kind);

  final String _id;

  @override
  final ControlKind kind;

  @override
  DeviceKind get device => DeviceKind.mouse;

  @override
  String get path => 'mouse/$_id';
}

/// A gamepad control, named by position rather than printed label, so
/// [south] is the bottom face button on every vendor's pad.
/// {@category Controls}
enum GamepadControl implements Control {
  /// Bottom face button.
  south('south', ControlKind.digital),

  /// Right face button.
  east('east', ControlKind.digital),

  /// Left face button.
  west('west', ControlKind.digital),

  /// Top face button.
  north('north', ControlKind.digital),

  /// Left bumper.
  leftShoulder('leftShoulder', ControlKind.digital),

  /// Right bumper.
  rightShoulder('rightShoulder', ControlKind.digital),

  /// Left trigger, `0..1`.
  leftTrigger('leftTrigger', ControlKind.analog),

  /// Right trigger, `0..1`.
  rightTrigger('rightTrigger', ControlKind.analog),

  /// The left center button (back, view, share).
  select('select', ControlKind.digital),

  /// The right center button (start, menu, options).
  start('start', ControlKind.digital),

  /// The vendor button.
  home('home', ControlKind.digital),

  /// Left stick click.
  leftStickPress('leftStickPress', ControlKind.digital),

  /// Right stick click.
  rightStickPress('rightStickPress', ControlKind.digital),

  /// D-pad up.
  dpadUp('dpadUp', ControlKind.digital),

  /// D-pad down.
  dpadDown('dpadDown', ControlKind.digital),

  /// D-pad left.
  dpadLeft('dpadLeft', ControlKind.digital),

  /// D-pad right.
  dpadRight('dpadRight', ControlKind.digital),

  /// Touchpad click.
  touchpad('touchpad', ControlKind.digital),

  /// Left stick horizontal axis, `-1..1`, +X right.
  leftStickX('leftStick/x', ControlKind.analog),

  /// Left stick vertical axis, `-1..1`, +Y up.
  leftStickY('leftStick/y', ControlKind.analog),

  /// Right stick horizontal axis, `-1..1`, +X right.
  rightStickX('rightStick/x', ControlKind.analog),

  /// Right stick vertical axis, `-1..1`, +Y up.
  rightStickY('rightStick/y', ControlKind.analog),

  /// The left stick as a vector.
  leftStick('leftStick', ControlKind.stick),

  /// The right stick as a vector.
  rightStick('rightStick', ControlKind.stick);

  const GamepadControl(this._id, this.kind);

  final String _id;

  @override
  final ControlKind kind;

  @override
  DeviceKind get device => DeviceKind.gamepad;

  @override
  String get path => 'gamepad/$_id';

  /// For a [ControlKind.stick] control, its horizontal axis.
  GamepadControl? get axisX => switch (this) {
    leftStick => leftStickX,
    rightStick => rightStickX,
    _ => null,
  };

  /// For a [ControlKind.stick] control, its vertical axis.
  GamepadControl? get axisY => switch (this) {
    leftStick => leftStickY,
    rightStick => rightStickY,
    _ => null,
  };
}

/// The face-button labeling a gamepad uses, for prompts. Controls stay
/// positional whatever the style.
/// {@category Controls}
enum GamepadLayoutStyle {
  /// A, B, X, Y with A at the bottom.
  xbox,

  /// Cross, Circle, Square, Triangle.
  playstation,

  /// B, A, Y, X with B at the bottom.
  nintendo,

  /// Unknown labeling; prompts use positions.
  generic;

  static const _sony = 0x054c;
  static const _nintendo = 0x057e;
  static const _microsoft = 0x045e;

  /// Guesses the labeling from a device [name] and USB [vendorId].
  static GamepadLayoutStyle guess({String name = '', int? vendorId}) {
    switch (vendorId) {
      case _sony:
        return playstation;
      case _nintendo:
        return nintendo;
      case _microsoft:
        return xbox;
    }
    final lower = name.toLowerCase();
    if (lower.contains('xbox') || lower.contains('xinput')) return xbox;
    if (lower.contains('dualsense') ||
        lower.contains('dualshock') ||
        lower.contains('playstation') ||
        lower.contains('ps4') ||
        lower.contains('ps5')) {
      return playstation;
    }
    if (lower.contains('pro controller') ||
        lower.contains('joy-con') ||
        lower.contains('nintendo') ||
        lower.contains('switch')) {
      return nintendo;
    }
    return generic;
  }
}
