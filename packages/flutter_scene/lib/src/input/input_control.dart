import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// The device namespaces the built-in sources publish controls under.
///
/// A device id is a plain string so a source added later (a gamepad backend,
/// a MIDI pedal, a racing wheel) needs no change here and no change to the
/// serialized form of an [InputMap]. Multi-device sources suffix an index,
/// `gamepad0`, `gamepad1`, and so on.
abstract final class InputDevice {
  static const String keyboard = 'keyboard';
  static const String mouse = 'mouse';
  static const String touch = 'touch';

  /// The device id for gamepad [index], the spelling a gamepad source is
  /// expected to publish under.
  static String gamepad(int index) => 'gamepad$index';
}

/// One physical control on one device: a key, a mouse button, a stick axis.
///
/// A control is the atom an [InputBinding] refers to and the unit an
/// [InputSource] publishes values for. It is deliberately a `(device, id)`
/// string pair rather than an enum, so that:
///
///  * a source this package does not ship (a gamepad backend) can publish
///    controls without a core change, and
///  * an [InputMap] round-trips through JSON, which is what makes runtime
///    rebinding and a project-settings file possible.
///
/// Values are doubles. A digital control reports 0 or 1; an analog control
/// reports its own range (`-1..1` for a stick axis, `0..1` for a trigger).
/// {@category Picking and input}
final class InputControl {
  const InputControl(this.device, this.id);

  /// The control for a keyboard [key], keyed by the key's stable
  /// [LogicalKeyboardKey.keyId] so the mapping survives serialization.
  InputControl.key(LogicalKeyboardKey key)
    : device = InputDevice.keyboard,
      id = key.keyId.toRadixString(16);

  /// The control for mouse [button], numbered as Flutter's pointer buttons
  /// (1 primary, 2 secondary, 4 tertiary).
  const InputControl.mouseButton(int button)
    : device = InputDevice.mouse,
      id = 'button$button';

  /// The control for [control] on gamepad [pad], where [control] is a
  /// [GamepadButton] or [GamepadAxis] id.
  ///
  /// [pad] is the player slot, so a split-screen game binds player two to
  /// `pad: 1`. A source that supports only one pad publishes under 0.
  InputControl.gamepad(String control, {int pad = 0})
    : device = 'gamepad$pad',
      id = control;

  /// Which device published this control.
  final String device;

  /// The control's id within its device.
  final String id;

  /// Horizontal mouse movement since the previous frame, in logical pixels.
  static const InputControl mouseDeltaX = InputControl(
    InputDevice.mouse,
    'deltaX',
  );

  /// Vertical mouse movement since the previous frame, in logical pixels.
  /// Positive is downward, matching Flutter's screen space.
  static const InputControl mouseDeltaY = InputControl(
    InputDevice.mouse,
    'deltaY',
  );

  /// Scroll wheel movement since the previous frame.
  static const InputControl mouseScroll = InputControl(
    InputDevice.mouse,
    'scroll',
  );

  /// The serialized spelling, `device/id`.
  String get path => '$device/$id';

  /// Parses the [path] spelling. Returns null when [source] has no separator.
  static InputControl? tryParse(String source) {
    final split = source.indexOf('/');
    if (split <= 0 || split == source.length - 1) return null;
    return InputControl(
      source.substring(0, split),
      source.substring(split + 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InputControl && other.device == device && other.id == id;

  @override
  int get hashCode => Object.hash(device, id);

  @override
  String toString() => 'InputControl($path)';
}
