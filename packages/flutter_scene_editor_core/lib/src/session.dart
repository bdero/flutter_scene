/// The editor session: the headless brain that ties a document, its history,
/// the command registry, the selection, and the read queries together.
///
/// Every document edit goes through [run] (a registered command, committed to
/// the history), so undo, redo, and agent parity hold by construction. Two
/// escape hatches handle the non-document-mutation cases (D1):
/// [applyTransient] for transient view state that is not history-worthy, and
/// [commitExternal] for a transaction produced out of band (an async import or
/// bake landing one atomic result on completion).
library;

import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';

import 'builtin_commands.dart';
import 'change.dart';
import 'command.dart';
import 'history.dart';
import 'query.dart';
import 'selection.dart';

/// A headless editing session over one [SceneDocument].
class EditorSession {
  /// Creates a session over [document]. A fresh [CommandRegistry] pre-loaded
  /// with the built-in commands is used unless [registry] is given.
  EditorSession(this.document, {CommandRegistry? registry})
    : registry = registry ?? _defaultRegistry(),
      _mutator = DocumentMutator(document),
      query = SceneQuery(document),
      selection = Selection() {
    history = EditHistory(_mutator);
    // Keep the selection valid as nodes come and go across edits and undo.
    history.addListener(_pruneSelection);
  }

  static CommandRegistry _defaultRegistry() {
    final registry = CommandRegistry();
    registerBuiltinCommands(registry);
    return registry;
  }

  /// Creates a session over a new empty document.
  factory EditorSession.empty() => EditorSession(SceneDocument());

  /// Loads a session from `.fscene` [source] text.
  factory EditorSession.fromFscene(String source) =>
      EditorSession(readFscene(source));

  /// The document being edited.
  final SceneDocument document;

  /// The command registry this session runs.
  final CommandRegistry registry;

  /// Read-only navigation and lookup over [document].
  final SceneQuery query;

  /// The transient selection (not document state, not undoable).
  final Selection selection;

  /// The undo/redo history.
  late final EditHistory history;

  final DocumentMutator _mutator;

  /// Runs the command named [name] with [params] and commits its transaction
  /// to the history. Returns the committed [Transaction] (empty when the
  /// command was a no-op). Throws [ArgumentError] for an unknown command and
  /// [CommandException] for invalid params.
  Transaction run(String name, [Map<String, Object?> params = const {}]) {
    final entry = registry.lookup(name);
    if (entry == null) throw ArgumentError('Unknown command: $name');
    final transaction = entry.execute(CommandContext(document), params);
    history.commit(transaction);
    return transaction;
  }

  /// Whether the command named [name] can run with [params] right now.
  bool canRun(String name, [Map<String, Object?> params = const {}]) {
    final entry = registry.lookup(name);
    return entry != null && entry.applicable(CommandContext(document), params);
  }

  /// Applies [transaction] without recording it on the history. For transient
  /// view state (camera moves, framing) that should not be undoable.
  void applyTransient(Transaction transaction) =>
      transaction.apply(_mutator);

  /// Commits an externally produced [transaction] to the history (the result
  /// of an async import or bake), so it is undoable like any other edit.
  void commitExternal(Transaction transaction) => history.commit(transaction);

  /// Undoes the last committed transaction. Returns false when there is
  /// nothing to undo.
  bool undo() => history.undo();

  /// Redoes the next undone transaction. Returns false when there is nothing
  /// to redo.
  bool redo() => history.redo();

  /// Serializes the current document to canonical `.fscene` JSON text.
  String toFscene() => writeFscene(document);

  void _pruneSelection() =>
      selection.retainWhere((id) => document.nodes.containsKey(id));
}
