/// The tiered MCP tool surface over an [EditorSession].
///
/// Agents do not see a flat dump of every command (the wrong granularity, per
/// the agent-tool-design research). They see a small curated bootstrap set,
/// perception tools to read the scene, a `search_commands` discovery tool, and
/// a `run_command` gateway into the full command registry. Nodes are addressed
/// by human-readable slash paths first, with stable id tokens as a fallback.
///
/// This layer is transport-free and GPU-free, so it is fully testable with
/// `dart test`. A dart_mcp server wraps [bootstrapTools] and [dispatch] to
/// speak the protocol; a running editor adds a viewport-screenshot tool.
library;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:vector_math/vector_math.dart';

/// One MCP tool definition, ready to hand to a protocol server.
class ToolDefinition {
  /// Creates a tool definition.
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  /// The tool name.
  final String name;

  /// A one-line description for the agent.
  final String description;

  /// The JSON Schema (draft-07) for the tool's arguments.
  final Map<String, Object?> inputSchema;
}

/// Thrown when a tool call has bad arguments or targets something missing.
class ToolError implements Exception {
  /// Creates a tool error with [message].
  const ToolError(this.message);

  /// What went wrong (surfaced to the agent).
  final String message;

  @override
  String toString() => 'ToolError: $message';
}

/// Builds the tiered tool surface for [session] and dispatches tool calls.
class EditorToolSurface {
  /// Creates a surface over [session].
  EditorToolSurface(this.session);

  /// The editing session this surface reads and drives.
  final EditorSession session;

  SceneQuery get _query => session.query;

  /// The curated tools an agent is offered up front. The full command set is
  /// reached through `search_commands` plus `run_command`, not listed here.
  List<ToolDefinition> bootstrapTools() => const [
    ToolDefinition(
      name: 'describe_scene',
      description:
          'Return the scene-graph tree (node ids, slash paths, names, '
          'component types) for an overview of the whole scene.',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
    ToolDefinition(
      name: 'get_node',
      description:
          'Return full detail for one node (transform, components and their '
          'properties, children) by slash path or id token.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'string',
            'description': 'A node slash path (Root/Cube) or id token.',
          },
        },
        'required': ['ref'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'get_selection',
      description: 'Return the currently selected nodes and the primary one.',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
    ToolDefinition(
      name: 'select_node',
      description: 'Select one node by slash path or id token.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ref': {'type': 'string'},
        },
        'required': ['ref'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'search_commands',
      description:
          'Search the editor command registry by name, category, or words in '
          'the description. Returns each match with its argument schema, ready '
          'to pass to run_command.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Substring to match, or empty for all commands.',
          },
        },
      },
    ),
    ToolDefinition(
      name: 'run_command',
      description:
          'Run any editor command by name with its arguments. Every command is '
          'a single undoable edit, identical to the same action in the UI. Use '
          'search_commands to discover names and argument schemas.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'command': {'type': 'string'},
          'params': {'type': 'object'},
        },
        'required': ['command'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'undo',
      description: 'Undo the last edit.',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
    ToolDefinition(
      name: 'redo',
      description: 'Redo the last undone edit.',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
  ];

  /// Dispatches a tool call, returning a JSON-encodable result. Throws a
  /// [ToolError] for an unknown tool, a missing node, or invalid arguments.
  Map<String, Object?> dispatch(String tool, Map<String, Object?> args) {
    switch (tool) {
      case 'describe_scene':
        return {
          'roots': [for (final n in _query.roots) _nodeTree(n)],
        };
      case 'get_node':
        return _nodeDetail(_resolve(_requireRef(args)));
      case 'get_selection':
        return _selectionResult();
      case 'select_node':
        session.selection.selectOnly(_resolve(_requireRef(args)).id);
        return _selectionResult();
      case 'search_commands':
        return {'commands': _searchCommands(args['query'] as String? ?? '')};
      case 'run_command':
        return _runCommand(args);
      case 'undo':
        return {'undone': session.undo(), 'canUndo': session.history.canUndo};
      case 'redo':
        return {'redone': session.redo(), 'canRedo': session.history.canRedo};
      default:
        throw ToolError('Unknown tool: $tool');
    }
  }

  // --- command tools ------------------------------------------------------

  List<Map<String, Object?>> _searchCommands(String query) {
    final q = query.toLowerCase();
    bool matches(CommandEntry e) =>
        q.isEmpty ||
        e.name.toLowerCase().contains(q) ||
        e.category.toLowerCase().contains(q) ||
        e.doc.toLowerCase().contains(q);
    return [
      for (final entry in session.registry.all)
        if (matches(entry))
          {
            'name': entry.name,
            'category': entry.category,
            'description': entry.doc,
            'inputSchema': mcpToolSchema(entry)['inputSchema'],
          },
    ];
  }

  Map<String, Object?> _runCommand(Map<String, Object?> args) {
    final command = args['command'];
    if (command is! String) {
      throw const ToolError('run_command needs a string "command"');
    }
    final params =
        (args['params'] as Map?)?.cast<String, Object?>() ?? const {};
    try {
      final transaction = session.run(command, params);
      return {
        'ok': true,
        'applied': transaction.name,
        'recordCount': transaction.records.length,
        'noOp': transaction.isEmpty,
        'canUndo': session.history.canUndo,
      };
    } on CommandException catch (e) {
      throw ToolError(e.message);
    } on ArgumentError catch (e) {
      throw ToolError('${e.message}');
    }
  }

  // --- perception ---------------------------------------------------------

  Map<String, Object?> _selectionResult() => {
    'primary': session.selection.primary?.toToken(),
    'primaryPath': session.selection.primary == null
        ? null
        : _query.namePathOf(session.selection.primary!),
    'selected': [for (final id in session.selection.ids) id.toToken()],
  };

  Map<String, Object?> _nodeTree(NodeSpec node) => {
    'id': node.id.toToken(),
    'path': _query.namePathOf(node.id),
    'name': node.name,
    'components': [for (final c in node.components) c.type],
    'children': [
      for (final child in _query.childrenOf(node.id)) _nodeTree(child),
    ],
  };

  Map<String, Object?> _nodeDetail(NodeSpec node) => {
    'id': node.id.toToken(),
    'path': _query.namePathOf(node.id),
    'name': node.name,
    'visible': node.visible,
    'transform': _transformJson(node.transform),
    'isPrefabInstance': node.instance != null,
    'components': [
      for (final c in node.components)
        {
          'type': c.type,
          'properties': {
            for (final entry in c.properties.entries)
              entry.key: _propertyJson(entry.value),
          },
        },
    ],
    'children': [
      for (final child in _query.childrenOf(node.id))
        {'id': child.id.toToken(), 'name': child.name},
    ],
  };

  // --- helpers ------------------------------------------------------------

  String _requireRef(Map<String, Object?> args) {
    final ref = args['ref'];
    if (ref is! String || ref.isEmpty) {
      throw const ToolError(
        'A node "ref" (slash path or id token) is required',
      );
    }
    return ref;
  }

  /// Resolves a node reference, preferring a slash name path, then an id token.
  NodeSpec _resolve(String ref) {
    final byPath = _query.nodeByNamePath(ref.split('/'));
    if (byPath != null) return byPath;
    try {
      final node = session.document.node(LocalId.parse(ref));
      if (node != null) return node;
    } on FormatException {
      // Not an id token; fall through to the not-found error.
    }
    throw ToolError('No node matches: $ref');
  }

  Object? _transformJson(TransformSpec transform) => switch (transform) {
    TrsTransform t => {
      'translation': _vec3(t.translation),
      'rotation': {
        'x': t.rotation.x,
        'y': t.rotation.y,
        'z': t.rotation.z,
        'w': t.rotation.w,
      },
      'scale': _vec3(t.scale),
    },
    MatrixTransform m => {'matrix': m.matrix.storage.toList()},
  };

  Object? _propertyJson(PropertyValue value) => switch (value) {
    BoolValue v => v.value,
    IntValue v => v.value,
    DoubleValue v => v.value,
    StringValue v => v.value,
    Vec2Value v => {'x': v.value.x, 'y': v.value.y},
    Vec3Value v => {'x': v.value.x, 'y': v.value.y, 'z': v.value.z},
    Vec4Value v => {
      'x': v.value.x,
      'y': v.value.y,
      'z': v.value.z,
      'w': v.value.w,
    },
    QuaternionValue v => {
      '\$quat': {
        'x': v.value.x,
        'y': v.value.y,
        'z': v.value.z,
        'w': v.value.w,
      },
    },
    Matrix4Value v => v.value.storage.toList(),
    ColorValue v => {'r': v.r, 'g': v.g, 'b': v.b, 'a': v.a},
    ResourceRefValue v => {'\$resource': v.id.toToken()},
    NodeRefValue v => {'\$node': v.id.toToken()},
    ListValue v => [for (final e in v.values) _propertyJson(e)],
    MapValue v => {
      for (final entry in v.values.entries)
        entry.key: _propertyJson(entry.value),
    },
  };

  Map<String, Object?> _vec3(Vector3 v) => {'x': v.x, 'y': v.y, 'z': v.z};
}
