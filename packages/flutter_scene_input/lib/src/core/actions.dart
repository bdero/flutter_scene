/// A named thing a game responds to (move, jump, look), independent of the
/// controls that produce it.
///
/// Actions are typed const objects. The [name] is the stable id used by
/// profiles and display, so renaming one needs a profile migration; the
/// object gives type-safe queries.
///
/// ```dart
/// const move = VectorAction('move');
/// const jump = ButtonAction('jump');
/// ```
///
/// Two actions are equal when their type and [name] match.
/// {@category Actions}
sealed class InputAction {
  const InputAction(this.name);

  /// The stable id of this action within its set.
  final String name;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is InputAction &&
      other.name == name;

  @override
  int get hashCode => Object.hash(runtimeType, name);

  @override
  String toString() => '$runtimeType($name)';
}

/// A pressed state with edges and counters. Read with `PlayerInput.button`.
/// {@category Actions}
base class ButtonAction extends InputAction {
  /// A button action called [name].
  const ButtonAction(super.name);
}

/// The range an [AxisAction] reports.
/// {@category Actions}
enum AxisRange {
  /// `-1..1`.
  bipolar,

  /// `0..1`, for throttles and triggers.
  unipolar,
}

/// A scalar. Read with `PlayerInput.axis`.
/// {@category Actions}
final class AxisAction extends InputAction {
  /// An axis action called [name] reporting [range].
  const AxisAction(super.name, {this.range = AxisRange.bipolar});

  /// The range values are clamped to.
  final AxisRange range;
}

/// A 2D direction with magnitude up to 1, +Y forward or up. Read with
/// `PlayerInput.vector`.
/// {@category Actions}
final class VectorAction extends InputAction {
  /// A vector action called [name].
  const VectorAction(super.name);
}

/// An unbounded 2D displacement accumulated over each read window, +Y up.
/// Read with `PlayerInput.delta`.
///
/// Relative movement (mouse look, scrolling) never shares a clamping path
/// with sticks, so a flick and a nudge keep their difference. A stick or key
/// bound to a delta action carries a `PerSecond` processor, which turns its
/// level into a displacement over the window's elapsed time, so mouse and
/// right-stick look share one action.
/// {@category Actions}
final class DeltaAction extends InputAction {
  /// A delta action called [name].
  const DeltaAction(super.name);
}

/// A button action derived from another button action's timing rather than
/// bound to controls. Listed in `ActionSet.derived`.
/// {@category Actions}
sealed class DerivedButtonAction extends ButtonAction {
  const DerivedButtonAction(super.name, {required this.source});

  /// The action whose presses this one recognizes.
  final ButtonAction source;
}

/// Pressed once [source] has been held for [duration] seconds.
///
/// With [toggle], each completed hold flips the pressed state instead, the
/// hold-to-toggle accessibility setting a profile can turn on.
/// {@category Actions}
final class HoldAction extends DerivedButtonAction {
  /// Recognizes a hold of [source] lasting [duration] seconds.
  const HoldAction(
    super.name, {
    required super.source,
    required this.duration,
    this.toggle = false,
  });

  /// Seconds [source] must stay held.
  final double duration;

  /// Whether each completed hold flips the pressed state.
  final bool toggle;
}

/// Fires (a press and release in the same instant) when [source] is released
/// within [maxDuration] seconds of being pressed.
/// {@category Actions}
final class TapAction extends DerivedButtonAction {
  /// Recognizes a tap of [source] no longer than [maxDuration] seconds.
  const TapAction(super.name, {required super.source, this.maxDuration = 0.2});

  /// The longest press, in seconds, that still counts as a tap.
  final double maxDuration;
}

/// Fires when [source] is pressed [count] times, each within [window]
/// seconds of the previous press.
/// {@category Actions}
final class MultiTapAction extends DerivedButtonAction {
  /// Recognizes [count] presses of [source] spaced at most [window] apart.
  const MultiTapAction(
    super.name, {
    required super.source,
    this.count = 2,
    this.window = 0.3,
  });

  /// Presses needed.
  final int count;

  /// The longest gap, in seconds, between consecutive presses.
  final double window;
}
