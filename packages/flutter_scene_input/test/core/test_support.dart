import 'package:flutter_scene_input/flutter_scene_input.dart';

/// A clock tests advance by hand.
final class FakeClock implements InputClock {
  @override
  double seconds = 0;
}

/// Keys by USB HID usage, so core tests need no Flutter services import.
const keyW = KeyControl(0x0007001a);
const keyA = KeyControl(0x00070004);
const keyS = KeyControl(0x00070016);
const keyD = KeyControl(0x00070007);
const keyE = KeyControl(0x00070008);
const keyF = KeyControl(0x00070009);
const space = KeyControl(0x0007002c);
const controlLeft = KeyControl(0x000700e0);
const shiftLeft = KeyControl(0x000700e1);

/// A system on a [FakeClock].
(InputSystem, PlayerInput, FakeClock) makeSystem() {
  final clock = FakeClock();
  final system = InputSystem(clock: clock);
  return (system, system.defaultPlayer, clock);
}
