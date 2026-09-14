import 'package:flutter_scene_input/src/core/action_set.dart';
import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/bindings.dart';
import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/overrides.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';

/// One control as shown in a prompt.
/// {@category Rebinding}
final class ControlLabel {
  /// [control] shown as [label], at composite [part].
  const ControlLabel(this.control, this.label, {this.part, this.glyph});

  /// The control.
  final Control control;

  /// Human-readable text, following the keyboard layout and pad style.
  final String label;

  /// The composite part, or null.
  final String? part;

  /// Whatever `InputSystem.glyphResolver` returned for this control.
  final Object? glyph;
}

/// How a binding is shown in a prompt or a controls screen.
/// {@category Rebinding}
final class BindingDisplay {
  /// [controls] at [location], joined as [label].
  const BindingDisplay(this.location, this.controls, this.label);

  /// Where the binding lives.
  final BindingLocation location;

  /// Each control, in reading order.
  final List<ControlLabel> controls;

  /// All controls as one string (`W/A/S/D`, `Ctrl+S`), or `Unbound`.
  final String label;
}

/// Prompt text for a player's bindings.
/// {@category Rebinding}
extension BindingDisplays on PlayerInput {
  /// How [action] is bound for [device] (default the active device kind,
  /// keyboard and mouse counting together), from [slot] if given, else the
  /// first slot bound to that device family. Null when no slot fits.
  BindingDisplay? bindingDisplay(
    InputAction action, {
    DeviceKind? device,
    String? slot,
    ActionSet? set,
  }) {
    final sets = set != null
        ? [set]
        : contexts.entries.map((entry) => entry.set).toList();
    final kind = device ?? activeDeviceKind ?? DeviceKind.keyboard;
    for (final candidate in sets) {
      final slots = candidate.bindings[action];
      if (slots == null) continue;
      final names = slot != null ? [slot] : slots.keys;
      for (final name in names) {
        if (!slots.containsKey(name)) continue;
        final location = BindingLocation(candidate, action, name);
        final binding = effectiveBinding(candidate, action, name);
        if (binding == null) {
          if (slot != null) {
            return BindingDisplay(location, const [], 'Unbound');
          }
          continue;
        }
        final authored = slots[name]!;
        if (slot == null && !_fits(authored, kind)) continue;
        final controls = _labels(binding);
        return BindingDisplay(location, controls, _join(binding, controls));
      }
    }
    return null;
  }

  /// [control] as text, using the keyboard layout and the style of the
  /// gamepad this player last used.
  String controlLabel(Control control) {
    final style = _style();
    return switch (control) {
      KeyControl() =>
        system.keyLabelResolver?.call(control) ?? keyCodeLabel(control),
      MouseControl() => _mouseLabels[control]!,
      GamepadControl() => gamepadLabel(control, style),
      UnboundControl() => 'Unbound',
    };
  }

  GamepadLayoutStyle _style() {
    final pad =
        lastGamepad ??
        pairedDevices.where((d) => d.kind == DeviceKind.gamepad).firstOrNull;
    if (pad == null) return GamepadLayoutStyle.generic;
    return GamepadLayoutStyle.guess(name: pad.name, vendorId: pad.vendorId);
  }

  static bool _fits(Binding binding, DeviceKind kind) {
    final kinds = {for (final c in binding.controls) c.device};
    return kind == DeviceKind.gamepad
        ? kinds.contains(DeviceKind.gamepad)
        : kinds.contains(DeviceKind.keyboard) ||
              kinds.contains(DeviceKind.mouse);
  }

  List<ControlLabel> _labels(Binding binding) {
    ControlLabel label(Control control, [String? part]) => ControlLabel(
      control,
      controlLabel(control),
      part: part,
      glyph: system.glyphResolver?.call(control, _style()),
    );
    return switch (binding) {
      DpadBinding(:final up, :final left, :final down, :final right) => [
        label(up, 'up'),
        label(left, 'left'),
        label(down, 'down'),
        label(right, 'right'),
      ],
      AxisPairBinding(:final negative, :final positive) => [
        label(negative, 'negative'),
        label(positive, 'positive'),
      ],
      ChordBinding(:final modifiers, :final trigger) => [
        for (var i = 0; i < modifiers.length; i++)
          label(modifiers[i], 'modifier$i'),
        label(trigger, 'trigger'),
      ],
      GatedBinding(:final modifiers, binding: final inner) => [
        for (final modifier in modifiers) label(modifier),
        ..._labels(inner),
      ],
      _ => [label(controlAt(binding, null) ?? UnboundControl.instance)],
    };
  }

  static String _join(Binding binding, List<ControlLabel> labels) {
    final text = labels.map((l) => l.label).toList();
    return switch (binding) {
      ChordBinding() || GatedBinding() => text.join(' + '),
      _ => text.join('/'),
    };
  }
}

/// A readable name for a key from its W3C code, used until the keyboard
/// source has seen the key's logical label.
String keyCodeLabel(KeyControl control) {
  final code = control.code;
  if (code == null) return 'Key ${control.usage.toRadixString(16)}';
  final named = _keyNames[code];
  if (named != null) return named;
  if (code.startsWith('Key') && code.length == 4) return code.substring(3);
  if (code.startsWith('Digit') && code.length == 6) return code.substring(5);
  if (code.startsWith('Numpad')) return 'Num ${code.substring(6)}';
  for (final side in ['Left', 'Right']) {
    if (code.endsWith(side)) {
      final base = code.substring(0, code.length - side.length);
      return '$side ${_keyNames[base] ?? base}';
    }
  }
  return code;
}

const Map<String, String> _keyNames = {
  'Control': 'Ctrl',
  'Meta': 'Meta',
  'Escape': 'Esc',
  'ArrowUp': 'Up',
  'ArrowDown': 'Down',
  'ArrowLeft': 'Left',
  'ArrowRight': 'Right',
  'Backquote': '`',
  'Minus': '-',
  'Equal': '=',
  'BracketLeft': '[',
  'BracketRight': ']',
  'Backslash': r'\',
  'Semicolon': ';',
  'Quote': "'",
  'Comma': ',',
  'Period': '.',
  'Slash': '/',
  'PageUp': 'Page Up',
  'PageDown': 'Page Down',
  'CapsLock': 'Caps Lock',
};

const Map<MouseControl, String> _mouseLabels = {
  MouseControl.left: 'Left Click',
  MouseControl.right: 'Right Click',
  MouseControl.middle: 'Middle Click',
  MouseControl.back: 'Mouse Back',
  MouseControl.forward: 'Mouse Forward',
  MouseControl.delta: 'Mouse',
  MouseControl.scroll: 'Scroll',
};

/// [control]'s printed label on a pad of [style].
String gamepadLabel(GamepadControl control, GamepadLayoutStyle style) {
  const faces = {
    GamepadLayoutStyle.xbox: ['A', 'B', 'X', 'Y'],
    GamepadLayoutStyle.playstation: ['Cross', 'Circle', 'Square', 'Triangle'],
    GamepadLayoutStyle.nintendo: ['B', 'A', 'Y', 'X'],
    GamepadLayoutStyle.generic: ['South', 'East', 'West', 'North'],
  };
  const shoulders = {
    GamepadLayoutStyle.xbox: ['LB', 'RB', 'LT', 'RT', 'View', 'Menu', 'Xbox'],
    GamepadLayoutStyle.playstation: [
      'L1',
      'R1',
      'L2',
      'R2',
      'Create',
      'Options',
      'PS',
    ],
    GamepadLayoutStyle.nintendo: [
      'L',
      'R',
      'ZL',
      'ZR',
      'Minus',
      'Plus',
      'Home',
    ],
    GamepadLayoutStyle.generic: [
      'L1',
      'R1',
      'L2',
      'R2',
      'Select',
      'Start',
      'Home',
    ],
  };
  final face = faces[style]!;
  final side = shoulders[style]!;
  final stickClick = style == GamepadLayoutStyle.playstation
      ? const ['L3', 'R3']
      : const ['LS', 'RS'];
  return switch (control) {
    GamepadControl.south => face[0],
    GamepadControl.east => face[1],
    GamepadControl.west => face[2],
    GamepadControl.north => face[3],
    GamepadControl.leftShoulder => side[0],
    GamepadControl.rightShoulder => side[1],
    GamepadControl.leftTrigger => side[2],
    GamepadControl.rightTrigger => side[3],
    GamepadControl.select => side[4],
    GamepadControl.start => side[5],
    GamepadControl.home => side[6],
    GamepadControl.leftStickPress => stickClick[0],
    GamepadControl.rightStickPress => stickClick[1],
    GamepadControl.dpadUp => 'D-pad Up',
    GamepadControl.dpadDown => 'D-pad Down',
    GamepadControl.dpadLeft => 'D-pad Left',
    GamepadControl.dpadRight => 'D-pad Right',
    GamepadControl.touchpad => 'Touchpad',
    GamepadControl.leftStick => 'Left Stick',
    GamepadControl.rightStick => 'Right Stick',
    GamepadControl.leftStickX => 'Left Stick X',
    GamepadControl.leftStickY => 'Left Stick Y',
    GamepadControl.rightStickX => 'Right Stick X',
    GamepadControl.rightStickY => 'Right Stick Y',
  };
}
