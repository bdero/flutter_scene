import 'dart:async';

import 'package:flutter_scene_input/src/core/action_set.dart';
import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/bindings.dart';
import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/core/overrides.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';

/// Two binding locations reading the same control.
/// {@category Rebinding}
final class BindingConflict {
  /// [location] also reads [control].
  const BindingConflict(this.location, this.control);

  /// The other location.
  final BindingLocation location;

  /// The shared control.
  final Control control;

  @override
  String toString() => 'BindingConflict($location, ${control.path})';
}

/// How [RebindResult.apply] treats conflicting locations.
/// {@category Rebinding}
enum ConflictResolution {
  /// Unbind every conflicting location.
  replace,

  /// Give conflicting locations the control the rebound location had.
  swap,

  /// Leave conflicting locations bound to the same control.
  allowDuplicate,
}

/// How a listen ended.
/// {@category Rebinding}
enum RebindStatus {
  /// A control was chosen.
  bound,

  /// A cancel control was pressed or [RebindOperation.cancel] was called.
  cancelled,

  /// Nothing was pressed before the timeout.
  timedOut,
}

/// The outcome of [Rebinding.listenForBinding].
/// {@category Rebinding}
final class RebindResult {
  RebindResult._(
    this._player,
    this.status,
    this.location,
    this.control,
    this.conflicts,
  );

  final PlayerInput _player;

  /// How the listen ended.
  final RebindStatus status;

  /// The location being rebound.
  final BindingLocation location;

  /// The chosen control, when [status] is [RebindStatus.bound].
  final Control? control;

  /// Other locations already reading [control], within the location's set and
  /// sets sharing its `ActionSet.conflictGroup`.
  final List<BindingConflict> conflicts;

  /// Binds [control] to [location], resolving [conflicts] per [resolution].
  /// Does nothing unless [status] is [RebindStatus.bound].
  void apply({ConflictResolution resolution = ConflictResolution.replace}) {
    final chosen = control;
    if (status != RebindStatus.bound || chosen == null) return;
    final overrides = _player.overrides;
    final current = _player.effectiveBinding(
      location.set,
      location.action,
      location.slot,
    );
    final previous = current == null ? null : controlAt(current, location.part);
    overrides.bindAt(location, chosen);
    for (final conflict in conflicts) {
      switch (resolution) {
        case ConflictResolution.replace:
          overrides.clearAt(conflict.location);
        case ConflictResolution.swap:
          if (previous == null || previous is UnboundControl) {
            overrides.clearAt(conflict.location);
          } else {
            try {
              overrides.bindAt(conflict.location, previous);
            } on ArgumentError {
              overrides.clearAt(conflict.location);
            }
          }
        case ConflictResolution.allowDuplicate:
          break;
      }
    }
  }
}

/// A listen for the next control a player presses. Complete [result] or call
/// [cancel]; there is nothing to dispose.
/// {@category Rebinding}
final class RebindOperation {
  RebindOperation._(
    this._player,
    this.location,
    this._devices,
    this._exclude,
    this._cancelControls,
    this._settle,
    Duration timeout,
    this._conflictSets,
  ) {
    final binding = location.set.bindings[location.action]?[location.slot];
    if (binding == null) {
      throw ArgumentError('No slot "${location.slot}" at $location');
    }
    _expectsStick =
        binding is StickBinding ||
        (binding is GatedBinding && binding.binding is StickBinding);
    if (location.part != null && !binding.parts.containsKey(location.part)) {
      throw ArgumentError('No part "${location.part}" at $location');
    }
    _player
      ..suppressActions(true)
      ..addControlListener(_onControl);
    _timeout = Timer(timeout, () => _finish(RebindStatus.timedOut));
  }

  final PlayerInput _player;
  final Set<DeviceKind> _devices;
  final Set<Control> _exclude;
  final Set<Control> _cancelControls;
  final Duration _settle;
  final Iterable<ActionSet> _conflictSets;
  late final bool _expectsStick;
  final Completer<RebindResult> _completer = Completer();
  final Map<Control, double> _lastValues = {};
  final Set<Control> _risen = {};
  Timer? _timeout;
  Timer? _settleTimer;
  Control? _best;
  // The device control behind [_best]; for a stick, the axis that moved.
  Control? _bestRaw;
  double _bestMagnitude = 0;
  Control? _awaitingRelease;
  bool _suppressed = true;

  /// The location being rebound.
  final BindingLocation location;

  /// Completes when the listen ends.
  Future<RebindResult> get result => _completer.future;

  /// Ends the listen as [RebindStatus.cancelled]. Safe after completion.
  void cancel() => _finish(RebindStatus.cancelled);

  void _onControl(InputDevice device, Control control, double value) {
    // Seeded from the player, so a control held before the listen started is
    // not mistaken for a fresh press.
    final previous = _lastValues[control] ?? _player.levelOf(control);
    _lastValues[control] = value;
    final rising = previous.abs() < 0.5 && value.abs() >= 0.5;

    if (_completer.isCompleted) {
      // Hold actions suppressed until the chosen control is let go, so the
      // press that picked it does not also fire the action.
      if (control == _awaitingRelease && value.abs() < 0.5) _release();
      return;
    }
    if (rising) _risen.add(control);
    // Controls held from before the listen never rose, so they cannot win.
    if (value.abs() < 0.5 || !_risen.contains(control)) return;
    if (rising && _cancelControls.contains(control)) {
      _awaitingRelease = control;
      _finish(RebindStatus.cancelled);
      return;
    }
    if (!_devices.contains(control.device) || _exclude.contains(control)) {
      return;
    }
    Control candidate = control;
    if (_expectsStick) {
      final stick = _stickOf(control);
      if (stick == null) return;
      candidate = stick;
    } else if (control.kind != ControlKind.digital &&
        control.kind != ControlKind.analog) {
      return;
    }
    if (value.abs() <= _bestMagnitude) return;
    _best = candidate;
    _bestRaw = control;
    _bestMagnitude = value.abs();
    // Wait briefly for a stronger match, so brushing one stick axis on the
    // way to the other does not win.
    _settleTimer ??= Timer(_settle, () {
      _awaitingRelease = _bestRaw;
      _finish(RebindStatus.bound);
    });
  }

  static GamepadControl? _stickOf(Control control) => switch (control) {
    GamepadControl.leftStickX ||
    GamepadControl.leftStickY => GamepadControl.leftStick,
    GamepadControl.rightStickX ||
    GamepadControl.rightStickY => GamepadControl.rightStick,
    _ => null,
  };

  void _finish(RebindStatus status) {
    if (_completer.isCompleted) return;
    _timeout?.cancel();
    _settleTimer?.cancel();
    final chosen = status == RebindStatus.bound ? _best : null;
    final conflicts = chosen == null
        ? const <BindingConflict>[]
        : _player.conflictsFor(location, chosen, _conflictSets);
    _completer.complete(
      RebindResult._(_player, status, location, chosen, conflicts),
    );
    final awaiting = _awaitingRelease;
    if (awaiting == null || (_lastValues[awaiting] ?? 0).abs() < 0.5) {
      _release();
    }
  }

  void _release() {
    if (!_suppressed) return;
    _suppressed = false;
    _player
      ..removeControlListener(_onControl)
      ..suppressActions(false);
  }
}

/// Rebinding operations on a player.
/// {@category Rebinding}
extension Rebinding on PlayerInput {
  /// Listens for the next control pressed to rebind [slot] (and [part]) of
  /// [action] in [set] (default the one live set binding it).
  ///
  /// Every action on this player is suppressed while listening, and until the
  /// chosen control is released. Candidates come from [devices] (default the
  /// slot's current device family, keyboard and mouse together), skip
  /// [exclude], and must suit the slot (a stick slot takes a stick). The
  /// strongest candidate within [settle] of the first wins. [cancelControls]
  /// (default Escape and Start) end the listen, as does [timeout].
  ///
  /// Conflicts are checked against the location's set and [conflictSets]
  /// sharing its `ActionSet.conflictGroup` (default the live sets).
  RebindOperation listenForBinding(
    InputAction action, {
    required String slot,
    String? part,
    ActionSet? set,
    Set<DeviceKind>? devices,
    Set<Control> exclude = const {MouseControl.delta, MouseControl.scroll},
    Set<Control>? cancelControls,
    Duration timeout = const Duration(seconds: 10),
    Duration settle = const Duration(milliseconds: 150),
    Iterable<ActionSet>? conflictSets,
  }) {
    final resolvedSet = set ?? _setBinding(action);
    final location = BindingLocation(resolvedSet, action, slot, part);
    final binding = resolvedSet.bindings[action]?[slot];
    final current = binding == null
        ? null
        : controlAt(binding, part) ?? binding.controls.firstOrNull;
    final family = switch (current?.device) {
      DeviceKind.gamepad => {DeviceKind.gamepad},
      _ => {DeviceKind.keyboard, DeviceKind.mouse},
    };
    return RebindOperation._(
      this,
      location,
      devices ?? family,
      exclude,
      cancelControls ?? {const KeyControl(_escapeUsage), GamepadControl.start},
      settle,
      timeout,
      conflictSets ?? contexts.entries.map((entry) => entry.set).toList(),
    );
  }

  /// Other locations reading [control], in [location]'s set and any of [sets]
  /// sharing its conflict group.
  List<BindingConflict> conflictsFor(
    BindingLocation location,
    Control control,
    Iterable<ActionSet> sets,
  ) {
    final targetBinding =
        location.set.bindings[location.action]?[location.slot];
    final targetChord = targetBinding == null
        ? null
        : _chordSignature(targetBinding);
    final group = location.set.conflictGroup;
    final checked = {
      location.set,
      for (final set in sets)
        if (group != null && set.conflictGroup == group) set,
    };
    final conflicts = <BindingConflict>[];
    for (final set in checked) {
      for (final MapEntry(key: action, value: slots) in set.bindings.entries) {
        for (final slot in slots.keys) {
          final binding = effectiveBinding(set, action, slot);
          if (binding == null) continue;
          // A chord and a plain binding sharing a trigger coexist (the
          // longest chord wins), so only equal chords conflict.
          final chord = _chordSignature(binding);
          if (chord != targetChord && (chord != null || targetChord != null)) {
            continue;
          }
          for (final (part, bound) in _leaves(binding)) {
            final other = BindingLocation(set, action, slot, part);
            if (other == location || bound != control) continue;
            conflicts.add(BindingConflict(other, control));
          }
        }
      }
    }
    return conflicts;
  }

  /// Every pair of locations in [sets] reading the same control, within a set
  /// or across sets sharing a conflict group.
  List<(BindingLocation, BindingLocation)> findConflicts(
    Iterable<ActionSet> sets,
  ) {
    final found = <(BindingLocation, BindingLocation)>[];
    final seen = <BindingLocation>{};
    for (final set in sets) {
      for (final MapEntry(key: action, value: slots) in set.bindings.entries) {
        for (final slot in slots.keys) {
          final binding = effectiveBinding(set, action, slot);
          if (binding == null) continue;
          for (final (part, control) in _leaves(binding)) {
            final location = BindingLocation(set, action, slot, part);
            seen.add(location);
            for (final conflict in conflictsFor(location, control, sets)) {
              if (!seen.contains(conflict.location)) {
                found.add((location, conflict.location));
              }
            }
          }
        }
      }
    }
    return found;
  }

  ActionSet _setBinding(InputAction action) {
    final matches = contexts.entries
        .map((entry) => entry.set)
        .where((set) => set.bindings.containsKey(action))
        .toList();
    if (matches.length == 1) return matches.single;
    throw ArgumentError.value(
      action,
      'action',
      matches.isEmpty
          ? 'No live set binds this action; pass `set`'
          : 'Several live sets bind this action; pass `set`',
    );
  }
}

const int _escapeUsage = 0x00070029;

// The rebindable leaves of [binding]: each part, or the single control.
Iterable<(String?, Control)> _leaves(Binding binding) {
  final parts = binding.parts;
  if (parts.isNotEmpty) {
    return [
      for (final MapEntry(:key, :value) in parts.entries)
        if (value is! UnboundControl && !key.startsWith('modifier'))
          (key, value),
    ];
  }
  final control = controlAt(binding, null);
  return control == null || control is UnboundControl
      ? const []
      : [(null, control)];
}

// A chord's modifier set as a sorted path list, or null for a plain binding.
String? _chordSignature(Binding binding) => switch (binding) {
  ChordBinding(:final modifiers) =>
    (modifiers.map((m) => m.path).toList()..sort()).join('+'),
  GatedBinding(binding: final inner) => _chordSignature(inner),
  _ => null,
};
