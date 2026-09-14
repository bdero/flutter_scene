import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/processors.dart';

/// How controls produce an action's value. Bindings form a small tree
/// (composites hold controls, gates hold bindings) and hold no state, so one
/// action set serves any number of players.
/// {@category Bindings}
sealed class Binding {
  const Binding({this.processors = const []});

  /// Transforms applied to this binding's value, in order.
  final List<Processor> processors;

  /// The controls whose values this binding reads, excluding gate modifiers.
  /// These are what a firing binding consumes for lower contexts.
  Iterable<Control> get controls;

  /// The named parts a rebind can address individually (`up`, `down`), or
  /// empty for a binding with a single control.
  Map<String, Control> get parts => const {};
}

/// A press. An analog control presses once it reaches [pressPoint] and
/// releases once it falls below [releasePoint], so a trigger resting near the
/// threshold does not chatter.
/// {@category Bindings}
final class ButtonBinding extends Binding {
  /// A press of [control].
  const ButtonBinding(
    this.control, {
    this.pressPoint = 0.5,
    this.releasePoint = 0.4,
    super.processors,
  });

  /// The control pressed.
  final Control control;

  /// The value at or above which the control presses.
  final double pressPoint;

  /// The value below which a pressed control releases.
  final double releasePoint;

  @override
  Iterable<Control> get controls => [control];
}

/// A scalar read from one digital or analog control.
/// {@category Bindings}
final class AxisBinding extends Binding {
  /// The value of [control].
  const AxisBinding(this.control, {super.processors});

  /// The control read.
  final Control control;

  @override
  Iterable<Control> get controls => [control];
}

/// A scalar from two controls, `positive - negative`.
/// {@category Bindings}
final class AxisPairBinding extends Binding {
  /// An axis from [negative] and [positive].
  const AxisPairBinding({
    required this.negative,
    required this.positive,
    super.processors,
  });

  /// Pushes toward -1.
  final Control negative;

  /// Pushes toward +1.
  final Control positive;

  @override
  Iterable<Control> get controls => [negative, positive];

  @override
  Map<String, Control> get parts => {
    'negative': negative,
    'positive': positive,
  };
}

/// A vector read from a stick control.
/// {@category Bindings}
final class StickBinding extends Binding {
  /// The vector of [control], a [ControlKind.stick] control.
  const StickBinding(this.control, {super.processors});

  /// The stick read.
  final GamepadControl control;

  @override
  Iterable<Control> get controls => [control.axisX!, control.axisY!];
}

/// How a [DpadBinding] combines its parts.
/// {@category Bindings}
enum DpadMode {
  /// Unit length on diagonals.
  normalized,

  /// Each axis -1, 0, or 1, so diagonals are longer than 1 before clamping.
  digital,

  /// The parts' raw values, for analog controls.
  analog,
}

/// A vector from four directional controls (WASD, arrows, a d-pad).
/// {@category Bindings}
final class DpadBinding extends Binding {
  /// A vector from four controls, +Y up.
  const DpadBinding({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    this.mode = DpadMode.normalized,
    super.processors,
  });

  /// Pushes toward +Y.
  final Control up;

  /// Pushes toward -Y.
  final Control down;

  /// Pushes toward -X.
  final Control left;

  /// Pushes toward +X.
  final Control right;

  /// How the parts combine.
  final DpadMode mode;

  @override
  Iterable<Control> get controls => [up, down, left, right];

  @override
  Map<String, Control> get parts => {
    'up': up,
    'down': down,
    'left': left,
    'right': right,
  };
}

/// A displacement read from a [ControlKind.delta] control.
/// {@category Bindings}
final class DeltaBinding extends Binding {
  /// The displacement of [control].
  const DeltaBinding(this.control, {super.processors});

  /// The delta control read.
  final Control control;

  @override
  Iterable<Control> get controls => [control];
}

/// A press of [trigger] made while every modifier is held.
///
/// The longest chord wins. While a chord's modifiers are held, bindings in
/// the same context that use its trigger with fewer modifiers read as idle,
/// so `S` and `Ctrl+S` can both be bound.
/// {@category Bindings}
final class ChordBinding extends Binding {
  /// [trigger] pressed while [modifiers] are held.
  const ChordBinding(
    this.modifiers,
    this.trigger, {
    this.pressPoint = 0.5,
    this.releasePoint = 0.4,
    super.processors,
  });

  /// Controls that must already be held.
  final List<Control> modifiers;

  /// The control whose press fires the chord.
  final Control trigger;

  /// See [ButtonBinding.pressPoint].
  final double pressPoint;

  /// See [ButtonBinding.releasePoint].
  final double releasePoint;

  @override
  Iterable<Control> get controls => [trigger];

  @override
  Map<String, Control> get parts => {
    for (var i = 0; i < modifiers.length; i++) 'modifier$i': modifiers[i],
    'trigger': trigger,
  };
}

/// Any [binding] that reads as idle unless every modifier is held. With a
/// mouse delta inside, this is drag-to-look.
/// {@category Bindings}
final class GatedBinding extends Binding {
  /// [binding] active only while [modifiers] are held.
  const GatedBinding(this.modifiers, this.binding, {super.processors});

  /// Controls that must be held.
  final List<Control> modifiers;

  /// The binding gated.
  final Binding binding;

  @override
  Iterable<Control> get controls => binding.controls;

  @override
  Map<String, Control> get parts => binding.parts;
}

/// [binding] with the control at [part] (or its single control when [part] is
/// null) replaced by [control], keeping processors and thresholds.
///
/// Throws [ArgumentError] when the binding has no such part.
// TODO(input-rebind): gate modifiers are not rebindable yet; add
// `gate0`-style parts to GatedBinding when a game needs them.
Binding rebindPart(Binding binding, String? part, Control control) {
  Never noPart() => throw ArgumentError.value(
    part,
    'part',
    '${binding.runtimeType} has ${binding.parts.isEmpty ? 'no parts' : 'parts ${binding.parts.keys.join(', ')}'}',
  );
  switch (binding) {
    case ButtonBinding(
      :final pressPoint,
      :final releasePoint,
      :final processors,
    ):
      if (part != null) noPart();
      return ButtonBinding(
        control,
        pressPoint: pressPoint,
        releasePoint: releasePoint,
        processors: processors,
      );
    case AxisBinding(:final processors):
      if (part != null) noPart();
      return AxisBinding(control, processors: processors);
    case DeltaBinding(:final processors):
      if (part != null) noPart();
      return DeltaBinding(control, processors: processors);
    case StickBinding(:final processors):
      if (part != null) noPart();
      if (control is! GamepadControl || control.axisX == null) {
        throw ArgumentError.value(control, 'control', 'Not a stick control');
      }
      return StickBinding(control, processors: processors);
    case AxisPairBinding(:final negative, :final positive, :final processors):
      return switch (part) {
        'negative' => AxisPairBinding(
          negative: control,
          positive: positive,
          processors: processors,
        ),
        'positive' => AxisPairBinding(
          negative: negative,
          positive: control,
          processors: processors,
        ),
        _ => noPart(),
      };
    case DpadBinding(
      :final up,
      :final down,
      :final left,
      :final right,
      :final mode,
      :final processors,
    ):
      if (!const {'up', 'down', 'left', 'right'}.contains(part)) noPart();
      return DpadBinding(
        up: part == 'up' ? control : up,
        down: part == 'down' ? control : down,
        left: part == 'left' ? control : left,
        right: part == 'right' ? control : right,
        mode: mode,
        processors: processors,
      );
    case ChordBinding(
      :final modifiers,
      :final trigger,
      :final pressPoint,
      :final releasePoint,
      :final processors,
    ):
      final index = part != null && part.startsWith('modifier')
          ? int.tryParse(part.substring('modifier'.length))
          : null;
      if (part != 'trigger' &&
          (index == null || index < 0 || index >= modifiers.length)) {
        noPart();
      }
      return ChordBinding(
        [
          for (var i = 0; i < modifiers.length; i++)
            i == index ? control : modifiers[i],
        ],
        part == 'trigger' ? control : trigger,
        pressPoint: pressPoint,
        releasePoint: releasePoint,
        processors: processors,
      );
    case GatedBinding(
      :final modifiers,
      binding: final inner,
      :final processors,
    ):
      return GatedBinding(
        modifiers,
        rebindPart(inner, part, control),
        processors: processors,
      );
  }
}

/// The control [binding] reads at [part], or its single control when [part]
/// is null.
Control? controlAt(Binding binding, String? part) {
  if (part != null) return binding.parts[part];
  return switch (binding) {
    ButtonBinding(:final control) ||
    AxisBinding(:final control) ||
    DeltaBinding(:final control) => control,
    StickBinding(:final control) => control,
    GatedBinding(binding: final inner) => controlAt(inner, null),
    _ => null,
  };
}
