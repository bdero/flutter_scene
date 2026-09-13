import 'package:flutter/widgets.dart';

import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/sources/keyboard_source.dart';
import 'package:flutter_scene_input/src/sources/mouse_source.dart';

/// The Flutter sources wired into one [InputSystem].
/// {@category Sources}
final class FlutterInputSources {
  FlutterInputSources._(this.system) {
    system
      ..addSource(keyboard)
      ..addSource(mouse);
    FocusManager.instance.addListener(_updateTextEntry);
    _updateTextEntry();
  }

  static final Expando<FlutterInputSources> _installed = Expando();

  /// Attaches the keyboard and mouse sources and the text-entry guard to
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
      ..removeSource(installed.mouse);
  }

  /// The system these sources feed.
  final InputSystem system;

  /// The keyboard source.
  final KeyboardSource keyboard = KeyboardSource();

  /// The mouse source `InputListener` widgets feed.
  final MouseSource mouse = MouseSource();

  bool _textEntry = false;

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
