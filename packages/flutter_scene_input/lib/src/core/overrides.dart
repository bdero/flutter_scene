import 'dart:convert';

import 'package:meta/meta.dart';

import 'package:flutter_scene_input/src/core/action_set.dart';
import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/bindings.dart';
import 'package:flutter_scene_input/src/core/controls.dart';

/// Where a binding lives: a slot of an action in a set, optionally one part of
/// a composite.
/// {@category Rebinding}
final class BindingLocation {
  /// The location of [part] (or the whole slot) of [slot] for [action] in
  /// [set].
  const BindingLocation(this.set, this.action, this.slot, [this.part]);

  /// The set.
  final ActionSet set;

  /// The action.
  final InputAction action;

  /// The slot name.
  final String slot;

  /// The composite part, or null for the slot's single control.
  final String? part;

  @override
  bool operator ==(Object other) =>
      other is BindingLocation &&
      identical(other.set, set) &&
      other.action == action &&
      other.slot == slot &&
      other.part == part;

  @override
  int get hashCode => Object.hash(identityHashCode(set), action, slot, part);

  @override
  String toString() =>
      '${set.name}/${action.name}/$slot${part == null ? '' : '/$part'}';
}

/// One persisted binding override, addressed by names so it survives app
/// updates that keep those names.
/// {@category Rebinding}
final class OverrideRecord {
  /// An override of [slot] (and [part]) of [action] in [set] to [control], a
  /// control path, or null for an explicitly unbound slot.
  const OverrideRecord({
    required this.set,
    required this.action,
    required this.slot,
    this.part,
    required this.control,
  });

  /// The set name.
  final String set;

  /// The action name.
  final String action;

  /// The slot name.
  final String slot;

  /// The composite part, or null.
  final String? part;

  /// The control path, or null when unbound.
  final String? control;

  /// A copy with some fields replaced.
  OverrideRecord copyWith({
    String? set,
    String? action,
    String? slot,
    String? part,
    String? control,
    bool clearControl = false,
  }) => OverrideRecord(
    set: set ?? this.set,
    action: action ?? this.action,
    slot: slot ?? this.slot,
    part: part ?? this.part,
    control: clearControl ? null : control ?? this.control,
  );

  (String, String, String, String?) get _key => (set, action, slot, part);

  @override
  String toString() =>
      '$set/$action/$slot${part == null ? '' : '/$part'} -> ${control ?? 'unbound'}';
}

/// A player's rebinds and settings, layered over the authored action sets.
///
/// Authored bindings never change. Overrides are keyed by set, action, slot,
/// and part names, and persist as a small versioned JSON profile the game
/// stores however it likes.
///
/// ```dart
/// player.overrides
///   ..bind(jump, PhysicalKeyboardKey.keyF.control, slot: 'keyboard')
///   ..tune('mouseSensitivity', 1.4);
/// prefs.setString('controls', jsonEncode(player.overrides.toJson()));
/// ```
/// {@category Rebinding}
final class PlayerOverrides {
  /// Created by `PlayerInput`.
  @internal
  PlayerOverrides(this._onChanged, this._liveSets);

  /// The profile format id.
  static const String format = 'flutter_scene_input.profile';

  /// The current profile version.
  static const int version = 1;

  final void Function() _onChanged;
  final Iterable<ActionSet> Function() _liveSets;
  final Map<(String, String, String, String?), OverrideRecord> _records = {};
  final Map<String, double> _tunables = {};
  final Map<String, bool> _toggles = {};
  int _revision = 0;

  /// Increments on every change, for caches.
  int get revision => _revision;

  /// Every binding override, in insertion order.
  Iterable<OverrideRecord> get records => _records.values;

  /// Tunable values set by the player.
  Map<String, double> get tunables => Map.unmodifiable(_tunables);

  /// Rebinds [location] to [control].
  ///
  /// Throws [ArgumentError] when the part does not exist or the control cannot
  /// produce the action's value.
  void bindAt(BindingLocation location, Control control) {
    final binding = location.set.bindings[location.action]?[location.slot];
    if (binding == null) {
      throw ArgumentError('No slot "${location.slot}" at $location');
    }
    final rebound = rebindPart(binding, location.part, control);
    final problem = bindingProblem(location.action, rebound);
    if (problem != null) throw ArgumentError('$location: $problem');
    _put(_recordFor(location, control.path));
  }

  /// Rebinds [slot] (and [part]) of [action] to [control]. [set] defaults to
  /// the one live set binding [action].
  void bind(
    InputAction action,
    Control control, {
    required String slot,
    String? part,
    ActionSet? set,
  }) => bindAt(
    BindingLocation(set ?? _setFor(action), action, slot, part),
    control,
  );

  /// Unbinds [location], so it never actuates.
  void clearAt(BindingLocation location) {
    final binding = location.set.bindings[location.action]?[location.slot];
    if (binding == null) {
      throw ArgumentError('No slot "${location.slot}" at $location');
    }
    if (location.part != null) {
      rebindPart(binding, location.part, UnboundControl.instance);
    }
    _put(_recordFor(location, null));
  }

  /// Unbinds [slot] (and [part]) of [action].
  void clear(
    InputAction action, {
    required String slot,
    String? part,
    ActionSet? set,
  }) => clearAt(BindingLocation(set ?? _setFor(action), action, slot, part));

  /// Restores [action]'s authored bindings, every slot or just [slot].
  void reset(InputAction action, {String? slot, ActionSet? set}) {
    final setName = (set ?? _setFor(action)).name;
    final before = _records.length;
    _records.removeWhere(
      (key, record) =>
          record.set == setName &&
          record.action == action.name &&
          (slot == null || record.slot == slot),
    );
    if (_records.length != before) _changed();
  }

  /// Restores every authored binding, tunable, and recognizer setting.
  void resetAll() {
    if (_records.isEmpty && _tunables.isEmpty && _toggles.isEmpty) return;
    _records.clear();
    _tunables.clear();
    _toggles.clear();
    _changed();
  }

  /// Sets tunable [id], read by `Scale.tunable` and `Invert.tunable`.
  void tune(String id, double value) {
    if (_tunables[id] == value) return;
    _tunables[id] = value;
    _changed();
  }

  /// Returns tunable [id] to its binding default.
  void untune(String id) {
    if (_tunables.remove(id) != null) _changed();
  }

  /// The value of tunable [id], or [fallback] when unset.
  double tunable(String id, double fallback) => _tunables[id] ?? fallback;

  /// Sets whether [action] in [set] toggles instead of holding.
  void setToggle(HoldAction action, bool toggle, {ActionSet? set}) {
    final key = '${(set ?? _setFor(action)).name}/${action.name}';
    if (_toggles[key] == toggle) return;
    _toggles[key] = toggle;
    _changed();
  }

  /// Whether [action] in the set named [setName] toggles.
  bool toggleFor(String setName, HoldAction action) =>
      _toggles['$setName/${action.name}'] ?? action.toggle;

  /// The override at [location], or null when authored.
  OverrideRecord? recordAt(BindingLocation location) =>
      _records[_recordFor(location, null)._key];

  /// [location]'s authored binding with this player's overrides applied, or
  /// null when the whole slot is unbound.
  Binding? effectiveBinding(ActionSet set, InputAction action, String slot) {
    var binding = set.bindings[action]?[slot];
    if (binding == null) return null;
    for (final record in _records.values) {
      if (record.set != set.name ||
          record.action != action.name ||
          record.slot != slot) {
        continue;
      }
      final control = record.control == null
          ? UnboundControl.instance
          : Control.tryParse(record.control!);
      // A path this build cannot parse keeps the authored binding.
      if (control == null) continue;
      if (record.part == null && control is UnboundControl) return null;
      try {
        final rebound = rebindPart(binding!, record.part, control);
        if (bindingProblem(action, rebound) == null) binding = rebound;
      } on ArgumentError {
        // A part that no longer exists keeps the authored binding.
      }
    }
    return binding;
  }

  /// Records whose set, action, slot, or part match nothing in [sets], or
  /// whose control path this build cannot parse. They stay in the profile so
  /// a downgrade or a set not yet loaded does not lose them.
  List<OverrideRecord> unmatched(Iterable<ActionSet> sets) {
    final byName = {for (final set in sets) set.name: set};
    return [
      for (final record in _records.values)
        if (!_matches(record, byName)) record,
    ];
  }

  bool _matches(OverrideRecord record, Map<String, ActionSet> sets) {
    final set = sets[record.set];
    if (set == null) return false;
    final entry = set.bindings.entries
        .where((e) => e.key.name == record.action)
        .firstOrNull;
    final binding = entry?.value[record.slot];
    if (binding == null) return false;
    if (record.part != null && !binding.parts.containsKey(record.part)) {
      return false;
    }
    return record.control == null || Control.tryParse(record.control!) != null;
  }

  /// The profile as JSON, with records and keys in a stable order.
  Map<String, Object?> toJson({String name = 'default'}) {
    final records = _records.values.toList()
      ..sort((a, b) {
        for (final (x, y) in [
          (a.set, b.set),
          (a.action, b.action),
          (a.slot, b.slot),
          (a.part ?? '', b.part ?? ''),
        ]) {
          final order = x.compareTo(y);
          if (order != 0) return order;
        }
        return 0;
      });
    return {
      'format': format,
      'version': version,
      'name': name,
      'bindings': [
        for (final record in records)
          {
            'set': record.set,
            'action': record.action,
            'slot': record.slot,
            if (record.part != null) 'part': record.part,
            'control': record.control,
          },
      ],
      'tunables': {
        for (final id in _tunables.keys.toList()..sort()) id: _tunables[id],
      },
      'recognizers': {
        for (final key in _toggles.keys.toList()..sort())
          key: {'toggle': _toggles[key]},
      },
    };
  }

  /// The profile as indented JSON text.
  String toJsonString({String name = 'default'}) =>
      const JsonEncoder.withIndent('  ').convert(toJson(name: name));

  /// Replaces every override with those in [json].
  ///
  /// [renames] rewrites set and action ids (`'gameplay'` or
  /// `'gameplay/fire'` to a new name) for sets and actions renamed since the
  /// profile was saved. [migrate] then sees each record and returns it,
  /// rewritten, or null to drop it.
  ///
  /// Throws [FormatException] for a different format or a newer version.
  void loadJson(
    Map<String, Object?> json, {
    Map<String, String> renames = const {},
    OverrideRecord? Function(OverrideRecord record)? migrate,
  }) {
    if (json['format'] != format) {
      throw FormatException('Not a $format document', json);
    }
    final fileVersion = json['version'];
    if (fileVersion is! int || fileVersion > version) {
      throw FormatException(
        'Profile version $fileVersion is newer than $version',
        json,
      );
    }
    _records.clear();
    _tunables.clear();
    _toggles.clear();

    String rename(String set, String? action) {
      if (action == null) return renames[set] ?? set;
      final full = renames['$set/$action'];
      return full != null ? full.split('/').last : action;
    }

    final bindings = json['bindings'];
    if (bindings is List) {
      for (final raw in bindings.whereType<Map<Object?, Object?>>()) {
        final set = raw['set'];
        final action = raw['action'];
        final slot = raw['slot'];
        final part = raw['part'];
        final control = raw['control'];
        if (set is! String || action is! String || slot is! String) continue;
        if (part != null && part is! String) continue;
        if (control != null && control is! String) continue;
        final renamedSet =
            renames['$set/$action']?.split('/').first ?? rename(set, null);
        var record = OverrideRecord(
          set: renamedSet,
          action: rename(set, action),
          slot: slot,
          part: part as String?,
          control: control as String?,
        );
        if (migrate != null) {
          final migrated = migrate(record);
          if (migrated == null) continue;
          record = migrated;
        }
        _records[record._key] = record;
      }
    }
    final tunables = json['tunables'];
    if (tunables is Map) {
      for (final MapEntry(:key, :value) in tunables.entries) {
        if (key is! String) continue;
        if (value is num) _tunables[key] = value.toDouble();
        if (value is bool) _tunables[key] = value ? 1 : 0;
      }
    }
    final recognizers = json['recognizers'];
    if (recognizers is Map) {
      for (final MapEntry(:key, :value) in recognizers.entries) {
        if (key is! String || value is! Map) continue;
        final toggle = value['toggle'];
        if (toggle is bool) _toggles[renames[key] ?? key] = toggle;
      }
    }
    _changed();
  }

  /// Parses [source] with [loadJson].
  void loadJsonString(
    String source, {
    Map<String, String> renames = const {},
    OverrideRecord? Function(OverrideRecord record)? migrate,
  }) {
    final json = jsonDecode(source);
    if (json is! Map<String, Object?>) {
      throw const FormatException('A profile is a JSON object');
    }
    loadJson(json, renames: renames, migrate: migrate);
  }

  OverrideRecord _recordFor(BindingLocation location, String? control) =>
      OverrideRecord(
        set: location.set.name,
        action: location.action.name,
        slot: location.slot,
        part: location.part,
        control: control,
      );

  void _put(OverrideRecord record) {
    _records[record._key] = record;
    _changed();
  }

  void _changed() {
    _revision++;
    _onChanged();
  }

  ActionSet _setFor(InputAction action) {
    final matches = _liveSets()
        .where((set) => set.actions.contains(action))
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
