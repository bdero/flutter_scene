/// The command framework: schema-described commands as the only mutation
/// surface, plus the introspection that lets one declaration drive three
/// faces (execution, an MCP tool schema, and a parameter-editing UI).
///
/// A [CommandEntry] declares a [name], a [doc] string, a [paramSchema] (the
/// single source of truth), an [applicable] predicate, and an [execute]
/// function that turns validated params into a [Transaction]. A command never
/// applies its transaction, the session commits it through the history, so
/// every edit is undoable and identical whether it came from the UI, a
/// script, or an agent.
library;

import 'package:scene/scene.dart';

import 'change.dart';

/// The wire type of a command parameter, shared by the JSON schema and the UI.
enum ParamType {
  /// A string.
  string,

  /// A boolean.
  boolean,

  /// An integer.
  integer,

  /// A floating-point number.
  number,

  /// A 3-component vector `{x, y, z}`.
  vec3,

  /// A rotation quaternion `{x, y, z, w}`.
  quaternion,

  /// A linear RGBA color `{r, g, b, a}`.
  color,

  /// A node id token referencing a document node.
  nodeRef,

  /// A list of node id tokens.
  nodeRefList,

  /// A resource id token referencing a document resource.
  resourceRef,

  /// A source-path key for an external asset.
  assetRef,

  /// A nested property bag (a JSON object of typed values).
  propertyMap,

  /// A list of prefab overrides (`{target, path, value}` objects).
  overrideList,
}

/// One declared parameter of a command.
class ParamSpec {
  /// Declares a parameter.
  const ParamSpec({
    required this.name,
    required this.type,
    required this.label,
    this.description = '',
    this.required = true,
    this.defaultValue,
  });

  /// The key in the params map passed to [CommandEntry.execute].
  final String name;

  /// The wire type.
  final ParamType type;

  /// A short human-readable label for the inspector UI.
  final String label;

  /// A longer description (an MCP parameter description, or a UI tooltip).
  final String description;

  /// Whether the parameter must be present.
  final bool required;

  /// A default value the UI seeds the field with.
  final Object? defaultValue;
}

/// What a command can read while building its transaction, the document (for
/// current values and for minting fresh ids). Commands do not mutate here;
/// they return a [Transaction] the session commits.
class CommandContext {
  /// Creates a context over [document].
  CommandContext(this.document);

  /// The document being edited (read access plus [SceneDocument.newId]).
  final SceneDocument document;
}

/// Thrown when a command receives invalid or missing parameters.
class CommandException implements Exception {
  /// Creates an exception with [message].
  const CommandException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'CommandException: $message';
}

/// A registered command.
class CommandEntry {
  /// Declares a command.
  const CommandEntry({
    required this.name,
    required this.doc,
    required this.paramSchema,
    required this.execute,
    this.category = '',
    this.applicable = _always,
  });

  /// The stable command name (for example `setNodeTransform`).
  final String name;

  /// A brief description of what the command does.
  final String doc;

  /// A grouping label for menus and tool browsing (for example `Node`).
  final String category;

  /// The parameter declarations, the single source of truth from which the
  /// MCP schema and the UI descriptors are derived.
  final List<ParamSpec> paramSchema;

  /// Whether the command can run given [ctx] and [params] (Blender's poll()).
  final bool Function(CommandContext ctx, Map<String, Object?> params)
  applicable;

  /// Builds the [Transaction] for [params]. Throws [CommandException] on
  /// invalid params. Must not mutate the document.
  final Transaction Function(CommandContext ctx, Map<String, Object?> params)
  execute;

  static bool _always(CommandContext ctx, Map<String, Object?> params) => true;
}

/// The set of registered commands, keyed by name.
class CommandRegistry {
  final Map<String, CommandEntry> _entries = {};

  /// Registers [entry]. Throws [StateError] on a duplicate name.
  void register(CommandEntry entry) {
    if (_entries.containsKey(entry.name)) {
      throw StateError('Command already registered: ${entry.name}');
    }
    _entries[entry.name] = entry;
  }

  /// The command named [name], or null.
  CommandEntry? lookup(String name) => _entries[name];

  /// All registered commands, in registration order.
  Iterable<CommandEntry> get all => _entries.values;

  /// The registered command names.
  Iterable<String> get names => _entries.keys;
}

/// Returns an MCP-tool definition (JSON Schema draft-07 input schema) for
/// [entry], ready to `jsonEncode`. Derived entirely from [entry]'s
/// declaration.
Map<String, Object> mcpToolSchema(CommandEntry entry) {
  final properties = <String, Object>{};
  final required = <String>[];
  for (final param in entry.paramSchema) {
    properties[param.name] = _paramJsonSchema(param);
    if (param.required) required.add(param.name);
  }
  return {
    'name': entry.name,
    'description': entry.doc,
    'inputSchema': {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': false,
    },
  };
}

Map<String, Object> _paramJsonSchema(ParamSpec param) {
  Map<String, Object> object(Map<String, Object> props, List<String> req) => {
    'type': 'object',
    'properties': props,
    'required': req,
  };
  final number = {'type': 'number'};
  switch (param.type) {
    case ParamType.string:
      return {'type': 'string', 'description': param.description};
    case ParamType.boolean:
      return {'type': 'boolean', 'description': param.description};
    case ParamType.integer:
      return {'type': 'integer', 'description': param.description};
    case ParamType.number:
      return {'type': 'number', 'description': param.description};
    case ParamType.vec3:
      return {
        ...object({'x': number, 'y': number, 'z': number}, ['x', 'y', 'z']),
        'description': param.description,
      };
    case ParamType.quaternion:
      return {
        ...object(
          {'x': number, 'y': number, 'z': number, 'w': number},
          ['x', 'y', 'z', 'w'],
        ),
        'description': param.description,
      };
    case ParamType.color:
      return {
        ...object(
          {'r': number, 'g': number, 'b': number, 'a': number},
          ['r', 'g', 'b', 'a'],
        ),
        'description': param.description,
      };
    case ParamType.nodeRef:
      return {
        'type': 'string',
        'description': '${param.description} (node id token)'.trim(),
      };
    case ParamType.nodeRefList:
      return {
        'type': 'array',
        'description': '${param.description} (node id tokens)'.trim(),
        'items': {'type': 'string'},
      };
    case ParamType.resourceRef:
      return {
        'type': 'string',
        'description': '${param.description} (resource id token)'.trim(),
      };
    case ParamType.assetRef:
      return {
        'type': 'string',
        'description': '${param.description} (asset path key)'.trim(),
      };
    case ParamType.propertyMap:
      return {
        'type': 'object',
        'description': param.description,
        'additionalProperties': true,
      };
    case ParamType.overrideList:
      return {
        'type': 'array',
        'description': param.description,
        'items': object(
          {
            'target': {'type': 'string'},
            'path': {'type': 'string'},
            'value': {},
          },
          ['target', 'path', 'value'],
        ),
      };
  }
}

/// One field descriptor for the parameter-editing UI, derived from a
/// [ParamSpec]. The inspector builds a widget per descriptor by switching on
/// [type].
class UiFieldDescriptor {
  /// Creates a descriptor.
  const UiFieldDescriptor({
    required this.field,
    required this.type,
    required this.label,
    required this.description,
    required this.required,
    this.defaultValue,
  });

  /// The param key.
  final String field;

  /// The wire type the UI switches on.
  final ParamType type;

  /// The display label.
  final String label;

  /// Tooltip text.
  final String description;

  /// Whether the field is required.
  final bool required;

  /// A default value for the field.
  final Object? defaultValue;
}

/// The parameter-editing UI descriptors for [entry], derived from the same
/// [CommandEntry.paramSchema] declaration that drives [mcpToolSchema].
List<UiFieldDescriptor> uiDescriptors(CommandEntry entry) => [
  for (final param in entry.paramSchema)
    UiFieldDescriptor(
      field: param.name,
      type: param.type,
      label: param.label,
      description: param.description,
      required: param.required,
      defaultValue: param.defaultValue,
    ),
];
