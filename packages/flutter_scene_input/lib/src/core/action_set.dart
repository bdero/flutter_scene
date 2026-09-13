import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/bindings.dart';
import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/processors.dart';

/// A named group of actions and their default bindings, pushed onto a
/// player's context stack as a unit (gameplay, vehicle, pause menu).
///
/// Each action maps named slots to one default binding. Slot names
/// (`keyboard`, `gamepad`) are what rebinding addresses, so they must stay
/// stable across app updates.
///
/// ```dart
/// final gameplay = ActionSet('gameplay', {
///   jump: {
///     'keyboard': ButtonBinding(KeyControl(0x0007002c)),
///     'gamepad': ButtonBinding(GamepadControl.south),
///   },
/// });
/// ```
///
/// Throws [ArgumentError] when a binding cannot produce its action's value
/// (a stick bound to a button, a stick feeding a delta action without
/// `PerSecond`), or when a derived action's source is not in the set.
/// {@category Actions}
final class ActionSet {
  /// A set called [name].
  ActionSet(
    this.name,
    Map<InputAction, Map<String, Binding>> bindings, {
    List<DerivedButtonAction> derived = const [],
    this.allowDuringTextEntry = false,
    this.conflictGroup,
  }) : bindings = Map.unmodifiable({
         for (final entry in bindings.entries)
           entry.key: Map<String, Binding>.unmodifiable(entry.value),
       }),
       derived = List.unmodifiable(derived) {
    for (final entry in this.bindings.entries) {
      if (entry.key is DerivedButtonAction) {
        throw ArgumentError.value(
          entry.key,
          'bindings',
          'Derived actions belong in `derived`, not `bindings`',
        );
      }
      for (final slot in entry.value.entries) {
        final problem = bindingProblem(entry.key, slot.value);
        if (problem != null) {
          throw ArgumentError(
            'Set "$name", action "${entry.key.name}", slot "${slot.key}": '
            '$problem',
          );
        }
      }
    }
    for (final action in this.derived) {
      if (!this.bindings.containsKey(action.source)) {
        throw ArgumentError(
          'Set "$name": derived action "${action.name}" reads '
          '"${action.source.name}", which is not bound in this set',
        );
      }
    }
  }

  /// The stable id of this set.
  final String name;

  /// Every bound action and its default binding per slot.
  final Map<InputAction, Map<String, Binding>> bindings;

  /// Actions recognized from other actions' timing.
  final List<DerivedButtonAction> derived;

  /// Whether this set stays live while a text field has focus. Sets for menus
  /// and text UIs opt in; gameplay sets do not.
  final bool allowDuringTextEntry;

  /// Sets sharing a group are checked against each other for binding
  /// conflicts, since they are live together.
  final String? conflictGroup;

  /// Every action this set can answer, bound and derived.
  Iterable<InputAction> get actions => [...bindings.keys, ...derived];

  @override
  String toString() => 'ActionSet($name)';
}

/// Why [binding] cannot feed [action], or null when it can.
String? bindingProblem(InputAction action, Binding binding) {
  if (binding is GatedBinding) {
    for (final modifier in binding.modifiers) {
      if (modifier.kind != ControlKind.digital &&
          modifier.kind != ControlKind.analog) {
        return 'gate modifier ${modifier.path} is not a button';
      }
    }
    return bindingProblem(action, binding.binding);
  }
  final hasRate = binding.processors.any((p) => p is PerSecond);
  String? requireKind(Control control, Set<ControlKind> kinds) =>
      kinds.contains(control.kind)
      ? null
      : '${control.path} is ${control.kind.name}, expected '
            '${kinds.map((k) => k.name).join(' or ')}';
  const levels = {ControlKind.digital, ControlKind.analog};
  switch (action) {
    case ButtonAction():
      return switch (binding) {
        ButtonBinding(:final control) => requireKind(control, levels),
        ChordBinding(:final trigger, :final modifiers) =>
          requireKind(trigger, levels) ??
              modifiers.map((m) => requireKind(m, levels)).nonNulls.firstOrNull,
        _ => '${binding.runtimeType} cannot drive a button',
      };
    case AxisAction():
      return switch (binding) {
        ButtonBinding(:final control) ||
        AxisBinding(:final control) => requireKind(control, levels),
        AxisPairBinding(:final negative, :final positive) =>
          requireKind(negative, levels) ?? requireKind(positive, levels),
        _ => '${binding.runtimeType} cannot drive an axis',
      };
    case VectorAction():
      return switch (binding) {
        StickBinding(:final control) => requireKind(control, {
          ControlKind.stick,
        }),
        DpadBinding() =>
          binding.controls
              .map((c) => requireKind(c, levels))
              .nonNulls
              .firstOrNull,
        _ => '${binding.runtimeType} cannot drive a vector',
      };
    case DeltaAction():
      return switch (binding) {
        DeltaBinding(:final control) =>
          hasRate
              ? 'PerSecond does not apply to a delta control'
              : requireKind(control, {ControlKind.delta}),
        StickBinding(:final control) =>
          hasRate
              ? requireKind(control, {ControlKind.stick})
              : 'a stick feeding a delta action needs PerSecond',
        DpadBinding() || AxisPairBinding() || AxisBinding() =>
          hasRate
              ? binding.controls
                    .map((c) => requireKind(c, levels))
                    .nonNulls
                    .firstOrNull
              : 'a level binding feeding a delta action needs PerSecond',
        _ => '${binding.runtimeType} cannot drive a delta',
      };
  }
}
