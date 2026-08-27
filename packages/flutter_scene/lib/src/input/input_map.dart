import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:flutter_scene/src/input/gamepad.dart';
import 'package:flutter_scene/src/input/input_binding.dart';
import 'package:flutter_scene/src/input/input_control.dart';

/// A named action and the bindings that can trigger it.
/// {@category Picking and input}
final class InputAction {
  InputAction(this.name, this.kind, List<InputBinding> bindings)
    : bindings = List<InputBinding>.of(bindings) {
    for (final binding in this.bindings) {
      if (binding.kind != kind) {
        throw ArgumentError.value(
          binding,
          'bindings',
          'Action "$name" is ${kind.name} but was given a ${binding.kind.name} binding',
        );
      }
    }
  }

  /// The name queried against `InputManager`.
  final String name;

  /// The value shape this action produces.
  final InputActionKind kind;

  /// Every binding that can trigger it. Mutable so a rebinding UI can edit
  /// it in place; call [InputMap.notifyRebound] afterward.
  final List<InputBinding> bindings;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'bindings': [for (final binding in bindings) binding.toJson()],
  };

  /// Rebuilds an action named [name] from [json].
  static InputAction fromJson(String name, Map<String, Object?> json) {
    final kindName = json['kind'];
    final kind = InputActionKind.values
        .where((candidate) => candidate.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw FormatException('Unknown action kind "$kindName"', json);
    }
    final rawBindings = json['bindings'];
    if (rawBindings is! List) {
      throw FormatException('Action "$name" has no bindings list', json);
    }
    return InputAction(name, kind, [
      for (final raw in rawBindings)
        if (raw is Map<String, Object?>)
          InputBinding.fromJson(raw)
        else
          throw FormatException('Malformed binding in "$name"', json),
    ]);
  }
}

/// The set of actions a game responds to, and what triggers each.
///
/// Separated from `InputManager` so one map can drive several managers (split
/// screen), be swapped wholesale (menu bindings versus gameplay bindings), and
/// round-trip through JSON for user rebinding and for a project-settings file.
///
/// It is a [ChangeNotifier]; a rebinding UI listens to repaint, and an
/// `InputManager` listens to drop its per-action caches.
/// {@category Picking and input}
final class InputMap extends ChangeNotifier {
  InputMap([Iterable<InputAction> actions = const []]) {
    for (final action in actions) {
      _actions[action.name] = action;
    }
  }

  /// A keyboard-and-mouse map covering the verbs the bundled character and
  /// camera controllers already take, so a project has something working
  /// before anyone opens a rebinding screen.
  ///
  /// Every action carries a keyboard-and-mouse binding and a gamepad one, so a
  /// player can pick up a pad mid-session without rebinding anything; an action
  /// takes the strongest of its bindings, so the two never fight.
  ///
  /// `move` (WASD or left stick, +Y forward), `look` (mouse delta or right
  /// stick), `jump` (space, gamepad south), `sprint` (left shift, L3),
  /// `elevate` (Q/E or the shoulders, +1 up, for a fly camera), `interact`
  /// (E, gamepad west), `fire` (primary mouse, right trigger), `aim`
  /// (secondary mouse, left trigger), `pause` (escape, start).
  ///
  /// The gamepad bindings name positions, not letters, so `south` is the
  /// bottom face button on every vendor's pad. See [GamepadButton].
  factory InputMap.defaults() => InputMap([
    InputAction('move', InputActionKind.vector2, [
      CompositeVector2Binding(
        up: InputControl.key(LogicalKeyboardKey.keyW),
        down: InputControl.key(LogicalKeyboardKey.keyS),
        left: InputControl.key(LogicalKeyboardKey.keyA),
        right: InputControl.key(LogicalKeyboardKey.keyD),
      ),
      CompositeVector2Binding(
        up: InputControl.key(LogicalKeyboardKey.arrowUp),
        down: InputControl.key(LogicalKeyboardKey.arrowDown),
        left: InputControl.key(LogicalKeyboardKey.arrowLeft),
        right: InputControl.key(LogicalKeyboardKey.arrowRight),
      ),
      StickBinding(
        x: InputControl.gamepad(GamepadAxis.leftX),
        y: InputControl.gamepad(GamepadAxis.leftY),
        // A pad reports Y positive downward; the engine convention is +Y
        // forward.
        invertY: true,
      ),
      CompositeVector2Binding(
        up: InputControl.gamepad(GamepadButton.dpadUp),
        down: InputControl.gamepad(GamepadButton.dpadDown),
        left: InputControl.gamepad(GamepadButton.dpadLeft),
        right: InputControl.gamepad(GamepadButton.dpadRight),
      ),
    ]),
    InputAction('look', InputActionKind.vector2, [
      const StickBinding(
        x: InputControl.mouseDeltaX,
        y: InputControl.mouseDeltaY,
        deadzone: 0,
        // Mouse Y grows downward; the engine's input convention is +Y up.
        invertY: true,
      ),
      StickBinding(
        x: InputControl.gamepad(GamepadAxis.rightX),
        y: InputControl.gamepad(GamepadAxis.rightY),
        invertY: true,
      ),
    ]),
    InputAction('jump', InputActionKind.button, [
      ButtonBinding(InputControl.key(LogicalKeyboardKey.space)),
      ButtonBinding(InputControl.gamepad(GamepadButton.south)),
    ]),
    InputAction('sprint', InputActionKind.button, [
      ButtonBinding(InputControl.key(LogicalKeyboardKey.shiftLeft)),
      ButtonBinding(InputControl.gamepad(GamepadButton.leftStick)),
    ]),
    // Q/E, the fly-camera convention. E is also `interact`: a project flying a
    // debug camera is not usually also interacting, and `actionsUsing` surfaces
    // the overlap for a rebinding screen that wants to resolve it.
    InputAction('elevate', InputActionKind.axis, [
      AxisBinding(
        positive: InputControl.key(LogicalKeyboardKey.keyE),
        negative: InputControl.key(LogicalKeyboardKey.keyQ),
      ),
      AxisBinding(
        positive: InputControl.gamepad(GamepadButton.rightShoulder),
        negative: InputControl.gamepad(GamepadButton.leftShoulder),
      ),
    ]),
    InputAction('interact', InputActionKind.button, [
      ButtonBinding(InputControl.key(LogicalKeyboardKey.keyE)),
      ButtonBinding(InputControl.gamepad(GamepadButton.west)),
    ]),
    InputAction('fire', InputActionKind.button, [
      const ButtonBinding(InputControl.mouseButton(1)),
      // A trigger is analog, so the binding says how far is far enough
      // rather than waiting for the hard stop at 1.
      ButtonBinding(
        InputControl.gamepad(GamepadButton.rightTrigger),
        threshold: 0.3,
      ),
    ]),
    InputAction('aim', InputActionKind.button, [
      const ButtonBinding(InputControl.mouseButton(2)),
      ButtonBinding(
        InputControl.gamepad(GamepadButton.leftTrigger),
        threshold: 0.3,
      ),
    ]),
    InputAction('pause', InputActionKind.button, [
      ButtonBinding(InputControl.key(LogicalKeyboardKey.escape)),
      ButtonBinding(InputControl.gamepad(GamepadButton.start)),
    ]),
  ]);

  final Map<String, InputAction> _actions = {};

  /// Every registered action, in insertion order.
  Iterable<InputAction> get actions => _actions.values;

  /// The action named [name], or null when it is not registered.
  InputAction? operator [](String name) => _actions[name];

  /// Registers [action], replacing any action of the same name.
  void add(InputAction action) {
    _actions[action.name] = action;
    notifyListeners();
  }

  /// Unregisters the action named [name]. Returns whether one was removed.
  bool remove(String name) {
    final removed = _actions.remove(name) != null;
    if (removed) notifyListeners();
    return removed;
  }

  /// Announces that a caller edited an [InputAction.bindings] list in place.
  void notifyRebound() => notifyListeners();

  /// Every action that reads [control], for showing conflicts in a rebinding
  /// UI before the change is committed.
  Iterable<InputAction> actionsUsing(InputControl control) =>
      _actions.values.where(
        (action) => action.bindings.any(
          (binding) => binding.controls.contains(control),
        ),
      );

  Map<String, Object?> toJson() => {
    for (final entry in _actions.entries) entry.key: entry.value.toJson(),
  };

  /// Rebuilds a map from [json], the inverse of [toJson]. Throws
  /// [FormatException] on a malformed action or binding.
  factory InputMap.fromJson(Map<String, Object?> json) => InputMap([
    for (final entry in json.entries)
      if (entry.value is Map<String, Object?>)
        InputAction.fromJson(entry.key, entry.value! as Map<String, Object?>)
      else
        throw FormatException('Action "${entry.key}" is not an object', json),
  ]);
}
