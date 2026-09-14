import 'package:flutter/widgets.dart';

import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/sources/gamepad_source.dart';
import 'package:flutter_scene_input/src/sources/keyboard_source.dart';
import 'package:flutter_scene_input/src/sources/mouse_source.dart';

/// The Flutter sources wired into one [InputSystem].
/// {@category Sources}
final class FlutterInputSources {
  FlutterInputSources._(this.system) {
    system
      ..addSource(keyboard)
      ..addSource(mouse)
      ..addSource(gamepads);
    system.keyLabelResolver ??= _keyLabel;
    FocusManager.instance.addListener(_updateTextEntry);
    _updateTextEntry();
  }

  static final Expando<FlutterInputSources> _installed = Expando();

  /// Attaches the keyboard, mouse, and gamepad sources and the text-entry guard to
  /// [system] once, returning the installed sources on later calls.
  ///
  /// `InputListener` and `attachInput` call this, so apps rarely need to.
  static FlutterInputSources ensure(InputSystem system) =>
      _installed[system] ??= FlutterInputSources._(system);

  /// Detaches the sources and guard installed on [system], if any, so a later
  /// [ensure] installs fresh ones.
  static void remove(InputSystem system) {
    final installed = _installed[system];
    if (installed == null) return;
    _installed[system] = null;
    FocusManager.instance.removeListener(installed._updateTextEntry);
    system
      ..removeSource(installed.keyboard)
      ..removeSource(installed.mouse)
      ..removeSource(installed.gamepads);
  }

  /// The system these sources feed.
  final InputSystem system;

  /// The keyboard source.
  final KeyboardSource keyboard = KeyboardSource();

  /// The mouse source `InputListener` widgets feed.
  final MouseSource mouse = MouseSource();

  /// The gamepad source.
  final GamepadSource gamepads = GamepadSource();

  bool _textEntry = false;

  String? _keyLabel(KeyControl control) {
    final label = keyboard.logicalKeyFor(control)?.keyLabel;
    return label == null || label.isEmpty ? null : label;
  }

  void _updateTextEntry() {
    final context = FocusManager.instance.primaryFocus?.context;
    final active =
        context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
    if (active == _textEntry) return;
    _textEntry = active;
    for (final player in system.players) {
      player.textEntryActive = active;
    }
  }
}
