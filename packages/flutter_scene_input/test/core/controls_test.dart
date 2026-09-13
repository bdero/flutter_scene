import 'package:flutter/services.dart' show PhysicalKeyboardKey;
import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('key paths use W3C code names and round-trip', () {
    final w = KeyControl(PhysicalKeyboardKey.keyW.usbHidUsage);
    expect(w.path, 'keyboard/KeyW');
    expect(Control.tryParse('keyboard/KeyW'), w);
    expect(
      Control.tryParse('keyboard/ShiftLeft'),
      KeyControl(PhysicalKeyboardKey.shiftLeft.usbHidUsage),
    );
  });

  test('every generated key name matches Flutter\'s physical key usage', () {
    for (final key in [
      PhysicalKeyboardKey.space,
      PhysicalKeyboardKey.escape,
      PhysicalKeyboardKey.arrowUp,
      PhysicalKeyboardKey.numpad1,
      PhysicalKeyboardKey.metaLeft,
      PhysicalKeyboardKey.f12,
    ]) {
      final control = KeyControl(key.usbHidUsage);
      expect(control.code, isNotNull, reason: '$key has no code name');
      expect(Control.tryParse(control.path), control);
    }
  });

  test('a key without a name persists as its raw usage', () {
    const unnamed = KeyControl(0x00ff0001);
    expect(unnamed.path, 'keyboard/usb:0x00ff0001');
    expect(Control.tryParse(unnamed.path), unnamed);
  });

  test('mouse and gamepad paths round-trip', () {
    for (final Control control in [
      ...MouseControl.values,
      ...GamepadControl.values,
    ]) {
      expect(Control.tryParse(control.path), control, reason: control.path);
    }
    expect(GamepadControl.leftStickX.path, 'gamepad/leftStick/x');
  });

  test('malformed paths parse to null', () {
    expect(Control.tryParse('keyboard'), isNull);
    expect(Control.tryParse('keyboard/NotAKey'), isNull);
    expect(Control.tryParse('gamepad/nope'), isNull);
    expect(Control.tryParse('wheel/left'), isNull);
  });
}
