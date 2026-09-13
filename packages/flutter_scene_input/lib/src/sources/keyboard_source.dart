import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/input_system.dart';

/// Publishes physical keyboard state from [HardwareKeyboard].
///
/// Listens globally and never consumes events, so shortcuts and text fields
/// keep working; the text-entry guard, not focus, keeps typing from driving
/// gameplay. Key repeats are ignored, keys already held when the source
/// attaches are seeded, and every held key is released when the app loses
/// focus or is hidden, so no key sticks down across an alt-tab.
/// {@category Sources}
final class KeyboardSource extends InputSource {
  InputSink? _sink;
  InputDevice? _device;
  AppLifecycleListener? _lifecycle;
  final Set<int> _held = {};
  final Map<int, LogicalKeyboardKey> _lastLogical = {};

  /// The logical key most recently produced by the physical key [control],
  /// for labels that follow the user's keyboard layout. Null until the key
  /// has been pressed.
  LogicalKeyboardKey? logicalKeyFor(KeyControl control) =>
      _lastLogical[control.usage];

  @override
  void attach(InputSink sink) {
    _sink = sink;
    _device = sink.connectDevice(DeviceKind.keyboard, name: 'Keyboard');
    HardwareKeyboard.instance.addHandler(_handleKey);
    for (final key in HardwareKeyboard.instance.physicalKeysPressed) {
      _set(key.usbHidUsage, true);
    }
    _lifecycle = AppLifecycleListener(
      onInactive: _releaseAll,
      onHide: _releaseAll,
    );
  }

  @override
  void detach() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _lifecycle?.dispose();
    _lifecycle = null;
    _releaseAll();
    final device = _device;
    if (device != null) _sink?.disconnectDevice(device);
    _device = null;
    _sink = null;
  }

  bool _handleKey(KeyEvent event) {
    final usage = event.physicalKey.usbHidUsage;
    switch (event) {
      case KeyDownEvent():
        _lastLogical[usage] = event.logicalKey;
        _set(usage, true);
      case KeyUpEvent():
        _set(usage, false);
      case KeyRepeatEvent():
        break;
    }
    return false;
  }

  void _set(int usage, bool down) {
    final sink = _sink;
    final device = _device;
    if (sink == null || device == null) return;
    if (down ? !_held.add(usage) : !_held.remove(usage)) return;
    sink.publish(device, KeyControl(usage), down ? 1 : 0);
  }

  void _releaseAll() {
    for (final usage in _held.toList()) {
      _set(usage, false);
    }
  }
}

/// The [KeyControl] for a Flutter physical key.
/// {@category Controls}
extension PhysicalKeyControl on PhysicalKeyboardKey {
  /// This key as a control, identified by its USB HID usage.
  KeyControl get control => KeyControl(usbHidUsage);
}
