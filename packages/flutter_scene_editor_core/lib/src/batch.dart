/// Running many commands as one undo step.
///
/// An out-of-process caller pays a round trip per command, so a script that
/// touches a thousand nodes must be able to send them together, and a user
/// undoing that script's work expects one step back, not a thousand. A batch
/// runs its commands in order against a document that already carries the
/// earlier ones, and commits the whole run as a single [Transaction].
library;

import 'package:scene/scene.dart' hide NodeChange;

import 'change.dart';
import 'command.dart';
import 'selection.dart';

/// One command call in a batch.
class CommandCall {
  /// Names a command, its params, and optionally an [alias] later calls can
  /// refer to what it creates by.
  const CommandCall(this.name, [this.params = const {}, this.alias]);

  /// Builds a call from `{'command': name, 'params': {...}, 'as': alias}`.
  factory CommandCall.fromJson(Map<String, Object?> json) {
    final name = json['command'] ?? json['name'];
    if (name is! String || name.isEmpty) {
      throw const CommandException('A batch entry needs a "command" name');
    }
    final params = json['params'];
    if (params != null && params is! Map) {
      throw CommandException('$name needs "params" to be an object');
    }
    final alias = json['as'];
    if (alias != null && (alias is! String || alias.isEmpty)) {
      throw CommandException('$name needs "as" to be a non-empty name');
    }
    return CommandCall(
      name,
      (params as Map?)?.cast<String, Object?>() ?? const {},
      alias as String?,
    );
  }

  /// The registered command name.
  final String name;

  /// The params passed to it.
  final Map<String, Object?> params;

  /// A name later calls reference as `\$alias` wherever an id goes, bound to
  /// the first entity this call creates. Null when nothing refers to it.
  final String? alias;
}

/// Thrown when one call in a batch fails, naming where it stopped so a caller
/// can fix that call rather than bisecting the run.
class BatchException implements Exception {
  /// Creates a failure for the call at [index], named [command].
  const BatchException({
    required this.index,
    required this.command,
    required this.cause,
  });

  /// The failing call's position in the batch.
  final int index;

  /// The failing call's command name.
  final String command;

  /// What the command threw.
  final Object cause;

  /// What went wrong, with the position that produced it.
  String get message => 'Batch failed at $index ($command), $cause';

  @override
  String toString() => 'BatchException: $message';
}

/// Builds one [Transaction] out of many command calls.
///
/// Each call is executed against the document as the calls before it left it,
/// so a batch can create a node and then address it. The records accumulate;
/// nothing reaches the history until [build]. A call that throws leaves the
/// document and the selection as they were when the composer started.
class BatchComposer {
  /// Composes against [document], resolving names through [registry] and
  /// building each call's context with [contextFor]. [selection] is snapshot
  /// so a failed run can put it back.
  BatchComposer({
    required this.document,
    required this.registry,
    required CommandContext Function() contextFor,
    Selection? selection,
  }) : _contextFor = contextFor,
       _selection = selection,
       _selectionBefore = selection?.ids.toList(),
       _mutator = DocumentMutator(document);

  /// The document the calls read and (while composing) write.
  final SceneDocument document;

  /// Where command names resolve.
  final CommandRegistry registry;

  final CommandContext Function() _contextFor;
  final Selection? _selection;
  final List<LocalId>? _selectionBefore;
  final DocumentMutator _mutator;
  final List<ChangeRecord> _records = [];
  final Map<String, LocalId> _bindings = {};

  /// How many records the calls have produced so far.
  int get recordCount => _records.length;

  /// What each alias bound to, for a caller that wants the ids back.
  Map<String, LocalId> get bindings => Map.unmodifiable(_bindings);

  /// The kinds a batch accepts.
  ///
  /// Document and selection edits are the two a failed run can undo, the
  /// first through its records and the second through a snapshot. A view, ui,
  /// or application command reaches a host that has no way to put back what
  /// it did, so allowing one would break the promise that a failed batch
  /// keeps nothing.
  static const Set<CommandKind> acceptedKinds = {
    CommandKind.document,
    CommandKind.selection,
  };

  /// Runs [call], applying its records so later calls see its effect.
  ///
  /// Throws [ArgumentError] for an unknown command and [CommandException]
  /// when the command refuses the call or its kind cannot ride in a batch.
  void add(CommandCall call) {
    final entry = registry.lookup(call.name);
    if (entry == null) throw ArgumentError('Unknown command: ${call.name}');
    if (!acceptedKinds.contains(entry.kind)) {
      throw CommandException(
        'A batch takes only document and selection commands, and '
        '${call.name} is ${entry.kind.name}. Nothing else can be put back '
        'when a later call fails.',
      );
    }
    final params = _resolve(call.name, call.params);
    final context = _contextFor();
    if (!entry.applicable(context, params)) {
      throw CommandException('${call.name} cannot run right now');
    }
    final transaction = entry.execute(context, params);
    // Applied now, not at the end, so the next call reads what this one did.
    transaction.apply(_mutator);
    _records.addAll(transaction.records);
    if (call.alias != null) _bind(call, transaction);
  }

  /// Binds [call]'s alias to the first entity its transaction created, so a
  /// later call can name what this one made before any id has been reported.
  void _bind(CommandCall call, Transaction transaction) {
    for (final record in transaction.records) {
      final created = switch ((record.slot, record.oldValue, record.newValue)) {
        (ChangeSlot.poolNode, NodeChange(value: null), NodeChange(value: _?)) ||
        (
          ChangeSlot.poolResource,
          ResourceChange(value: null),
          ResourceChange(value: _?),
        ) ||
        (
          ChangeSlot.poolPayload,
          PayloadChange(value: null),
          PayloadChange(value: _?),
        ) ||
        (ChangeSlot.poolSkin, SkinChange(value: null), SkinChange(value: _?)) ||
        (
          ChangeSlot.poolAnimation,
          AnimationChange(value: null),
          AnimationChange(value: _?),
        ) => true,
        _ => false,
      };
      if (!created) continue;
      _bindings[call.alias!] = record.targetId;
      return;
    }
    throw CommandException(
      '${call.name} created nothing, so "${call.alias}" has nothing to name',
    );
  }

  /// Replaces every `\$alias` in [params] with the id it is bound to.
  Object? _resolveValue(String command, Object? value) {
    if (value is String) {
      if (!value.startsWith(r'$') || value.length < 2) return value;
      final alias = value.substring(1);
      final bound = _bindings[alias];
      if (bound == null) {
        throw CommandException(
          '$command refers to "$value", which no earlier call in this batch '
          'named with "as"',
        );
      }
      return bound.toToken();
    }
    if (value is List) {
      return [for (final item in value) _resolveValue(command, item)];
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key: _resolveValue(command, entry.value),
      };
    }
    return value;
  }

  Map<String, Object?> _resolve(String command, Map<String, Object?> params) =>
      _bindings.isEmpty && !_mentionsAlias(params)
      ? params
      : (_resolveValue(command, params)! as Map).cast<String, Object?>();

  static bool _mentionsAlias(Object? value) => switch (value) {
    String s => s.startsWith(r'$') && s.length > 1,
    List<Object?> list => list.any(_mentionsAlias),
    Map<Object?, Object?> map => map.values.any(_mentionsAlias),
    _ => false,
  };

  /// Reverts everything applied so far and puts the selection back, so a
  /// batch that fails part way leaves the session as it found it.
  void revert() {
    Transaction(name: 'revert', records: _records).revert(_mutator);
    _records.clear();
    _bindings.clear();
    final before = _selectionBefore;
    if (before != null) _selection?.set(before);
  }

  /// The accumulated records as one transaction named [name].
  ///
  /// The records are already applied to the document. Committing re-applies
  /// them, which writes the same values again, since every record carries the
  /// whole new value for its slot rather than a delta.
  Transaction build(String name) =>
      Transaction(name: name, records: List.of(_records));
}
