import 'package:flutter_scene/src/input/input_control.dart';
import 'package:flutter_scene/src/input/input_source.dart';

/// The control ids a gamepad source publishes buttons under.
///
/// The names are positional rather than branded: [south] is A on an Xbox pad,
/// Cross on a PlayStation pad, and B on a Nintendo one, and a binding written
/// against [south] means "the bottom face button" on all three. Binding to a
/// letter instead would silently mean a different physical button per vendor.
///
/// A source is free to publish ids outside this set (a wheel's pedals, a
/// flight stick's hat); these are the ones [InputMap.defaults] binds and the
/// ones a rebinding screen can label.
/// {@category Picking and input}
abstract final class GamepadButton {
  /// Bottom face button: Xbox A, PlayStation Cross, Nintendo B.
  static const String south = 'south';

  /// Right face button: Xbox B, PlayStation Circle, Nintendo A.
  static const String east = 'east';

  /// Left face button: Xbox X, PlayStation Square, Nintendo Y.
  static const String west = 'west';

  /// Top face button: Xbox Y, PlayStation Triangle, Nintendo X.
  static const String north = 'north';

  static const String leftShoulder = 'leftShoulder';
  static const String rightShoulder = 'rightShoulder';

  /// The analog triggers, also published as buttons so a binding can treat
  /// one as digital through [ButtonBinding.threshold].
  static const String leftTrigger = 'leftTrigger';
  static const String rightTrigger = 'rightTrigger';

  /// Back/Select/Share/Minus.
  static const String select = 'select';

  /// Start/Options/Plus.
  static const String start = 'start';

  /// The stick clicks, L3 and R3.
  static const String leftStick = 'leftStick';
  static const String rightStick = 'rightStick';

  static const String dpadUp = 'dpadUp';
  static const String dpadDown = 'dpadDown';
  static const String dpadLeft = 'dpadLeft';
  static const String dpadRight = 'dpadRight';

  /// The vendor button: Xbox Guide, PlayStation PS, Nintendo Home. Some
  /// platforms reserve it and never report it.
  static const String guide = 'guide';

  /// The button order of the W3C Gamepad API's `"standard"` mapping, which is
  /// also SDL's and the one every major controller reports. A source that
  /// receives buttons as a flat indexed array can hand it straight to
  /// [GamepadInputSource.publishPad].
  static const List<String> standardOrder = [
    south,
    east,
    west,
    north,
    leftShoulder,
    rightShoulder,
    leftTrigger,
    rightTrigger,
    select,
    start,
    leftStick,
    rightStick,
    dpadUp,
    dpadDown,
    dpadLeft,
    dpadRight,
    guide,
  ];
}

/// The control ids a gamepad source publishes analog axes under.
///
/// Values run `-1..1`. **Y is positive downward**, as the W3C Gamepad API and
/// SDL both report it; a [StickBinding] with `invertY: true` turns that into
/// the engine's +Y forward/up convention, which is what
/// [InputMap.defaults] does.
/// {@category Picking and input}
abstract final class GamepadAxis {
  static const String leftX = 'leftX';
  static const String leftY = 'leftY';
  static const String rightX = 'rightX';
  static const String rightY = 'rightY';

  /// The axis order of the W3C Gamepad API's `"standard"` mapping.
  static const List<String> standardOrder = [leftX, leftY, rightX, rightY];
}

/// A device backend for gamepads.
///
/// Flutter exposes no gamepad API, so a gamepad reaches the engine through one
/// of these: [WebGamepadSource] on web, or a platform plugin implementing this
/// contract on native. Subclasses do the platform work and call [publishPad]
/// and [disconnectPad]; the bookkeeping that a manager needs, publishing only
/// what changed and releasing a pad's controls when it goes away, lives here.
///
/// A source that must ask the platform for state rather than being handed it
/// does that work in [poll], which `InputManager.update` calls once per frame.
/// {@category Picking and input}
abstract class GamepadInputSource extends InputSource {
  InputSink? _sink;

  /// The last published value of each control, per pad, so a frame publishes
  /// only what moved. A pad reports its full state every poll, and most of it
  /// is unchanged.
  final Map<int, Map<String, double>> _published = {};

  /// The sink this source publishes into, or null while detached.
  InputSink? get sink => _sink;

  /// The pad indices this source currently has state for.
  Iterable<int> get connectedPads => _published.keys;

  @override
  void attach(InputSink sink) => _sink = sink;

  @override
  void detach() {
    for (final pad in _published.keys.toList()) {
      disconnectPad(pad);
    }
    _sink = null;
  }

  /// Publishes one pad's state, [buttons] and [axes] in [standardOrder].
  ///
  /// Both lists may be short (a pad reporting fewer controls) or long (extra
  /// controls past the standard mapping); trailing entries with no name are
  /// published under their index, so a device-specific binding can still reach
  /// them.
  void publishPad(
    int pad, {
    required List<double> buttons,
    required List<double> axes,
  }) {
    final previous = _published.putIfAbsent(pad, () => <String, double>{});
    for (var i = 0; i < buttons.length; i++) {
      _publishControl(pad, previous, _buttonId(i), buttons[i]);
    }
    for (var i = 0; i < axes.length; i++) {
      _publishControl(pad, previous, _axisId(i), axes[i]);
    }
  }

  /// Releases every control of [pad] and forgets it.
  ///
  /// Call when a pad is unplugged, or a key held at the moment it vanished
  /// stays held forever.
  void disconnectPad(int pad) {
    final previous = _published.remove(pad);
    final sink = _sink;
    if (previous == null || sink == null) return;
    for (final entry in previous.entries) {
      if (entry.value != 0) {
        sink.publish(InputControl.gamepad(entry.key, pad: pad), 0);
      }
    }
  }

  void _publishControl(
    int pad,
    Map<String, double> previous,
    String id,
    double value,
  ) {
    if (previous[id] == value) return;
    previous[id] = value;
    _sink?.publish(InputControl.gamepad(id, pad: pad), value);
  }

  static String _buttonId(int index) =>
      index < GamepadButton.standardOrder.length
      ? GamepadButton.standardOrder[index]
      : 'button$index';

  static String _axisId(int index) => index < GamepadAxis.standardOrder.length
      ? GamepadAxis.standardOrder[index]
      : 'axis$index';
}
