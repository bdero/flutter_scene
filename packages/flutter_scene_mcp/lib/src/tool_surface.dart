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
    this.returnsImage = false,
  });

  /// The tool name.
  final String name;

  /// A one-line description for the agent.
  final String description;

  /// The JSON Schema (draft-07) for the tool's arguments.
  final Map<String, Object?> inputSchema;

  /// Whether calls route through [EditorToolSurface.dispatchImage] and
  /// return image content instead of JSON.
  final bool returnsImage;
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

/// Runs many commands through the host as one undoable step, named [name]
/// when the caller supplied one, filling [bindings] with what each call's
/// alias named.
typedef BatchRunner =
    Future<Transaction> Function(
      List<CommandCall> calls,
      String? name,
      Map<String, LocalId> bindings,
    );

/// Captures the next frame's render graph as a JSON-shaped summary
/// (passes, timings, data flow, resources). [thumbnails] false is a
/// metadata-only capture.
typedef RenderGraphCapture =
    Future<Map<String, Object?>> Function({
      required bool thumbnails,
      int? maxDimension,
    });

/// Renders one captured resource through the host's display remap into a
/// PNG. [options] carries `maxDimension`, `rangeMin`, `rangeMax`,
/// `channel`, and `highlightNonFinite` when given.
typedef RenderGraphImage =
    Future<ScreenshotResult> Function(String key, Map<String, Object?> options);

/// Reads one pixel's exact float values from a captured resource.
typedef RenderGraphPixel =
    Future<Map<String, Object?>> Function(String key, int x, int y);

/// Captures a frame and scans every float target for NaN/Inf.
typedef RenderGraphScan = Future<Map<String, Object?>> Function();

/// The live scene's rendering statistics, the last frame plus [frames] of
/// history.
typedef RenderStatsReader = Map<String, Object?> Function(int frames);

/// Lists the draw calls of the host's most recent capture. [options] carries
/// `pass`, `phase`, `node`, `material`, `includeUniforms`, `offset`, and
/// `limit` when given.
typedef RenderDrawList =
    Future<Map<String, Object?>> Function(Map<String, Object?> options);

/// One draw of the most recent capture, addressed by pass (name or index)
/// and draw order, with decoded uniform values.
typedef RenderDrawReader =
    Future<Map<String, Object?>> Function(Object pass, int order);

/// Lists every loaded shader bundle with its entries.
typedef ShaderLister = Future<Map<String, Object?>> Function();

/// Reflection for one shader entry by name.
typedef ShaderInfoReader =
    Future<Map<String, Object?>> Function(
      String name, {
      String? backend,
      bool includeSource,
    });

/// Writes the most recent capture to [path] as JSON, returning a summary.
typedef RenderCaptureSaver =
    Future<Map<String, Object?>> Function(
      String path, {
      required bool includeImages,
    });

/// Lists the viewport debug outputs (`[{id, label, active}]`).
typedef DebugModesList = List<Map<String, Object?>> Function();

/// Selects the viewport debug output by id.
typedef DebugModeSet = Future<void> Function(String id);

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

/// Opens (or creates for a directory) an `.fproject`; returns the same shape
/// as [ProjectInfo].
typedef ProjectOpener = Future<Map<String, Object?>> Function(String path);

/// Closes the open project.
typedef ProjectCloser = Future<void> Function();

/// The open project's info (name, path, root, configurations, selected
/// configuration id), or null with no project open.
typedef ProjectInfo = Map<String, Object?>? Function();

/// Selects the project's build configuration by id.
typedef BuildConfigurationSelector = Future<void> Function(String id);

/// Starts the selected configuration's build/run command; returns whether it
/// started.
typedef ProjectCommandStarter = Future<bool> Function();

/// Stops the running app/build.
typedef ProjectCommandStopper = Future<void> Function();

/// Restarts the running app session; returns whether the daemon reported
/// success.
typedef SessionRestarter = Future<bool> Function();

/// The app session's state (state, appId, mode, deviceId, vmServiceUri,
/// supportsHotReload, supportsHotRestart).
typedef AppStateReader = Map<String, Object?> Function();

/// Lists the registered component types (type, doc, provenance).
typedef ComponentTypeLister = List<Map<String, Object?>> Function();

/// The full schema JSON for one component type, or null when unknown.
typedef ComponentTypeDescriber = Map<String, Object?>? Function(String type);

/// The console tail plus building/running flags.
typedef ConsoleReader = Map<String, Object?> Function(int tail);

/// Lists devices from the selected installation ({devices: [{id, name,
/// targetPlatform, emulator}]}).
typedef DeviceLister = Future<Map<String, Object?>> Function({bool refresh});

/// Selects the target device by id for the open project.
typedef DeviceSelector = Future<void> Function(String id);

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
    this.windowScreenshot,
    this.commandRunner,
    this.batchRunner,
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
    this.openProject,
    this.closeProject,
    this.projectInfo,
    this.selectBuildConfiguration,
    this.buildProject,
    this.runProject,
    this.stopProject,
    this.hotRestart,
    this.hotReload,
    this.reloadScene,
    this.appState,
    this.listComponentTypes,
    this.describeComponentType,
    this.readConsole,
    this.listDevices,
    this.selectDevice,
    this.renderGraphCapture,
    this.renderGraphImage,
    this.renderGraphPixel,
    this.renderGraphScan,
    this.readRenderStats,
    this.listDraws,
    this.readDraw,
    this.listShaders,
    this.readShaderInfo,
    this.saveRenderCapture,
    this.listDebugModes,
    this.setDebugMode,
  }) : _sessionProvider = sessionProvider;

  /// Convenience over a fixed [session] (headless use, tests).
  EditorToolSurface.of(
    EditorSession session, {
    ViewportScreenshot? screenshot,
    ViewportScreenshot? windowScreenshot,
  }) : this(
         () => session,
         screenshot: screenshot,
         windowScreenshot: windowScreenshot,
       );

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

  /// Captures the whole editor window (viewport plus panels), or null in a
  /// headless session.
  final ViewportScreenshot? windowScreenshot;

  /// Host-routed mutation, so applied commands reach the host's display.
  final CommandRunner? commandRunner;

  /// Host-routed batch, for the same reason. Null runs on the session.
  final BatchRunner? batchRunner;

  /// Pushes events to the connected client, set by a transport that can send
  /// server notifications. Null leaves every subscription poll-only.
  void Function(String subscription, List<EditorEvent> events)? eventPush;

  /// The subscriptions this connection made.
  ///
  /// The bus is shared across every connection and outlives any one of them,
  /// so a surface that did not make a subscription must not be able to poll
  /// or cancel it, and one that goes away must not leave its buffers and push
  /// closures behind. Both follow from owning them here.
  final Map<String, EventSubscription> _subscriptions = {};

  /// Cancels every subscription this connection made. The transport calls it
  /// when the client disconnects.
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

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

  /// Project lifecycle and build/run control; null members hide the
  /// corresponding tools (a headless session).
  final ProjectOpener? openProject;
  final ProjectCloser? closeProject;
  final ProjectInfo? projectInfo;
  final BuildConfigurationSelector? selectBuildConfiguration;
  final ProjectCommandStarter? buildProject;
  final ProjectCommandStarter? runProject;
  final ProjectCommandStopper? stopProject;
  final SessionRestarter? hotRestart;
  final SessionRestarter? hotReload;
  final SessionRestarter? reloadScene;
  final AppStateReader? appState;
  final ComponentTypeLister? listComponentTypes;
  final ComponentTypeDescriber? describeComponentType;
  final ConsoleReader? readConsole;
  final DeviceLister? listDevices;
  final DeviceSelector? selectDevice;

  /// Render graph inspection; null in sessions without a live renderer.
  final RenderGraphCapture? renderGraphCapture;

  /// Remapped image of one captured resource; see [dispatchImage].
  final RenderGraphImage? renderGraphImage;

  /// Exact float pixel values from a captured resource.
  final RenderGraphPixel? renderGraphPixel;

  /// The whole-frame non-finite scan.
  final RenderGraphScan? renderGraphScan;

  /// Steady-state per-frame rendering statistics.
  final RenderStatsReader? readRenderStats;

  /// Draw calls of the most recent capture.
  final RenderDrawList? listDraws;

  /// One draw of the most recent capture.
  final RenderDrawReader? readDraw;

  /// The loaded shader bundles.
  final ShaderLister? listShaders;

  /// Reflection for one shader entry.
  final ShaderInfoReader? readShaderInfo;

  /// Writes the most recent capture to disk.
  final RenderCaptureSaver? saveRenderCapture;

  /// The viewport debug-output registry.
  final DebugModesList? listDebugModes;

  /// Selects a viewport debug output.
  final DebugModeSet? setDebugMode;

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
        returnsImage: true,
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (windowScreenshot != null)
      const ToolDefinition(
        name: 'screenshot_window',
        description:
            'Capture the whole editor window as a PNG image, including the '
            'panels around the viewport (outliner, inspector, asset browser), '
            'so you can see the editor UI exactly as the user does.',
        returnsImage: true,
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
    if (openProject != null)
      const ToolDefinition(
        name: 'open_project',
        description:
            'Open a .fproject (or a Flutter project directory, creating a '
            'default .fproject beside its pubspec.yaml). Independent of the '
            'open scene. Returns the project info with its build '
            'configurations.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Absolute path to a .fproject file or a Flutter project '
                  'directory.',
            },
          },
          'required': ['path'],
          'additionalProperties': false,
        },
      ),
    if (closeProject != null)
      const ToolDefinition(
        name: 'close_project',
        description: 'Close the open project (the scene stays open).',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (projectInfo != null)
      const ToolDefinition(
        name: 'get_project',
        description:
            'The open project (name, root, build configurations, selected '
            'configuration), or projectOpen false.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (selectBuildConfiguration != null)
      const ToolDefinition(
        name: 'select_build_configuration',
        description: 'Select the project build configuration by id.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': 'The configuration id.'},
          },
          'required': ['id'],
          'additionalProperties': false,
        },
      ),
    if (buildProject != null)
      const ToolDefinition(
        name: 'build_project',
        description:
            'Start the selected configuration\'s build command (streams into '
            'the console; poll get_console).',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (runProject != null)
      const ToolDefinition(
        name: 'run_project',
        description:
            'Launch the Play session, an editor-managed flutter run for the '
            'selected configuration and device. Structured progress streams '
            'into the console; poll get_app_state for the lifecycle '
            '(launching/running), then hot_restart/hot_reload/stop_project '
            'drive it.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (stopProject != null)
      const ToolDefinition(
        name: 'stop_project',
        description: 'Stop the app session started by run_project.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (hotRestart != null)
      const ToolDefinition(
        name: 'hot_restart',
        description:
            'Hot restart the running app session (debug and profile modes).',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (hotReload != null)
      const ToolDefinition(
        name: 'hot_reload',
        description: 'Hot reload the running app session (debug mode).',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (reloadScene != null)
      const ToolDefinition(
        name: 'reload_scene',
        description:
            'Ask the running debug session to reload changed scene assets in '
            'place over the VM service (sub-second; needs source-direct '
            'loading, which Play sessions launch with). Returns ok false when '
            'the session cannot, in which case hot_restart is the fallback.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (listComponentTypes != null)
      const ToolDefinition(
        name: 'list_component_types',
        description:
            'The component types nodes can carry (builtin, package, and '
            'schema-discovered project types), with docs and provenance. '
            'Use describe_component_type for a type\'s full property schema.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (describeComponentType != null)
      const ToolDefinition(
        name: 'describe_component_type',
        description:
            'The full property schema of one component type: property names, '
            'kinds, defaults, constraints, and docs, as consumed by the '
            'inspector. Feeds correct addComponent/setComponentProperties '
            'calls.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'type': {'type': 'string', 'description': 'The component type.'},
          },
          'required': ['type'],
          'additionalProperties': false,
        },
      ),
    if (appState != null)
      const ToolDefinition(
        name: 'get_app_state',
        description:
            'The app session lifecycle state (idle/launching/running/'
            'restarting/stopping) plus appId, mode, device, and VM service '
            'URI when running.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (listDevices != null)
      const ToolDefinition(
        name: 'list_devices',
        description:
            'Devices reported by the selected Flutter installation (the '
            'toolbar device dropdown source). Pass refresh true to relist.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'refresh': {'type': 'boolean', 'description': 'Relist devices.'},
          },
          'additionalProperties': false,
        },
      ),
    if (selectDevice != null)
      const ToolDefinition(
        name: 'select_device',
        description:
            'Select the target device by id for the open project (feeds the '
            'DEVICE and BUILD_TARGET command variables).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': 'The device id.'},
          },
          'required': ['id'],
          'additionalProperties': false,
        },
      ),
    if (readConsole != null)
      const ToolDefinition(
        name: 'get_console',
        description: 'The build/run console tail plus building/running flags.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'tail': {
              'type': 'integer',
              'description': 'Lines from the end (default 100).',
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
    if (renderGraphCapture != null) ...[
      const ToolDefinition(
        name: 'list_render_passes',
        description:
            'Capture the next frame\'s render graph metadata: the executed '
            'passes in order with CPU timings and the blackboard keys each '
            'read and wrote, plus every render target\'s format and size. '
            'No images; use capture_render_graph or get_pass_output for '
            'those.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      const ToolDefinition(
        name: 'capture_render_graph',
        description:
            'Capture the next frame\'s render graph with thumbnails, '
            'refreshing the capture get_pass_output and read_pass_pixel '
            'read from. Returns the same graph JSON as list_render_passes.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'maxDimension': {
              'type': 'integer',
              'description': 'Longest thumbnail edge in pixels (default 256).',
            },
          },
          'additionalProperties': false,
        },
      ),
      const ToolDefinition(
        name: 'get_pass_output',
        description:
            'Render one captured resource (a blackboard key from '
            'list_render_passes, e.g. "scene_color", "linear_depth") as a '
            'PNG through the display remap, so you can see any intermediate '
            'buffer. Non-finite highlighting paints NaN magenta, Inf '
            'yellow, negative blue.',
        returnsImage: true,
        inputSchema: {
          'type': 'object',
          'properties': {
            'key': {'type': 'string'},
            'maxDimension': {
              'type': 'integer',
              'description': 'Longest output edge (default full size).',
            },
            'rangeMin': {'type': 'number'},
            'rangeMax': {'type': 'number'},
            'channel': {
              'type': 'string',
              'description': 'r, g, b, or a for single-channel grayscale.',
            },
            'highlightNonFinite': {'type': 'boolean'},
          },
          'required': ['key'],
          'additionalProperties': false,
        },
      ),
      const ToolDefinition(
        name: 'read_pass_pixel',
        description:
            'Read one pixel\'s exact float RGBA values from a captured '
            'resource, including NaN/Inf flags. Coordinates are texels from '
            'the top-left of the full-resolution target.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'key': {'type': 'string'},
            'x': {'type': 'integer'},
            'y': {'type': 'integer'},
          },
          'required': ['key', 'x', 'y'],
          'additionalProperties': false,
        },
      ),
      const ToolDefinition(
        name: 'scan_for_nans',
        description:
            'Capture a frame and scan every float render target for '
            'NaN/Inf, in pass execution order. The first offending pass is '
            'where non-finite values originate; everything downstream is '
            'contamination.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    ],
    if (readRenderStats != null)
      const ToolDefinition(
        name: 'get_render_stats',
        description:
            'Return the last rendered frame\'s counters (draws, instances, '
            'vertices, culling, batching, pipeline traffic) broken down by '
            'view and pass, with CPU times. Always on, no capture needed.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'frames': {
              'type': 'integer',
              'description':
                  'Also return this many recent frames of history '
                  '(default 0).',
            },
          },
          'additionalProperties': false,
        },
      ),
    if (listDraws != null)
      const ToolDefinition(
        name: 'list_draws',
        description:
            'List the draw calls of the most recent capture (capturing one '
            'first when there is none), with node paths, materials, shader '
            'names, and batching, plus a per-pass tally of why items were '
            'skipped.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'pass': {
              'type': ['string', 'integer'],
              'description': 'Only draws in this pass name or index.',
            },
            'phase': {
              'type': 'string',
              'description': 'Only draws in this draw phase.',
            },
            'node': {
              'type': 'string',
              'description': 'Substring match on the node path.',
            },
            'material': {
              'type': 'string',
              'description': 'Substring match on the material type or source.',
            },
            'includeUniforms': {
              'type': 'boolean',
              'description': 'Include decoded uniform values (default false).',
            },
            'offset': {'type': 'integer'},
            'limit': {
              'type': 'integer',
              'description': 'Draws to return (default 200).',
            },
          },
          'additionalProperties': false,
        },
      ),
    if (readDraw != null)
      const ToolDefinition(
        name: 'get_draw',
        description:
            'Return one draw of the most recent capture with its decoded '
            'uniform blocks and shader names. Address it by the pass name or '
            'index and the draw order from list_draws.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'pass': {
              'type': ['string', 'integer'],
            },
            'order': {'type': 'integer'},
          },
          'required': ['pass', 'order'],
          'additionalProperties': false,
        },
      ),
    if (listShaders != null)
      const ToolDefinition(
        name: 'list_shaders',
        description:
            'List every loaded shader bundle and its entries, with each '
            'entry\'s stage, compiled backends, uniform block names, and '
            'texture names.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
    if (readShaderInfo != null)
      const ToolDefinition(
        name: 'get_shader_info',
        description:
            'Return one shader entry\'s reflection by name (inputs, uniform '
            'blocks with field offsets, textures), optionally with the '
            'compiled source. SPIR-V comes back base64.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'backend': {
              'type': 'string',
              'description':
                  'metalIos, metalDesktop, openglEs, openglDesktop, or '
                  'vulkan (default the running platform\'s).',
            },
            'includeSource': {'type': 'boolean'},
          },
          'required': ['name'],
          'additionalProperties': false,
        },
      ),
    if (saveRenderCapture != null)
      const ToolDefinition(
        name: 'save_render_graph_capture',
        description:
            'Write the most recent capture (capturing one first when there '
            'is none) to a JSON file, including every draw, uniform block, '
            'and resource image, for offline inspection.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'includeImages': {
              'type': 'boolean',
              'description': 'Embed resource PNGs (default true).',
            },
          },
          'required': ['path'],
          'additionalProperties': false,
        },
      ),
    if (listDebugModes != null) ...[
      const ToolDefinition(
        name: 'list_viewport_debug_modes',
        description:
            'List the viewport debug outputs (final output, HDR color, '
            'linear depth, normals, AO, shadow atlas, ...) and which is '
            'active.',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      const ToolDefinition(
        name: 'set_viewport_debug_mode',
        description:
            'Render one debug output full-viewport instead of the final '
            'image (pair with screenshot_viewport to eyeball any buffer). '
            'Set "final" to restore normal rendering.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'mode': {'type': 'string'},
          },
          'required': ['mode'],
          'additionalProperties': false,
        },
      ),
    ],
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
      name: 'run_commands',
      description:
          'Run many commands in order as ONE undoable step. Name a call with '
          '"as" and later calls reference what it created as "\$name" '
          'wherever an id goes, so a payload and the geometry over it are one '
          'batch. Nothing is kept unless every call succeeds. Takes document '
          'and selection commands only. Use this instead of repeated '
          'run_command whenever you are making more than a couple of edits.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'commands': {
            'type': 'array',
            'description': 'The calls, in order.',
            'items': {
              'type': 'object',
              'properties': {
                'command': {'type': 'string'},
                'params': {'type': 'object'},
                'as': {
                  'type': 'string',
                  'description':
                      'Name what this call creates, so a later call can '
                      'reference it as "\$name" wherever an id goes.',
                },
              },
              'required': ['command'],
            },
          },
          'name': {
            'type': 'string',
            'description': 'The label the undo history shows for the step.',
          },
        },
        'required': ['commands'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'search_queries',
      description:
          'Search the read surface by name, category, or words in the '
          'description. Returns each match with its argument schema, ready to '
          'pass to run_query.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Substring to match, or empty for every query.',
          },
        },
      },
    ),
    ToolDefinition(
      name: 'run_query',
      description:
          'Read the document through a named query. Queries answer in bulk '
          '(a whole subtree, a whole resource, a whole payload), so prefer '
          'one query over many small reads. Binary comes back base64-encoded '
          'under "blobs".',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'params': {'type': 'object'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'subscribe_events',
      description:
          'Subscribe to editor events. Returns a subscription id to pass to '
          'poll_events. Events are coalesced, so a batch of a thousand edits '
          'is one notification.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'types': {
            'type': 'array',
            'description': 'Event names; omit for every event.',
            'items': {'type': 'string'},
          },
        },
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'poll_events',
      description:
          'Drain the events buffered for a subscription, oldest first. '
          'Reports how many were dropped when a client fell far behind.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'subscription': {'type': 'string'},
        },
        'required': ['subscription'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'unsubscribe_events',
      description: 'Cancel a subscription and release what it buffered.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'subscription': {'type': 'string'},
        },
        'required': ['subscription'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'get_protocol_info',
      description:
          'The protocol version this editor speaks, what it can do, and the '
          'event names it emits. Ask before assuming a capability is here.',
      inputSchema: {'type': 'object', 'properties': {}},
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
    // TODO(query-parity): get_node still assembles its own answer, because it
    // mixes in world bounds only the host can compute. Give queries a host
    // seam and it collapses onto getResource and nodeSubtree like the rest.
    switch (tool) {
      case 'describe_scene':
        return {
          'roots': [
            for (final node in session.ask('nodeSubtree').body['nodes'] as List)
              _compactTree(node as Map<String, Object?>),
          ],
        };
      case 'get_node':
        return _nodeDetail(_resolve(_requireRef(args)));
      case 'get_selection':
        return _selectionResult();
      case 'select_node':
        // Through the command, so this tool and a script take one path.
        await _invoke('selectNodes', {
          'nodeIds': [_resolve(_requireRef(args)).id.toToken()],
        });
        return _selectionResult();
      case 'clear_selection':
        await _invoke('clearSelection', const {});
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
      case 'open_project':
        final opener = openProject;
        if (opener == null) {
          throw const ToolError('No project control in this session');
        }
        final projectPath = args['path'];
        if (projectPath is! String || projectPath.isEmpty) {
          throw const ToolError('open_project needs a string "path"');
        }
        try {
          return await opener(projectPath);
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
      case 'close_project':
        final closer = closeProject;
        if (closer == null) {
          throw const ToolError('No project control in this session');
        }
        await closer();
        return {'ok': true};
      case 'get_project':
        final info = projectInfo;
        if (info == null) {
          throw const ToolError('No project control in this session');
        }
        return info() ?? {'projectOpen': false};
      case 'select_build_configuration':
        final selector = selectBuildConfiguration;
        if (selector == null) {
          throw const ToolError('No project control in this session');
        }
        final id = args['id'];
        if (id is! String || id.isEmpty) {
          throw const ToolError(
            'select_build_configuration needs a string "id"',
          );
        }
        try {
          await selector(id);
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
        return {'ok': true};
      case 'build_project':
        final builder = buildProject;
        if (builder == null) {
          throw const ToolError('No project control in this session');
        }
        return {'ok': true, 'started': await builder()};
      case 'run_project':
        final startRunner = runProject;
        if (startRunner == null) {
          throw const ToolError('No project control in this session');
        }
        return {'ok': true, 'started': await startRunner()};
      case 'stop_project':
        final stopper = stopProject;
        if (stopper == null) {
          throw const ToolError('No project control in this session');
        }
        await stopper();
        return {'ok': true};
      case 'hot_restart':
        final restarter = hotRestart;
        if (restarter == null) {
          throw const ToolError('No project control in this session');
        }
        return {'ok': await restarter()};
      case 'hot_reload':
        final reloader = hotReload;
        if (reloader == null) {
          throw const ToolError('No project control in this session');
        }
        return {'ok': await reloader()};
      case 'reload_scene':
        final sceneReloader = reloadScene;
        if (sceneReloader == null) {
          throw const ToolError('No project control in this session');
        }
        return {'ok': await sceneReloader()};
      case 'list_component_types':
        final lister = listComponentTypes;
        if (lister == null) {
          throw const ToolError('No component registry in this session');
        }
        return {'types': lister()};
      case 'describe_component_type':
        final describer = describeComponentType;
        if (describer == null) {
          throw const ToolError('No component registry in this session');
        }
        final typeName = args['type'];
        if (typeName is! String || typeName.isEmpty) {
          throw const ToolError(
            'describe_component_type needs a string "type"',
          );
        }
        final schema = describer(typeName);
        if (schema == null) {
          throw ToolError('Unknown component type: $typeName');
        }
        return schema;
      case 'get_app_state':
        final stateReader = appState;
        if (stateReader == null) {
          throw const ToolError('No project control in this session');
        }
        return stateReader();
      case 'list_devices':
        final lister = listDevices;
        if (lister == null) {
          throw const ToolError('No project control in this session');
        }
        try {
          return await lister(refresh: args['refresh'] == true);
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
      case 'select_device':
        final deviceSelector = selectDevice;
        if (deviceSelector == null) {
          throw const ToolError('No project control in this session');
        }
        final deviceId = args['id'];
        if (deviceId is! String || deviceId.isEmpty) {
          throw const ToolError('select_device needs a string "id"');
        }
        try {
          await deviceSelector(deviceId);
        } on FormatException catch (e) {
          throw ToolError(e.message);
        }
        return {'ok': true};
      case 'get_console':
        final reader = readConsole;
        if (reader == null) {
          throw const ToolError('No project control in this session');
        }
        final tail = args['tail'];
        return reader(tail is num ? tail.toInt() : 100);
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
      case 'run_commands':
        return _runCommands(args);
      case 'search_queries':
        return {'queries': _searchQueries(args['query'] as String? ?? '')};
      case 'run_query':
        return _runQuery(args);
      case 'subscribe_events':
        return _subscribeEvents(args);
      case 'poll_events':
        return _pollEvents(args);
      case 'unsubscribe_events':
        return _unsubscribeEvents(args);
      case 'get_protocol_info':
        // Answered without a document, since a client asks what this build
        // speaks before it decides what to open.
        final open = _sessionProvider();
        return {
          'version': EditorProtocol.version,
          'capabilities': EditorProtocol.capabilities,
          'events': EditorEventType.all,
          'documentOpen': open != null,
          if (open != null) 'commandCount': open.registry.all.length,
          if (open != null) 'queryCount': open.queries.all.length,
        };
      case 'undo':
        final undone = await (undoRunner?.call() ?? Future.value(_undoHere()));
        return {'undone': undone, 'canUndo': session.history.canUndo};
      case 'redo':
        final redone = await (redoRunner?.call() ?? Future.value(_redoHere()));
        return {'redone': redone, 'canRedo': session.history.canRedo};
      case 'list_resources':
        return session.ask('listResources').body;
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
      case 'list_render_passes':
        final capture = renderGraphCapture;
        if (capture == null) {
          throw const ToolError('No render graph capture in this session');
        }
        return capture(thumbnails: false);
      case 'capture_render_graph':
        final capture = renderGraphCapture;
        if (capture == null) {
          throw const ToolError('No render graph capture in this session');
        }
        return capture(
          thumbnails: true,
          maxDimension: _optionalInt(args, 'maxDimension'),
        );
      case 'read_pass_pixel':
        final reader = renderGraphPixel;
        if (reader == null) {
          throw const ToolError('No render graph capture in this session');
        }
        final key = args['key'];
        final x = args['x'];
        final y = args['y'];
        if (key is! String || x is! num || y is! num) {
          throw const ToolError('read_pass_pixel needs key, x, and y');
        }
        return reader(key, x.toInt(), y.toInt());
      case 'scan_for_nans':
        final scanner = renderGraphScan;
        if (scanner == null) {
          throw const ToolError('No render graph capture in this session');
        }
        return scanner();
      case 'get_render_stats':
        final reader = readRenderStats;
        if (reader == null) {
          throw const ToolError('No render statistics in this session');
        }
        return reader(_optionalInt(args, 'frames') ?? 0);
      case 'list_draws':
        final lister = listDraws;
        if (lister == null) {
          throw const ToolError('No render graph capture in this session');
        }
        _requirePassRef(args, required: false);
        for (final name in ['phase', 'node', 'material']) {
          if (args[name] is! String?) {
            throw ToolError('$name must be a string');
          }
        }
        if (args['includeUniforms'] is! bool?) {
          throw const ToolError('includeUniforms must be a boolean');
        }
        _optionalInt(args, 'offset');
        _optionalInt(args, 'limit');
        return lister(args);
      case 'get_draw':
        final reader = readDraw;
        if (reader == null) {
          throw const ToolError('No render graph capture in this session');
        }
        final pass = _requirePassRef(args, required: true)!;
        final order = args['order'];
        if (order is! num) {
          throw const ToolError('get_draw needs an order');
        }
        return reader(pass, order.toInt());
      case 'list_shaders':
        final lister = listShaders;
        if (lister == null) {
          throw const ToolError('No shader reflection in this session');
        }
        return lister();
      case 'get_shader_info':
        final reader = readShaderInfo;
        if (reader == null) {
          throw const ToolError('No shader reflection in this session');
        }
        final name = args['name'];
        if (name is! String) {
          throw const ToolError('get_shader_info needs a shader name');
        }
        final backend = args['backend'];
        if (backend is! String?) {
          throw const ToolError('backend must be a string');
        }
        final includeSource = args['includeSource'];
        if (includeSource is! bool?) {
          throw const ToolError('includeSource must be a boolean');
        }
        return reader(
          name,
          backend: backend,
          includeSource: includeSource ?? false,
        );
      case 'save_render_graph_capture':
        final saver = saveRenderCapture;
        if (saver == null) {
          throw const ToolError('No render graph capture in this session');
        }
        final path = args['path'];
        if (path is! String || path.isEmpty) {
          throw const ToolError('save_render_graph_capture needs a path');
        }
        final includeImages = args['includeImages'];
        if (includeImages is! bool?) {
          throw const ToolError('includeImages must be a boolean');
        }
        return saver(path, includeImages: includeImages ?? true);
      case 'list_viewport_debug_modes':
        final lister = listDebugModes;
        if (lister == null) {
          throw const ToolError('No viewport debug modes in this session');
        }
        return {'modes': lister()};
      case 'set_viewport_debug_mode':
        final setter = setDebugMode;
        final lister = listDebugModes;
        if (setter == null || lister == null) {
          throw const ToolError('No viewport debug modes in this session');
        }
        final mode = args['mode'];
        if (mode is! String) {
          throw const ToolError('set_viewport_debug_mode needs a mode id');
        }
        await setter(mode);
        return {'ok': true, 'modes': lister()};
      case 'screenshot_viewport' || 'screenshot_window' || 'get_pass_output':
        throw ToolError(
          '$tool returns image content; call dispatchImage() instead of '
          'dispatch()',
        );
      default:
        throw ToolError('Unknown tool: $tool');
    }
  }

  /// Dispatches an image-returning tool (see [ToolDefinition.returnsImage]),
  /// returning `{mimeType, width, height, base64}`.
  Future<Map<String, Object?>> dispatchImage(
    String tool,
    Map<String, Object?> args,
  ) async {
    switch (tool) {
      case 'screenshot_viewport':
        return capture();
      case 'screenshot_window':
        return captureWindow();
      case 'get_pass_output':
        final fetch = renderGraphImage;
        if (fetch == null) {
          throw const ToolError('No render graph capture in this session');
        }
        final key = args['key'];
        if (key is! String) {
          throw const ToolError('get_pass_output needs a resource key');
        }
        // Tools register with schema validation off (the surface owns its
        // errors), so mistyped options must become ToolErrors here rather
        // than escaping as TypeErrors from the host callback.
        _optionalInt(args, 'maxDimension');
        _optionalNum(args, 'rangeMin');
        _optionalNum(args, 'rangeMax');
        if (args['channel'] is! String?) {
          throw const ToolError('channel must be a string (r, g, b, or a)');
        }
        if (args['highlightNonFinite'] is! bool?) {
          throw const ToolError('highlightNonFinite must be a boolean');
        }
        final shot = await fetch(key, args);
        return {
          'mimeType': 'image/png',
          'width': shot.width,
          'height': shot.height,
          'base64': base64Encode(shot.pngBytes),
        };
      default:
        throw ToolError('$tool does not return image content');
    }
  }

  // A pass is addressed by name or index, so both types pass through.
  static Object? _requirePassRef(
    Map<String, Object?> args, {
    required bool required,
  }) {
    final pass = args['pass'];
    if (pass == null) {
      if (!required) return null;
      throw const ToolError('A pass name or index is required');
    }
    if (pass is String) return pass;
    if (pass is num) return pass.toInt();
    throw const ToolError('pass must be a pass name or index');
  }

  static int? _optionalInt(Map<String, Object?> args, String name) {
    final value = args[name];
    if (value == null) return null;
    if (value is! num) throw ToolError('$name must be a number');
    return value.toInt();
  }

  static num? _optionalNum(Map<String, Object?> args, String name) {
    final value = args[name];
    if (value == null) return null;
    if (value is! num) throw ToolError('$name must be a number');
    return value;
  }

  /// Captures the viewport as a base64 PNG, for the `screenshot_viewport`
  /// tool. Throws a [ToolError] in a headless session (no [screenshot]
  /// provider). Asynchronous because image encoding is, so it sits beside
  /// the synchronous [dispatch] rather than inside it.
  Future<Map<String, Object?>> capture() =>
      _captureWith(screenshot, 'viewport');

  /// Captures the whole editor window as a base64 PNG, for the
  /// `screenshot_window` tool. See [capture].
  Future<Map<String, Object?>> captureWindow() =>
      _captureWith(windowScreenshot, 'window');

  Future<Map<String, Object?>> _captureWith(
    ViewportScreenshot? provider,
    String what,
  ) async {
    if (provider == null) {
      throw ToolError('No $what is available to screenshot in this session');
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

  List<Map<String, Object?>> _searchQueries(String query) {
    final q = query.toLowerCase();
    bool matches(QueryEntry e) =>
        q.isEmpty ||
        e.name.toLowerCase().contains(q) ||
        e.category.toLowerCase().contains(q) ||
        e.doc.toLowerCase().contains(q);
    return [
      for (final entry in session.queries.all)
        if (matches(entry))
          {
            'name': entry.name,
            'category': entry.category,
            'description': entry.doc,
            'inputSchema': querySchema(entry)['inputSchema'],
          },
    ];
  }

  Map<String, Object?> _runQuery(Map<String, Object?> args) {
    final name = args['query'];
    if (name is! String || name.isEmpty) {
      throw const ToolError('run_query needs a string "query"');
    }
    final params =
        (args['params'] as Map?)?.cast<String, Object?>() ?? const {};
    final QueryResult result;
    try {
      result = session.ask(name, params);
    } on QueryException catch (e) {
      throw ToolError(e.message);
    } on ArgumentError catch (e) {
      throw ToolError('${e.message}');
    }
    // JSON-RPC cannot frame binary, so blobs ride in the body as base64, the
    // fallback the protocol declares. A transport that can frame them sends
    // the same blobs beside the body instead, with the body unchanged.
    return {
      ...result.body,
      if (result.blobs.isNotEmpty)
        'blobs': {
          for (final blob in result.blobs)
            blob.id: {
              'mimeType': blob.mimeType,
              'byteCount': blob.bytes.lengthInBytes,
              'base64': base64Encode(blob.bytes),
            },
        },
    };
  }

  Future<Map<String, Object?>> _runCommands(Map<String, Object?> args) async {
    final entries = args['commands'];
    if (entries is! List) {
      throw const ToolError('run_commands needs a "commands" array');
    }
    if (entries.isEmpty) {
      throw const ToolError('run_commands needs at least one command');
    }
    final calls = <CommandCall>[];
    for (final entry in entries) {
      if (entry is! Map) {
        throw const ToolError('Every entry in "commands" must be an object');
      }
      try {
        calls.add(CommandCall.fromJson(entry.cast<String, Object?>()));
      } on CommandException catch (e) {
        throw ToolError(e.message);
      }
    }
    final name = args['name'];
    final label = name is String && name.isNotEmpty ? name : null;
    final bindings = <String, LocalId>{};
    final runner = batchRunner;
    // Caught around both paths, since a host-routed batch throws the same
    // failure and a client should read it, not a stack trace.
    final Transaction transaction;
    try {
      transaction = runner != null
          ? await runner(calls, label, bindings)
          : session.runAll(
              calls,
              name: label ?? 'Batch edit',
              bindings: bindings,
            );
    } on BatchException catch (e) {
      throw ToolError(e.message);
    } on CommandException catch (e) {
      throw ToolError(e.message);
    }
    return {
      'ok': true,
      'applied': transaction.name,
      'commandCount': calls.length,
      'recordCount': transaction.records.length,
      'noOp': transaction.isEmpty,
      'canUndo': session.history.canUndo,
      'created': _createdIn(transaction),
      if (bindings.isNotEmpty)
        'bindings': {
          for (final entry in bindings.entries)
            entry.key: entry.value.toToken(),
        },
    };
  }

  Map<String, Object?> _subscribeEvents(Map<String, Object?> args) {
    final types = args['types'];
    final wanted = <String>[];
    if (types == null) {
      wanted.addAll(EditorEventType.all);
    } else if (types is List) {
      for (final type in types) {
        if (type is! String) {
          throw const ToolError('"types" must be an array of event names');
        }
        wanted.add(type);
      }
    } else {
      throw const ToolError('"types" must be an array of event names');
    }
    try {
      // The closure names the subscription it belongs to, which only exists
      // once subscribe returns; nothing can fire before then.
      late final EventSubscription subscription;
      subscription = session.events.subscribe(
        wanted,
        onEvents: (events) => eventPush?.call(subscription.id, events),
      );
      _subscriptions[subscription.id] = subscription;
      return {
        'subscription': subscription.id,
        'types': subscription.types.toList(),
        'pushed': eventPush != null,
      };
    } on ArgumentError catch (e) {
      throw ToolError('${e.message}');
    }
  }

  EventSubscription _requireSubscription(Map<String, Object?> args) {
    final id = args['subscription'];
    if (id is! String || id.isEmpty) {
      throw const ToolError('Expected a "subscription" id');
    }
    // Looked up among this connection's own, so one client cannot reach
    // another's by guessing an id.
    final subscription = _subscriptions[id];
    if (subscription == null) {
      throw ToolError(
        'No subscription "$id" on this connection; it may have been '
        'cancelled, or it belongs to another client',
      );
    }
    return subscription;
  }

  Map<String, Object?> _pollEvents(Map<String, Object?> args) {
    final subscription = _requireSubscription(args);
    // Deliver whatever this turn produced before draining, so a client that
    // edits and immediately polls does not have to poll twice.
    session.events.flush();
    final drained = subscription.drain();
    return {
      'events': [for (final event in drained.events) event.toJson()],
      'dropped': drained.dropped,
    };
  }

  Map<String, Object?> _unsubscribeEvents(Map<String, Object?> args) {
    final subscription = _requireSubscription(args)..cancel();
    _subscriptions.remove(subscription.id);
    return {'ok': true};
  }

  bool _undoHere() => session.undo();

  bool _redoHere() => session.redo();

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

  /// Runs [command] the way `run_command` does, so tools that wrap a command
  /// cannot drift from it.
  Future<void> _invoke(String command, Map<String, Object?> params) async {
    try {
      commandRunner != null
          ? await commandRunner!(command, params)
          : session.run(command, params);
    } on CommandException catch (e) {
      throw ToolError(e.message);
    }
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
      final entry = session.registry.lookup(command);
      if (entry != null && entry.kind == CommandKind.application) {
        // Asynchronous, and outside the document, so it reports what it did
        // rather than a transaction.
        await session.invoke(command, params);
        return {
          'ok': true,
          'applied': command,
          'canUndo': session.history.canUndo,
        };
      }
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
        (
          ChangeSlot.poolPayload,
          PayloadChange(value: final o),
          PayloadChange(value: final n),
        ) =>
          ('payload', o == null, n != null),
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

  /// The compact tree an agent reads first, projected from the `nodeSubtree`
  /// query so both describe the same data. Component types only, since the
  /// whole point of this view is to be small enough to take in at once.
  Map<String, Object?> _compactTree(Map<String, Object?> node) => {
    'id': node['id'],
    'path': node['path'],
    'name': node['name'],
    'components': [
      for (final component in node['components'] as List)
        (component as Map)['type'],
    ],
    'children': [
      for (final child in (node['children'] as List? ?? const []))
        _compactTree(child as Map<String, Object?>),
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
              entry.key: propertyValueToJson(entry.value),
          },
          // Declared kinds for the carried properties, when the type's
          // schema is known (see describe_component_type for the full one).
          if (_componentKinds(c) case final kinds?) 'kinds': kinds,
        },
    ],
    'children': [
      for (final child in _query.childrenOf(node.id))
        {'id': child.id.toToken(), 'name': child.name},
    ],
  };

  // --- helpers ------------------------------------------------------------

  Map<String, Object?>? _componentKinds(ComponentSpec component) {
    final schema = describeComponentType?.call(component.type);
    if (schema == null) return null;
    final kinds = <String, Object?>{};
    if (schema['properties'] is List) {
      for (final def in schema['properties'] as List) {
        if (def is! Map) continue;
        final name = def['name'];
        if (name is String && component.properties.containsKey(name)) {
          kinds[name] = def['kind'];
        }
      }
    }
    return kinds.isEmpty ? null : kinds;
  }

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

  Map<String, Object?> _vec3(Vector3 v) => {'x': v.x, 'y': v.y, 'z': v.z};
}
