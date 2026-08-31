import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, KeyUpEvent;

import 'package:flutter_scene/src/input/input_control.dart';

/// The channel a source publishes control values through.
///
/// Implemented by `InputManager`. A source calls [publish] whenever a control
/// changes; it never needs to know which actions read it.
/// {@category Picking and input}
abstract interface class InputSink {
  /// Records [value] for [control]. Digital controls publish 0 or 1.
  void publish(InputControl control, double value);

  /// Records [value] for [control] for exactly one frame, after which it
  /// returns to zero unless published again.
  ///
  /// This is the shape of a *delta* control (mouse movement, scroll): it is
  /// meaningful only for the frame it arrived in, and a held value would read
  /// as an infinitely spinning camera.
  void publishDelta(InputControl control, double value);
}

/// A device backend feeding controls into an `InputManager`.
///
/// The same pluggable-backend contract the audio and physics packages use: the
/// engine ships keyboard and pointer sources, and anything else (a gamepad
/// backend over a platform plugin, a network source replaying recorded input,
/// a test harness) implements this without a core change.
/// {@category Picking and input}
abstract class InputSource {
  /// Starts publishing into [sink]. Called by `InputManager.attach`.
  void attach(InputSink sink);

  /// Stops publishing and releases any platform listeners.
  void detach();

  /// Called once per frame by `InputManager.update`, before the frame's edges
  /// are resolved, so anything published here belongs to the frame opening.
  ///
  /// For a backend that must ask the platform for state rather than being
  /// handed it: the browser's Gamepad API and every native gamepad API are
  /// polled, not evented. The event-driven sources do nothing here.
  void poll(double deltaSeconds) {}
}

/// Publishes physical keyboard state, driven by Flutter's [HardwareKeyboard].
///
/// This listens globally rather than through a focus node, which is what a
/// game usually wants. Use `InputScope` instead when keyboard input must
/// respect focus, so a text field does not also drive the player.
/// {@category Picking and input}
final class KeyboardInputSource extends InputSource {
  InputSink? _sink;

  @override
  void attach(InputSink sink) {
    _sink = sink;
    HardwareKeyboard.instance.addHandler(_handleKey);
    // Seed from keys already held when the source attaches, so a key held
    // across a scene change is not stuck reading as released.
    for (final key in HardwareKeyboard.instance.logicalKeysPressed) {
      sink.publish(InputControl.key(key), 1);
    }
  }

  @override
  void detach() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _sink = null;
  }

  bool _handleKey(KeyEvent event) {
    final sink = _sink;
    if (sink == null) return false;
    if (event is KeyDownEvent) {
      sink.publish(InputControl.key(event.logicalKey), 1);
    } else if (event is KeyUpEvent) {
      sink.publish(InputControl.key(event.logicalKey), 0);
    }
    // Never claim the event; other handlers and widgets still need it.
    return false;
  }

  /// Feeds one key event manually, for a caller routing events itself (a
  /// `Focus` widget's `onKeyEvent`) rather than listening globally.
  void handleKeyEvent(KeyEvent event) => _handleKey(event);
}

/// Publishes mouse and touch state. Driven by a widget rather than by a
/// global listener, because pointer events are inherently positional; feed it
/// from `InputScope`, or call the handlers directly from a `Listener`.
/// {@category Picking and input}
final class PointerInputSource extends InputSource {
  InputSink? _sink;
  int _buttons = 0;

  @override
  void attach(InputSink sink) => _sink = sink;

  @override
  void detach() {
    final sink = _sink;
    if (sink != null) {
      for (var button = 1; button <= 4; button <<= 1) {
        sink.publish(InputControl.mouseButton(button), 0);
      }
    }
    _buttons = 0;
    _sink = null;
  }

  /// Records the pressed-button bitmask from a pointer event.
  void handleButtons(int buttons) {
    final sink = _sink;
    if (sink == null || buttons == _buttons) return;
    for (var button = 1; button <= 4; button <<= 1) {
      final wasDown = _buttons & button != 0;
      final isDown = buttons & button != 0;
      if (wasDown != isDown) {
        sink.publish(InputControl.mouseButton(button), isDown ? 1 : 0);
      }
    }
    _buttons = buttons;
  }

  /// Records pointer movement for this frame, in logical pixels.
  void handleMove(double dx, double dy) {
    final sink = _sink;
    if (sink == null) return;
    sink.publishDelta(InputControl.mouseDeltaX, dx);
    sink.publishDelta(InputControl.mouseDeltaY, dy);
  }

  /// Records scroll movement for this frame.
  void handleScroll(double delta) =>
      _sink?.publishDelta(InputControl.mouseScroll, delta);
}
