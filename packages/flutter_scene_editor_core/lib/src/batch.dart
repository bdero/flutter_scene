/// Running many commands as one undo step.
///
/// An out-of-process caller pays a round trip per command, so a script that
/// touches a thousand nodes must be able to send them together, and a user
/// undoing that script's work expects one step back, not a thousand. A batch
/// runs its commands in order against a document that already carries the
/// earlier ones, and commits the whole run as a single [Transaction].
library;

import 'package:scene/scene.dart';

import 'change.dart';
import 'command.dart';

/// One command call in a batch.
class CommandCall {
  /// Names a command and its params.
  const CommandCall(this.name, [this.params = const {}]);

  /// Builds a call from `{'command': name, 'params': {...}}`.
  factory CommandCall.fromJson(Map<String, Object?> json) {
    final name = json['command'] ?? json['name'];
    if (name is! String || name.isEmpty) {
      throw const CommandException('A batch entry needs a "command" name');
    }
    final params = json['params'];
    if (params != null && params is! Map) {
      throw CommandException('$name needs "params" to be an object');
    }
    return CommandCall(
      name,
      (params as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  /// The registered command name.
  final String name;

  /// The params passed to it.
  final Map<String, Object?> params;
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
/// document as it was when the composer started.
class BatchComposer {
  /// Composes against [document], resolving names through [registry] and
  /// building each call's context with [contextFor].
  BatchComposer({
    required this.document,
    required this.registry,
    required CommandContext Function() contextFor,
  }) : _contextFor = contextFor,
       _mutator = DocumentMutator(document);

  /// The document the calls read and (while composing) write.
  final SceneDocument document;

  /// Where command names resolve.
  final CommandRegistry registry;

  final CommandContext Function() _contextFor;
  final DocumentMutator _mutator;
  final List<ChangeRecord> _records = [];

  /// How many records the calls have produced so far.
  int get recordCount => _records.length;

  /// Runs [call], applying its records so later calls see its effect.
  ///
  /// Throws [ArgumentError] for an unknown command and [CommandException]
  /// when the command refuses the call.
  void add(CommandCall call) {
    final entry = registry.lookup(call.name);
    if (entry == null) throw ArgumentError('Unknown command: ${call.name}');
    if (entry.kind == CommandKind.application) {
      throw CommandException(
        '${call.name} is asynchronous and cannot run inside a batch',
      );
    }
    final context = _contextFor();
    if (!entry.applicable(context, call.params)) {
      throw CommandException('${call.name} cannot run right now');
    }
    final transaction = entry.execute(context, call.params);
    // Applied now, not at the end, so the next call reads what this one did.
    transaction.apply(_mutator);
    _records.addAll(transaction.records);
  }

  /// Reverts everything applied so far, so a batch that fails part way
  /// leaves the document as it found it.
  void revert() {
    Transaction(name: 'revert', records: _records).revert(_mutator);
    _records.clear();
  }

  /// The accumulated records as one transaction named [name].
  ///
  /// The records are already applied to the document. Committing re-applies
  /// them, which writes the same values again, since every record carries the
  /// whole new value for its slot rather than a delta.
  Transaction build(String name) =>
      Transaction(name: name, records: List.of(_records));
}
