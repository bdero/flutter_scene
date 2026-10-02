/// The read half of the protocol, declared the way commands are.
///
/// Commands are the only way to change the document; queries are the only way
/// to read it from outside. Both carry a name, a doc string, and a parameter
/// schema, so one declaration drives execution, the wire schema, and
/// discovery, and an out-of-process caller can learn the surface at runtime.
///
/// Queries read in bulk on purpose. A caller that pays a round trip per node
/// is unusable on a real scene, so a query answers for a whole subtree, a
/// whole resource pool, or a whole payload at once.
library;

import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:vector_math/vector_math.dart';

import 'command.dart';
import 'history.dart';
import 'query.dart';
import 'selection.dart';

/// Bytes a query returns beside its JSON body.
///
/// A transport that can frame binary sends these as frames; JSON-RPC encodes
/// them as base64. Either way the body refers to a blob by [id] rather than
/// carrying the bytes inline, so the shape does not change with the wire.
class QueryBlob {
  /// Creates a blob.
  const QueryBlob({
    required this.id,
    required this.bytes,
    this.mimeType = 'application/octet-stream',
  });

  /// The body's reference to these bytes.
  final String id;

  /// The bytes themselves.
  final Uint8List bytes;

  /// What the bytes are.
  final String mimeType;
}

/// What a query answers with.
class QueryResult {
  /// Creates a result carrying [body] and any [blobs] it refers to.
  const QueryResult(this.body, {this.blobs = const []});

  /// The JSON-shaped answer.
  final Map<String, Object?> body;

  /// Binary the body refers to by id.
  final List<QueryBlob> blobs;
}

/// What a query can ask the application, for facts that live in the
/// rendered scene rather than the document.
///
/// The read counterpart to the hosts commands act through. A headless session
/// has none, and a query answering without one says so rather than guessing.
///
/// Reads that wait on the renderer are not host methods. The app declares
/// them as [QueryKind.frame] queries and registers them itself.
abstract interface class QueryHost {
  /// World-space bounds of [id] and everything under it, or null when none
  /// of it draws.
  Aabb3? worldBounds(LocalId id);
}

/// What a query can read.
class QueryContext {
  /// Creates a context over [document] and the session state around it.
  const QueryContext({
    required this.document,
    required this.query,
    required this.selection,
    required this.history,
    required this.commands,
    required this.queries,
    this.componentSchema,
    this.host,
  });

  /// Resolves a component type to its schema, or null when the type is not
  /// registered, so a read can report what each carried property is.
  final ComponentSchema? Function(String type)? componentSchema;

  /// The application around the document, or null in a headless session.
  final QueryHost? host;

  /// The document being read.
  final SceneDocument document;

  /// Navigation and lookup over [document].
  final SceneQuery query;

  /// The session's selection.
  final Selection selection;

  /// The undo history, for queries that report what undo would do.
  final EditHistory history;

  /// The commands this session runs, for schema discovery.
  final CommandRegistry commands;

  /// The queries this session answers, for schema discovery.
  final QueryRegistry queries;
}

/// Thrown when a query has bad arguments or names something missing.
class QueryException implements Exception {
  /// Creates an exception with [message].
  const QueryException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'QueryException: $message';
}

/// What a query reads, which decides how it is answered.
enum QueryKind {
  /// Reads the document. Synchronous, so the answer is one consistent
  /// snapshot, and answerable headless.
  document,

  /// Reads the rendered scene. Asynchronous, since it may wait on a frame,
  /// and registered only by an app that renders.
  frame,
}

/// A registered read.
class QueryEntry {
  /// Declares a document query.
  const QueryEntry({
    required this.name,
    required this.doc,
    required this.read,
    this.paramSchema = const [],
    this.category = '',
  }) : kind = QueryKind.document,
       fetch = null;

  /// Declares a query over the rendered scene. Answer it with
  /// `EditorSession.request`; `ask` refuses it.
  const QueryEntry.frame({
    required this.name,
    required this.doc,
    required Future<QueryResult> Function(QueryContext, Map<String, Object?>)
    this.fetch,
    this.paramSchema = const [],
    this.category = '',
  }) : kind = QueryKind.frame,
       read = _refuseSync;

  static QueryResult _refuseSync(
    QueryContext ctx,
    Map<String, Object?> params,
  ) => throw const QueryException(
    'This query reads the rendered scene; call request instead of ask',
  );

  /// What this query reads.
  final QueryKind kind;

  /// The asynchronous body, set only for [QueryKind.frame].
  final Future<QueryResult> Function(QueryContext, Map<String, Object?>)? fetch;

  /// The stable query name (for example `nodeSubtree`).
  final String name;

  /// A brief description of what it answers.
  final String doc;

  /// A grouping label for discovery (for example `Scene`).
  final String category;

  /// The parameter declarations, the single source of truth the wire schema
  /// is derived from.
  final List<ParamSpec> paramSchema;

  /// Answers for [params]. Throws [QueryException] on invalid params. Must
  /// not mutate the document.
  final QueryResult Function(QueryContext ctx, Map<String, Object?> params)
  read;
}

/// The set of registered queries, keyed by name.
class QueryRegistry {
  final Map<String, QueryEntry> _entries = {};

  /// Registers [entry]. Throws [StateError] on a duplicate name.
  void register(QueryEntry entry) {
    if (_entries.containsKey(entry.name)) {
      throw StateError('Query already registered: ${entry.name}');
    }
    _entries[entry.name] = entry;
  }

  /// The query named [name], or null.
  QueryEntry? lookup(String name) => _entries[name];

  /// All registered queries, in registration order.
  Iterable<QueryEntry> get all => _entries.values;

  /// The registered query names.
  Iterable<String> get names => _entries.keys;
}

/// Returns the wire schema for [entry], the same shape [mcpToolSchema]
/// produces for a command.
Map<String, Object> querySchema(QueryEntry entry) => {
  'name': entry.name,
  'description': entry.doc,
  if (entry.category.isNotEmpty) 'category': entry.category,
  'kind': entry.kind.name,
  'inputSchema': paramJsonSchema(entry.paramSchema),
};
