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

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

import 'batch.dart';
import 'builtin_commands.dart';
import 'builtin_queries.dart';
import 'change.dart';
import 'command.dart';
import 'events.dart';
import 'history.dart';
import 'queries.dart';
import 'query.dart';
import 'editor_host.dart';
import 'selection.dart';
import 'view_host.dart';

/// A headless editing session over one [SceneDocument].
class EditorSession {
  /// Creates a session over [document]. A fresh [CommandRegistry] pre-loaded
  /// with the built-in commands is used unless [registry] is given.
  EditorSession(
    this.document, {
    CommandRegistry? registry,
    QueryRegistry? queries,
  }) : registry = registry ?? _defaultRegistry(),
       queries = queries ?? _defaultQueries(),
       _mutator = DocumentMutator(document),
       query = SceneQuery(document),
       selection = Selection() {
    history = EditHistory(_mutator, selection: selection);
    // Keep the selection valid as nodes come and go across edits and undo.
    history.addListener(_pruneSelection);
    // Undo and redo move the document away from what was saved, too.
    history.addListener(markDirty);
    history.addListener(_announceHistory);
    selection.addListener(_announceSelection);
  }

  static CommandRegistry _defaultRegistry() {
    final registry = CommandRegistry();
    registerBuiltinCommands(registry);
    return registry;
  }

  static QueryRegistry _defaultQueries() {
    final registry = QueryRegistry();
    registerBuiltinQueries(registry);
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

  /// The query registry this session answers.
  final QueryRegistry queries;

  /// Resolves component types to schemas for property coercion, injected by
  /// the host (the editor wires its component registry here). Null falls
  /// back to shape-guessed coercion.
  ComponentSchema? Function(String type)? componentSchemaLookup;

  /// Read-only navigation and lookup over [document].
  final SceneQuery query;

  /// The transient selection (not document state, not undoable).
  final Selection selection;

  /// The viewport view commands act on, set by the host that renders one.
  /// Null leaves every view command inapplicable.
  ViewHost? viewHost;

  /// The application around the document, set by the editor. Null leaves
  /// every application command inapplicable.
  EditorHost? host;

  /// Whether anything has changed since the document was last saved.
  ///
  /// Selection and the viewport camera both save with the document, so both
  /// mark it dirty even though the camera is never an undo step.
  bool get isDirty => _dirty;
  bool _dirty = false;

  /// Marks the document changed. The host calls this for state that does not
  /// go through a command, such as an orbit drag.
  void markDirty() {
    if (_dirty) return;
    _dirty = true;
    _notifyDirty();
    events.emit(
      const EditorEvent(EditorEventType.dirtyChanged, {'dirty': true}),
    );
  }

  /// Marks the document saved.
  void markSaved() {
    if (!_dirty) return;
    _dirty = false;
    _notifyDirty();
    events.emit(
      const EditorEvent(EditorEventType.dirtyChanged, {'dirty': false}),
    );
  }

  final List<void Function()> _dirtyListeners = [];

  /// Registers [listener], called when [isDirty] changes.
  void addDirtyListener(void Function() listener) =>
      _dirtyListeners.add(listener);

  /// Removes a previously registered [listener].
  void removeDirtyListener(void Function() listener) =>
      _dirtyListeners.remove(listener);

  void _notifyDirty() {
    for (final listener in List.of(_dirtyListeners)) {
      listener();
    }
  }

  /// What this session announces to subscribed clients.
  ///
  /// Settable, because a subscription belongs to the client that made it, not
  /// to the document it was made against. A host that swaps sessions when a
  /// document opens installs the same bus on each one, so a client keeps
  /// hearing across the open rather than losing its subscription to exactly
  /// the event that announces it.
  EventBus events = EventBus();

  /// Announces that a document was opened into this session. The host calls
  /// it, since only the host knows an open happened.
  void announceOpened({String? path}) => events.emit(
    EditorEvent(EditorEventType.documentOpened, {
      if (path != null) 'path': path,
    }),
  );

  /// Announces a save, and marks the document clean, since a save is what
  /// makes it clean. The host calls it for the same reason.
  void announceSaved({String? path}) {
    markSaved();
    events.emit(
      EditorEvent(EditorEventType.documentSaved, {
        if (path != null) 'path': path,
      }),
    );
  }

  void _announceSelection() => events.emit(
    EditorEvent(EditorEventType.selectionChanged, {
      'nodeIds': [for (final id in selection.ids) id.toToken()],
    }),
  );

  void _announceHistory() {
    events.emit(
      EditorEvent(EditorEventType.historyChanged, {
        'canUndo': history.canUndo,
        'canRedo': history.canRedo,
        'undoLabel': history.undoLabel,
        'redoLabel': history.redoLabel,
      }),
    );
    events.emit(const EditorEvent(EditorEventType.documentChanged));
  }

  /// The undo/redo history.
  late final EditHistory history;

  final DocumentMutator _mutator;

  /// Predicate deciding which selected ids survive an edit. Defaults to "the id
  /// is a node in the document". The editor widens this to also keep prefab
  /// content ids (which live only in the composed document), so selecting a
  /// node inside a prefab is not lost on the next edit.
  bool Function(LocalId id)? selectionValidId;

  /// Runs the command named [name] with [params] and commits its transaction
  /// to the history. Returns the committed [Transaction] (empty when the
  /// command was a no-op). Throws [ArgumentError] for an unknown command and
  /// [CommandException] for invalid params.
  Transaction run(String name, [Map<String, Object?> params = const {}]) {
    final entry = registry.lookup(name);
    if (entry == null) throw ArgumentError('Unknown command: $name');
    final context = _context();
    if (!entry.applicable(context, params)) {
      throw CommandException('$name cannot run right now');
    }
    // Captured before the command runs, since a selection command changes the
    // selection as it executes.
    final before = selection.ids.toList();
    final transaction = entry.execute(context, params);
    transaction.selectionBefore = before;
    history.commit(transaction);
    if (!transaction.isEmpty || entry.kind == CommandKind.view) markDirty();
    return transaction;
  }

  CommandContext _context() => CommandContext(
    document,
    componentSchema: componentSchemaLookup,
    selection: selection,
    view: viewHost,
    host: host,
  );

  /// Runs [calls] in order and commits them as one history step named [name],
  /// so a script that touches a thousand nodes is one undo for the user.
  ///
  /// Each call sees what the calls before it did, and a call that names
  /// itself with an alias can be referenced by the calls after it, so a batch
  /// can create a payload and then build geometry over it. Nothing is
  /// committed unless every call succeeds; the first failure reverts the run,
  /// restores the selection, and throws a [BatchException] naming which call
  /// stopped it. [bindings], when given, receives what each alias named.
  ///
  /// Only document and selection commands ride in a batch. See
  /// [BatchComposer.acceptedKinds].
  Transaction runAll(
    Iterable<CommandCall> calls, {
    String name = 'Batch edit',
    Map<String, LocalId>? bindings,
  }) {
    final before = selection.ids.toList();
    final composer = BatchComposer(
      document: document,
      registry: registry,
      contextFor: _context,
      selection: selection,
    );
    var index = 0;
    for (final call in calls) {
      try {
        composer.add(call);
      } on Object catch (error) {
        composer.revert();
        throw BatchException(index: index, command: call.name, cause: error);
      }
      index++;
    }
    final transaction = composer.build(name);
    transaction.selectionBefore = before;
    bindings?.addAll(composer.bindings);
    history.commit(transaction);
    if (!transaction.isEmpty) markDirty();
    return transaction;
  }

  /// Answers the query named [name] with [params].
  ///
  /// Throws [ArgumentError] for an unknown query and [QueryException] for
  /// invalid params.
  QueryResult ask(String name, [Map<String, Object?> params = const {}]) {
    final entry = queries.lookup(name);
    if (entry == null) throw ArgumentError('Unknown query: $name');
    return entry.read(_queryContext(), params);
  }

  QueryContext _queryContext() => QueryContext(
    document: document,
    query: query,
    selection: selection,
    history: history,
    commands: registry,
    queries: queries,
  );

  /// Runs the command named [name], whatever its kind.
  ///
  /// Document, selection, and view commands run synchronously through [run]
  /// and return their transaction; an application command awaits its work and
  /// returns null.
  Future<Transaction?> invoke(
    String name, [
    Map<String, Object?> params = const {},
  ]) async {
    final entry = registry.lookup(name);
    if (entry == null) throw ArgumentError('Unknown command: $name');
    if (entry.kind != CommandKind.application) return run(name, params);
    final context = _context();
    if (!entry.applicable(context, params)) {
      throw CommandException('$name cannot run right now');
    }
    try {
      await entry.perform!(context, params);
    } on CommandException {
      rethrow;
    } on Object catch (error) {
      // The host throws its own failures (a missing path, a closed project);
      // agents and scripts should see one kind of error from a command.
      throw CommandException('$name failed, $error');
    }
    return null;
  }

  /// Whether the command named [name] can run with [params] right now.
  bool canRun(String name, [Map<String, Object?> params = const {}]) {
    final entry = registry.lookup(name);
    return entry != null && entry.applicable(_context(), params);
  }

  /// Applies [transaction] without recording it on the history. For transient
  /// view state (camera moves, framing) that should not be undoable.
  void applyTransient(Transaction transaction) => transaction.apply(_mutator);

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

  void _pruneSelection() {
    final valid = selectionValidId ?? (id) => document.nodes.containsKey(id);
    selection.retainWhere(valid);
  }
}
