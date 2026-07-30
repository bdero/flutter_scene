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

import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/scene.dart' hide NodeChange;
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:vector_math/vector_math.dart';

/// A captured viewport image (PNG-encoded), returned by a
/// [ViewportScreenshot] provider.
class ScreenshotResult {
  /// Creates a screenshot result.
  const ScreenshotResult({
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  /// PNG-encoded image bytes.
  final Uint8List pngBytes;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;
}

/// Captures the running editor's viewport as a PNG. Supplied by the editor
/// app (the headless core and the tool surface have no GPU), and exposed to
/// agents as the `screenshot_viewport` perception tool when present.
typedef ViewportScreenshot = Future<ScreenshotResult> Function();

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

/// Runs one command through the host and returns the applied transaction.
typedef CommandRunner =
    Future<Transaction> Function(String command, Map<String, Object?> params);

/// The pose of the host's primary viewport camera (an orbit camera), so
/// agents can compose their own screenshots. Angles are radians.
class ViewportCameraPose {
  /// Creates a pose.
  const ViewportCameraPose({
    required this.azimuth,
    required this.elevation,
    required this.radius,
    required this.target,
    required this.orthographic,
  });

  /// Horizontal orbit angle around the target.
  final double azimuth;

  /// Vertical orbit angle (positive looks down from above).
  final double elevation;

  /// Distance from the target.
  final double radius;

  /// The world-space point the camera orbits and looks at.
  final Vector3 target;

  /// Whether the viewport renders with a parallel projection.
  final bool orthographic;
}

/// Reads the primary viewport's camera, or null when no viewport is attached.
typedef ViewportCameraRead = ViewportCameraPose? Function();

/// Applies a full camera pose to the primary viewport.
typedef ViewportCameraWrite = void Function(ViewportCameraPose pose);

/// Frames the primary viewport on the node with [id]; false when the node
/// has no renderable bounds to frame.
typedef ViewportFrameNode = bool Function(LocalId id);

/// Imports the model file at [path] (`.glb`/`.gltf`) into the scene as a
/// linked prefab instance (under [parentId] when given), returning the
/// scene-relative asset path further instances can reference through the
/// `instantiatePrefab` command. Throws [FormatException] when the scene has
/// not been saved yet (a linked import needs a scene directory).
typedef ModelImporter =
    Future<String> Function(String path, {LocalId? parentId, double scale});

/// Imports the equirectangular panorama at [path] (`.hdr` or an LDR image)
/// and applies it to an environment resource (the stage's global one when
/// [environmentId] is null), returning the referenced asset path.
typedef EnvironmentImporter =
    Future<String> Function(String path, {LocalId? environmentId});

/// The world-space bounds of a node's rendered subtree, or null when it has
/// nothing renderable.
typedef NodeBounds = Aabb3? Function(LocalId id);

/// Creates a fresh empty document, replacing the current one.
typedef DocumentCreator = Future<void> Function();

/// Opens the `.fscene` document at an absolute path, replacing the current
/// document. Throws [FormatException] on a malformed file.
typedef DocumentOpener = Future<void> Function(String path);

/// Saves the current document; [path] is required the first time (Save As)
/// and optional afterward. Returns the absolute path written. Throws
/// [FormatException] when no path is known yet.
typedef DocumentSaver = Future<String> Function({String? path});

/// Builds the tiered tool surface for [session] and dispatches tool calls.
class EditorToolSurface {
  /// Creates a surface over [session].
  ///
  /// When [screenshot] is supplied (by a running editor), a
  /// `screenshot_viewport` perception tool is offered and handled by
  /// [capture].
  ///
  /// A live editor must also supply [commandRunner], [undoRunner], and
  /// [redoRunner] bound to the layer that reflects document changes into
  /// what it renders; running on the bare [session] would mutate the
  /// document while the screen keeps showing the old scene. Left null (a
  /// headless session), mutations run on the session directly.
  EditorToolSurface(
    EditorSession? Function() sessionProvider, {
    this.screenshot,
    this.commandRunner,
    this.undoRunner,
    this.redoRunner,
    this.readCamera,
    this.writeCamera,
    this.frameNode,
    this.importModel,
    this.importEnvironment,
    this.nodeBounds,
    this.newDocument,
    this.openDocument,
    this.saveDocument,
  }) : _sessionProvider = sessionProvider;

  /// Convenience over a fixed [session] (headless use, tests).
  EditorToolSurface.of(EditorSession session, {ViewportScreenshot? screenshot})
    : this(() => session, screenshot: screenshot);

  final EditorSession? Function() _sessionProvider;

  /// The editing session this surface reads and drives. Resolved on every
  /// use, so one connection stays valid across document swaps (New/Open).
  EditorSession get session {
    final current = _sessionProvider();
    if (current == null) {
      throw const ToolError(
        'No document is open; call new_document or open_document first',
      );
    }
    return current;
  }

  /// Captures the live viewport, or null in a headless session.
  final ViewportScreenshot? screenshot;

  /// Host-routed mutation, so applied commands reach the host's display.
  final CommandRunner? commandRunner;

  /// Host-routed undo; returns whether a transaction was undone.
  final Future<bool> Function()? undoRunner;

  /// Host-routed redo; returns whether a transaction was redone.
  final Future<bool> Function()? redoRunner;

  /// Reads the primary viewport's camera pose; null in a headless session.
  final ViewportCameraRead? readCamera;

  /// Writes the primary viewport's camera pose; null in a headless session.
  final ViewportCameraWrite? writeCamera;

  /// Frames the primary viewport on a node; null in a headless session.
  final ViewportFrameNode? frameNode;

  /// Imports a model file as a linked prefab; null when the host has no
  /// filesystem import pipeline.
  final ModelImporter? importModel;

  /// Imports an equirectangular panorama as the environment; null when the
  /// host has no filesystem import pipeline.
  final EnvironmentImporter? importEnvironment;

  /// Measures a node's rendered world-space bounds; null in a headless
  /// session (bounds come from the realized scene).
  final NodeBounds? nodeBounds;

  /// Creates a fresh document; null when the host does not expose document
  /// lifecycle control.
  final DocumentCreator? newDocument;

  /// Opens a document from disk; null when the host does not expose document
  /// lifecycle control.
  final DocumentOpener? openDocument;

  /// Saves the document to disk; null when the host does not expose document
  /// lifecycle control.
  final DocumentSaver? saveDocument;

  SceneQuery get _query => session.query;

  /// The curated tools an agent is offered up front. The full command set is
  /// reached through `search_commands` plus `run_command`, not listed here.
  /// The `screenshot_viewport` tool is appended only when a [screenshot]
  /// provider is available.
  List<ToolDefinition> bootstrapTools() => [
    ..._baseTools,
    if (screenshot != null)
      const ToolDefinition(
        name: 'screenshot_viewport',
        description:
            'Capture the current editor viewport as a PNG image, so you can '
            'see the rendered scene exactly as the user does.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (readCamera != null) ..._cameraTools,
    if (newDocument != null)
      const ToolDefinition(
        name: 'new_document',
        description:
            'Create a fresh empty scene document, replacing whatever is '
            'open. Unsaved changes in the current document are lost.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (openDocument != null)
      const ToolDefinition(
        name: 'open_document',
        description:
            'Open a .fscene document from disk, replacing whatever is open. '
            'Unsaved changes in the current document are lost.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Absolute path to the .fscene file.',
            },
          },
          'required': ['path'],
          'additionalProperties': false,
        },
      ),
    if (saveDocument != null)
      const ToolDefinition(
        name: 'save_document',
        description:
            'Save the current document. Pass a path the first time (or to '
            'save a copy elsewhere); afterwards the known path is reused. '
            'Saving also enables linked imports (import_model, '
            'import_environment), which need a scene directory.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Absolute path for the .fscene file.',
            },
          },
          'additionalProperties': false,
        },
      ),
    if (importEnvironment != null)
      const ToolDefinition(
        name: 'import_environment',
        description:
            'Import an equirectangular panorama (.hdr or LDR image) from '
            'disk and use it as the environment lighting and skybox. '
            'Targets the stage\'s global environment resource unless an '
            'environmentId is given.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Absolute path to the panorama file.',
            },
            'environmentId': {
              'type': 'string',
              'description': 'Optional environment resource id token.',
            },
          },
          'required': ['path'],
          'additionalProperties': false,
        },
      ),
    if (importModel != null)
      const ToolDefinition(
        name: 'import_model',
        description:
            'Import a .glb/.gltf model file from disk into the scene as a '
            'linked prefab instance. Returns the scene-relative asset path; '
            'place further copies by passing that path to the '
            'instantiatePrefab command. The scene must have been saved.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Absolute path to the model file.',
            },
            'parentId': {
              'type': 'string',
              'description': 'Optional parent node id token.',
            },
            'scale': {
              'type': 'number',
              'description': 'Uniform import scale (default 1).',
            },
          },
          'required': ['path'],
          'additionalProperties': false,
        },
      ),
  ];

  static const List<ToolDefinition> _cameraTools = [
    ToolDefinition(
      name: 'get_viewport_camera',
      description:
          'Return the primary viewport camera pose (orbit azimuth/elevation '
          'in radians, radius, target point, orthographic flag).',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
    ToolDefinition(
      name: 'set_viewport_camera',
      description:
          'Move the primary viewport camera. Any subset of the pose fields '
          'may be given; omitted fields keep their current values. Compose '
          'your shot with this before screenshot_viewport.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'azimuth': {
            'type': 'number',
            'description': 'Horizontal orbit angle, radians.',
          },
          'elevation': {
            'type': 'number',
            'description':
                'Vertical orbit angle, radians; positive looks down.',
          },
          'radius': {
            'type': 'number',
            'description': 'Distance from the target.',
          },
          'target': {
            'type': 'object',
            'properties': {
              'x': {'type': 'number'},
              'y': {'type': 'number'},
              'z': {'type': 'number'},
            },
            'required': ['x', 'y', 'z'],
            'description': 'World-space look-at point.',
          },
          'orthographic': {'type': 'boolean'},
        },
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'frame_node',
      description:
          'Aim the primary viewport camera at a node and pull back so its '
          'whole subtree fits the view. The fastest way to compose a shot of '
          'one object.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'string',
            'description': 'A node slash path or id token.',
          },
        },
        'required': ['ref'],
        'additionalProperties': false,
      },
    ),
  ];

  static const List<ToolDefinition> _baseTools = [
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
      name: 'clear_selection',
      description:
          'Deselect everything (also removes selection outlines and the '
          'transform gizmo from screenshots).',
      inputSchema: {'type': 'object', 'properties': {}},
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
      name: 'list_resources',
      description:
          'List every resource in the document (geometries, materials, '
          'textures, environments) with its id token, including ones not '
          'attached to any node.',
      inputSchema: {'type': 'object', 'properties': {}},
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
  Future<Map<String, Object?>> dispatch(
    String tool,
    Map<String, Object?> args,
  ) async {
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
      case 'clear_selection':
        session.selection.clear();
        return _selectionResult();
      case 'new_document':
        final creator = newDocument;
        if (creator == null) {
          throw const ToolError('No document control in this session');
        }
        await creator();
        return {'ok': true};
      case 'open_document':
        final opener = openDocument;
        if (opener == null) {
          throw const ToolError('No document control in this session');
        }
        final openPath = args['path'];
        if (openPath is! String || openPath.isEmpty) {
          throw const ToolError('open_document needs a string "path"');
        }
        try {
          await opener(openPath);
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
        return {'ok': true, 'path': openPath};
      case 'save_document':
        final saver = saveDocument;
        if (saver == null) {
          throw const ToolError('No document control in this session');
        }
        try {
          final saved = await saver(path: args['path'] as String?);
          return {'ok': true, 'path': saved};
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
      case 'import_environment':
        final envImporter = importEnvironment;
        if (envImporter == null) {
          throw const ToolError(
            'No environment import pipeline is available in this session',
          );
        }
        final envPath = args['path'];
        if (envPath is! String || envPath.isEmpty) {
          throw const ToolError('import_environment needs a string "path"');
        }
        final envToken = args['environmentId'] as String?;
        try {
          final asset = await envImporter(
            envPath,
            environmentId: envToken == null ? null : LocalId.parse(envToken),
          );
          return {'ok': true, 'asset': asset};
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
      case 'import_model':
        final importer = importModel;
        if (importer == null) {
          throw const ToolError(
            'No model import pipeline is available in this session',
          );
        }
        final path = args['path'];
        if (path is! String || path.isEmpty) {
          throw const ToolError('import_model needs a string "path"');
        }
        final parentToken = args['parentId'] as String?;
        try {
          final asset = await importer(
            path,
            parentId: parentToken == null ? null : _resolve(parentToken).id,
            scale: (args['scale'] as num?)?.toDouble() ?? 1.0,
          );
          return {'ok': true, 'asset': asset};
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
      case 'search_commands':
        return {'commands': _searchCommands(args['query'] as String? ?? '')};
      case 'run_command':
        return _runCommand(args);
      case 'undo':
        final undone = await (undoRunner?.call() ?? Future.value(_undoHere()));
        return {'undone': undone, 'canUndo': session.history.canUndo};
      case 'redo':
        final redone = await (redoRunner?.call() ?? Future.value(_redoHere()));
        return {'redone': redone, 'canRedo': session.history.canRedo};
      case 'list_resources':
        return {
          'resources': [
            for (final entry in session.document.resources.entries)
              {'id': entry.key.toToken(), 'kind': _resourceKind(entry.value)},
          ],
        };
      case 'get_viewport_camera':
        return _cameraResult();
      case 'set_viewport_camera':
        final current = _requireCamera();
        final target = args['target'] as Map?;
        writeCamera!(
          ViewportCameraPose(
            azimuth: (args['azimuth'] as num?)?.toDouble() ?? current.azimuth,
            elevation:
                (args['elevation'] as num?)?.toDouble() ?? current.elevation,
            radius: (args['radius'] as num?)?.toDouble() ?? current.radius,
            target: target == null
                ? current.target
                : Vector3(
                    (target['x'] as num).toDouble(),
                    (target['y'] as num).toDouble(),
                    (target['z'] as num).toDouble(),
                  ),
            orthographic: args['orthographic'] as bool? ?? current.orthographic,
          ),
        );
        return _cameraResult();
      case 'frame_node':
        _requireCamera();
        final node = _resolve(_requireRef(args));
        if (!frameNode!(node.id)) {
          throw ToolError(
            'Node "${args['ref']}" has no renderable bounds to frame',
          );
        }
        return _cameraResult();
      case 'screenshot_viewport':
        throw const ToolError(
          'screenshot_viewport is asynchronous; call capture() instead of '
          'dispatch()',
        );
      default:
        throw ToolError('Unknown tool: $tool');
    }
  }

  /// Captures the viewport as a base64 PNG, for the `screenshot_viewport`
  /// tool. Throws a [ToolError] in a headless session (no [screenshot]
  /// provider). Asynchronous because image encoding is, so it sits beside
  /// the synchronous [dispatch] rather than inside it.
  Future<Map<String, Object?>> capture() async {
    final provider = screenshot;
    if (provider == null) {
      throw const ToolError(
        'No viewport is available to screenshot in this session',
      );
    }
    final shot = await provider();
    return {
      'mimeType': 'image/png',
      'width': shot.width,
      'height': shot.height,
      'base64': base64Encode(shot.pngBytes),
    };
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

  bool _undoHere() => session.undo();

  bool _redoHere() => session.redo();

  String _resourceKind(ResourceSpec spec) => switch (spec) {
    GeometryResource() => 'geometry',
    TextureResource() => 'texture',
    RenderTextureResource() => 'renderTexture',
    MaterialResource() => 'material',
    EnvironmentResource() => 'environment',
  };

  ViewportCameraPose _requireCamera() {
    final pose = readCamera?.call();
    if (pose == null) {
      throw const ToolError('No viewport camera is available in this session');
    }
    return pose;
  }

  Map<String, Object?> _cameraResult() {
    final pose = _requireCamera();
    return {
      'azimuth': pose.azimuth,
      'elevation': pose.elevation,
      'radius': pose.radius,
      'target': {'x': pose.target.x, 'y': pose.target.y, 'z': pose.target.z},
      'orthographic': pose.orthographic,
    };
  }

  Future<Map<String, Object?>> _runCommand(Map<String, Object?> args) async {
    final command = args['command'];
    if (command is! String) {
      throw const ToolError('run_command needs a string "command"');
    }
    final params =
        (args['params'] as Map?)?.cast<String, Object?>() ?? const {};
    if (command == 'undo' || command == 'redo') {
      throw ToolError(
        '"$command" is a top-level tool; call it directly rather than '
        'through run_command',
      );
    }
    try {
      final transaction = commandRunner != null
          ? await commandRunner!(command, params)
          : session.run(command, params);
      return {
        'ok': true,
        'applied': transaction.name,
        'recordCount': transaction.records.length,
        'noOp': transaction.isEmpty,
        'canUndo': session.history.canUndo,
        // Ids of anything the command created, so a multi-step agent flow
        // can chain on them (attach a mesh to a fresh geometry/material).
        'created': _createdIn(transaction),
      };
    } on CommandException catch (e) {
      throw ToolError(e.message);
    } on ArgumentError catch (e) {
      throw ToolError('${e.message}');
    }
  }

  /// The entities [transaction] brought into existence, as
  /// `{kind, id}` pairs (a pool record going from absent to present).
  List<Map<String, String>> _createdIn(Transaction transaction) {
    final created = <Map<String, String>>[];
    for (final record in transaction.records) {
      final (kind, wasAbsent, isPresent) = switch ((
        record.slot,
        record.oldValue,
        record.newValue,
      )) {
        (
          ChangeSlot.poolNode,
          NodeChange(value: final o),
          NodeChange(value: final n),
        ) =>
          ('node', o == null, n != null),
        (
          ChangeSlot.poolResource,
          ResourceChange(value: final o),
          ResourceChange(value: final n),
        ) =>
          ('resource', o == null, n != null),
        (
          ChangeSlot.poolSkin,
          SkinChange(value: final o),
          SkinChange(value: final n),
        ) =>
          ('skin', o == null, n != null),
        (
          ChangeSlot.poolAnimation,
          AnimationChange(value: final o),
          AnimationChange(value: final n),
        ) =>
          ('animation', o == null, n != null),
        _ => ('', false, false),
      };
      if (wasAbsent && isPresent) {
        created.add({'kind': kind, 'id': record.targetId.toToken()});
      }
    }
    return created;
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
    // Rendered world-space bounds, the honest way to learn an asset's real
    // size (kits differ in unit scale).
    if (nodeBounds?.call(node.id) case final bounds?)
      'worldBounds': {
        'min': {'x': bounds.min.x, 'y': bounds.min.y, 'z': bounds.min.z},
        'max': {'x': bounds.max.x, 'y': bounds.max.y, 'z': bounds.max.z},
      },
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
