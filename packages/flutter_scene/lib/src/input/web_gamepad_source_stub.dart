import 'package:flutter_scene/src/input/gamepad.dart';

/// The inert form of [WebGamepadSource] on a platform with no browser.
///
/// See the web implementation for the documented behaviour; this one exists so
/// that attaching the source unconditionally compiles and does nothing off the
/// web, rather than forcing every call site to branch on the platform.
final class WebGamepadSource extends GamepadInputSource {
  /// Whether this source can read gamepads here. False off the web.
  bool get isSupported => false;

  @override
  void poll(double deltaSeconds) {}
}
