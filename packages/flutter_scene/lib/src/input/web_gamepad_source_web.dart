import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:flutter_scene/src/input/gamepad.dart';

/// Reads gamepads through the browser's Gamepad API.
///
/// The Gamepad API is polled, not evented, and it is also *gated*: a browser
/// reports no pads at all until the page has seen a button press on one, which
/// is a deliberate fingerprinting defence. So a pad that is plugged in and
/// idle is invisible until the player presses something, and there is nothing
/// the engine can do about that but say so.
///
/// Attach it like any other source; it is inert off the web, so no call site
/// needs to branch on the platform:
///
/// ```dart
/// final input = InputManager(
///   sources: [WebGamepadSource()],
/// );
/// ```
///
/// Axis values arrive `-1..1` with Y positive downward, and buttons `0..1`
/// with the analog triggers reporting their pull, exactly the shape
/// [InputMap.defaults] binds.
/// {@category Picking and input}
final class WebGamepadSource extends GamepadInputSource {
  /// Whether this source can read gamepads here. True on the web.
  bool get isSupported => true;

  // Reused across polls so a steady frame allocates no lists.
  final List<double> _buttons = [];
  final List<double> _axes = [];
  final Set<int> _seen = {};

  @override
  void poll(double deltaSeconds) {
    if (sink == null) return;
    final pads = web.window.navigator.getGamepads().toDart;
    _seen.clear();
    for (final pad in pads) {
      // The array is sparse: an unplugged slot is null, and it keeps its index
      // so the remaining pads do not renumber under the player.
      if (pad == null || !pad.connected) continue;
      _seen.add(pad.index);
      _readPad(pad);
    }
    // Anything that was connected last poll and is not in this one has gone.
    for (final pad in connectedPads.toList()) {
      if (!_seen.contains(pad)) disconnectPad(pad);
    }
  }

  void _readPad(web.Gamepad pad) {
    _buttons.clear();
    for (final button in pad.buttons.toDart) {
      // `value` is the analog pull for a trigger and 0/1 for a digital button,
      // except on the browsers that leave it at 0 and only set `pressed`.
      final value = button.value;
      _buttons.add(value != 0 ? value : (button.pressed ? 1.0 : 0.0));
    }
    _axes.clear();
    for (final axis in pad.axes.toDart) {
      _axes.add(axis.toDartDouble);
    }
    publishPad(pad.index, buttons: _buttons, axes: _axes);
  }
}
