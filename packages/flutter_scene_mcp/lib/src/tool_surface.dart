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
import 'dart:math' as math;
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

/// Drives the host's animation preview transport (the Animation panel's
/// playhead): loads an animation onto the playhead, seeks it, plays or
/// pauses, and sets loop mode and speed. Returns the resulting transport
/// state ({animation, playing, loop, speed, time, duration}). Null in a
/// headless session.
typedef AnimationPreviewControl =
    Map<String, Object?> Function({
      LocalId? animationId,
      bool? playing,
      bool? loop,
      double? speed,
      double? seek,
      bool? stop,
    });
/// Reads the prefab-expanded (composed) view of the open scene, or null when
/// the host has none (a headless session, or a scene with no prefab
/// instances). Imported rigs' bones exist only in the composed view, so
/// `get_armature` and `get_skin` read through it when it still contains the
/// resolved node and fall back to the editing document otherwise.
typedef ComposedDocumentReader = SceneDocument? Function();

/// Highlights [bones] (prefab member names) of the prefab instance [instance]
/// in the running editor's viewport, so the human sees exactly which bones
/// the agent is targeting. An empty [bones] list clears the highlight for the
/// instance. Returns the highlighted names after applying. Null in a
/// headless session.
typedef BoneHighlighter = List<String> Function(
  LocalId instance,
  List<String> bones,
);

/// Drives the host's animation preview transport (the Animation panel's

/// Builds the tiered tool surface for [session] and dispatches tool calls.
class EditorToolSurface {
  /// The default cap on keyframes returned per channel by `get_animation`
  /// and `get_keyframes`. The tool descriptions quote this as "200"; the
  /// tests pin the behavior so the two cannot drift apart silently.
  static const int _defaultMaxKeys = 200;

  /// Tolerance for time-range bounds against float32-stored keyframe times
  /// (mirrors the authoring commands' keyframe-time epsilon).
  static const double _rangeEpsilon = 1e-4;

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
    this.listDebugModes,
    this.setDebugMode,
    this.animationPreview,
    this.composedDocument,
    this.highlightBones,
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

  /// The viewport debug-output registry.
  final DebugModesList? listDebugModes;

  /// Selects a viewport debug output.
  final DebugModeSet? setDebugMode;

  /// Drives the animation preview playhead; null in a headless session
  /// (there is no Animation panel to drive).
  final AnimationPreviewControl? animationPreview;

  /// Reads the composed (prefab-expanded) scene; null in a headless session.
  /// See [ComposedDocumentReader] for why armature tools prefer it.
  final ComposedDocumentReader? composedDocument;

  /// Draws/clears the viewport's bone-highlight overlay; null in a headless
  /// session (there is no viewport to draw on).
  final BoneHighlighter? highlightBones;

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
    if (animationPreview != null)
      const ToolDefinition(
        name: 'control_animation_preview',
        description:
            'Drive the editor\'s animation preview playhead (the Animation '
            'panel): load an animation onto it, seek to a time to inspect '
            'the posed frame, play or pause, and set looping and speed. Any '
            'subset of the fields may be given; omitted fields keep their '
            'current values. Returns the transport state. Pair with '
            'screenshot_viewport to see the posed frame.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'ref': {
              'type': 'string',
              'description':
                  'Load this animation (id token or exact name) onto the '
                  'playhead, resetting its time.',
            },
            'seek': {
              'type': 'number',
              'description': 'Move the playhead to this time in seconds.',
            },
            'stop': {
              'type': 'boolean',
              'description':
                  'Stop playback: pause, reset the playhead to 0, and '
                  'restore every previewed node to its document transform.',
            },
            'playing': {
              'type': 'boolean',
              'description': 'Start playback (true) or pause it (false).',
            },
            'loop': {
              'type': 'boolean',
              'description':
                  'Whether playback wraps at the clip\'s end (default on).',
            },
            'speed': {
              'type': 'number',
              'description': 'Playback speed multiplier.',
            },
          },
          'additionalProperties': false,
        },
      ),
    if (highlightBones != null)
      const ToolDefinition(
        name: 'highlight_bones',
        description:
            'Highlight bones of a rig (a linked model instance) in the '
            'editor viewport so the human can see exactly which bones you '
            'are about to animate. Bones are addressed by member name, the '
            'same names targetName takes on the animation key commands. '
            'Call again with a different list to change the highlight, or '
            'with an empty bones list to clear it. Unknown bone names are '
            'rejected with the rig\'s bone list so you can self-correct. '
            'Returns the highlighted names.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'ref': {
              'type': 'string',
              'description':
                  'The rig: a linked model instance (slash path or id token).',
            },
            'bones': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Bone member names to highlight (e.g. ["Bone_012"]). '
                  'Empty or omitted clears the highlight.',
            },
          },
          'required': ['ref'],
          'additionalProperties': false,
        },
      ),
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
          'component types) plus an animation summary for an overview of '
          'the whole scene.',
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
      name: 'get_armature',
      description:
          'Return the armature view for one node: every skin bound in its '
          'subtree, and the full bone hierarchy (each bone\'s member name — '
          'the string targetName takes on the animation key commands — id '
          'token, slash path, parent, children, and whether animation '
          'channels already target it). For a linked model instance this '
          'reads the prefab-expanded view, so imported rigs are fully '
          'visible. Start here before authoring skeletal animation.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'string',
            'description':
                'A rig instance, a skinned mesh, or any node in their '
                'subtree (slash path or id token).',
          },
        },
        'required': ['ref'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'get_skin',
      description:
          "Return full detail for one skin: its joints in skinning order "
          '(the order the inverse-bind matrices are indexed by), each '
          "joint's transform, parent, and slash path, the skeleton root, "
          'and every mesh bound to the skin. Complements get_armature, '
          'which shows the whole hierarchy compactly.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'string',
            'description':
                'A node bound to the skin, or a rig instance (slash path '
                'or id token).',
          },
          'skin': {
            'type': 'string',
            'description':
                'A skin id token; only needed when the subtree binds more '
                'than one skin.',
          },
        },
        'required': ['ref'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'list_animations',
      description:
          'List every animation in the document with its id token, name, '
          'duration, and the target nodes and properties its channels drive.',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
    ToolDefinition(
      name: 'get_animation',
      description:
          "Return full detail for one animation: each channel's target node, "
          'property, and decoded keyframes (a time plus a value per entry; '
          'rotation values are quaternions with an eulerDeg '
          '{yaw, pitch, roll} degrees readout alongside, weights are flat '
          'lists). At most '
          'maxKeys keyframes per channel are returned (default 200); use '
          'totalKeys and keysTruncated to spot larger channels and page '
          'through them with get_keyframes. Author and edit animations '
          'through the createAnimation / setAnimationKeyframe / '
          'moveAnimationKeyframe / removeAnimationKeyframe commands via '
          'run_command.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'string',
            'description': 'An animation id token or exact name.',
          },
          'maxKeys': {
            'type': 'integer',
            'description':
                'Cap on keyframes returned per channel (default 200). '
                'Larger channels report keysTruncated.',
          },
        },
        'required': ['ref'],
        'additionalProperties': false,
      },
    ),
    ToolDefinition(
      name: 'get_keyframes',
      description:
          "Page through one animation channel's decoded keyframes by time "
          'range — the safe way to read large imported clips without '
          'flooding context. Returns entries with fromTime <= time <= '
          'toTime, capped at maxKeys, plus totalKeys in range and '
          'keysTruncated so you know to page further.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'string',
            'description': 'An animation id token or exact name.',
          },
          'node': {
            'type': 'string',
            'description':
                "The channel's target node (slash path or id "
                'token).',
          },
          'property': {
            'type': 'string',
            'description': 'translation, rotation, scale, or weights.',
          },
          'fromTime': {
            'type': 'number',
            'description': 'Inclusive lower time bound in seconds.',
          },
          'toTime': {
            'type': 'number',
            'description': 'Inclusive upper time bound in seconds.',
          },
          'maxKeys': {
            'type': 'integer',
            'description': 'Cap on keyframes returned (default 200).',
          },
        },
        'required': ['ref', 'node', 'property'],
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
          'animations': [
            for (final a in session.document.animations.values)
              _animationSummary(a),
          ],
        };
      case 'get_node':
        return _nodeDetail(_resolve(_requireRef(args)));
      case 'get_armature':
        return _armatureResult(_resolve(_requireRef(args)));
      case 'get_skin':
        return _skinResult(_resolve(_requireRef(args)), args);
      case 'highlight_bones':
        return _highlightBonesResult(args);
      case 'list_animations':
        return {
          'animations': [
            for (final a in session.document.animations.values)
              _animationSummary(a),
          ],
        };
      case 'get_animation':
        return _animationDetail(
          _resolveAnimation(_requireAnimationRef(args)),
          maxKeys: switch (args['maxKeys']) {
            null => null,
            final int keys when keys >= 1 => keys,
            final int _ => throw const ToolError(
              '"maxKeys" must be at least 1',
            ),
            _ => throw const ToolError('"maxKeys" must be an integer'),
          },
        );
      case 'get_keyframes':
        return _keyframeWindow(args);
      case 'get_selection':
        return _selectionResult();
      case 'select_node':
        session.selection.selectOnly(_resolve(_requireRef(args)).id);
        return _selectionResult();
      case 'clear_selection':
        session.selection.clear();
        return _selectionResult();
      case 'control_animation_preview':
        final control = animationPreview;
        if (control == null) {
          throw const ToolError('No animation preview control in this session');
        }
        bool? boolOf(Object? value, String name) => switch (value) {
          null => null,
          final bool flag => flag,
          _ => throw ToolError('"$name" must be a boolean'),
        };
        double? timeOf(Object? value, String name) => switch (value) {
          null => null,
          final num seconds => seconds.toDouble(),
          _ => throw ToolError('"$name" must be a number'),
        };
        final ref = args['ref'];
        if (ref != null) {
          if (ref is! String || ref.isEmpty) {
            throw const ToolError(
              '"ref" must be a non-empty animation id token or exact name',
            );
          }
        }
        return control(
          animationId: ref == null
              ? null
              : _resolveAnimation(_requireAnimationRef(args)).id,
          playing: boolOf(args['playing'], 'playing'),
          loop: boolOf(args['loop'], 'loop'),
          speed: timeOf(args['speed'], 'speed'),
          seek: timeOf(args['seek'], 'seek'),
          stop: boolOf(args['stop'], 'stop'),
        );
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

  // --- armature perception --------------------------------------------------

  /// The document, query, and resolved node armature tools read. Prefers the
  /// host's composed (prefab-expanded) view when it still contains [node]'s
  /// id — imported rigs' bones exist only there — and falls back to the
  /// editing document (which carries natively-authored skins).
  (SceneDocument, SceneQuery, NodeSpec) _armatureView(NodeSpec node) {
    final composed = composedDocument?.call();
    if (composed != null && composed.nodes.containsKey(node.id)) {
      return (composed, SceneQuery(composed), composed.nodes[node.id]!);
    }
    return (session.document, _query, node);
  }

  /// Whether an animation channel drives this bone. Two channel shapes
  /// count: a plain channel targets the bone node itself (native skins), and
  /// a member channel targets the rig root with the bone's member name in
  /// [targetName] (imported rigs, in both the host and composed views).
  bool _boneIsAnimated(
    SceneDocument doc, {
    required LocalId rigId,
    required LocalId boneId,
    required String? memberName,
  }) {
    for (final animation in doc.animations.values) {
      for (final channel in animation.channels) {
        // A plain channel targets the bone node itself (targetName is only
        // a fallback binding the commands keep in sync).
        if (channel.target == boneId) return true;
        // A member channel targets the rig root and names the bone.
        if (channel.target == rigId && channel.targetName == memberName) {
          return true;
        }
      }
    }
    return false;
  }

  /// One bone row shared by `get_armature` and `get_skin`.
  Map<String, Object?> _boneEntry(
    SceneDocument doc,
    SceneQuery query, {
    required NodeSpec bone,
    required NodeSpec? parent,
    required LocalId rigId,
    bool withTransform = false,
  }) => {
    'name': bone.name,
    'id': bone.id.toToken(),
    'path': query.namePathOf(bone.id),
    if (parent != null) 'parent': parent.name,
    'animated': _boneIsAnimated(
      doc,
      rigId: rigId,
      boneId: bone.id,
      memberName: bone.name,
    ),
    if (withTransform) 'transform': _transformJson(bone.transform),
  };

  /// The compact per-skin shape carried by `get_armature`.
  Map<String, Object?> _skinSummary(
    SceneDocument doc,
    LocalId skinId,
  ) {
    final skin = doc.skin(skinId);
    final skeleton = skin?.skeleton;
    return {
      'id': skinId.toToken(),
      'jointCount': skin?.joints.length ?? 0,
      if (skeleton != null)
        'skeleton': {
          'id': skeleton.toToken(),
          'name': doc.node(skeleton)?.name,
        },
    };
  }

  /// The armature result: skins bound in the node's subtree plus the union
  /// joint hierarchy, as a compact parent/child map an agent can walk.
  Map<String, Object?> _armatureResult(NodeSpec hostNode) {
    final (doc, query, node) = _armatureView(hostNode);

    final skinIds = <LocalId>[];
    for (final id in query.subtreeOf(node.id)) {
      final spec = doc.node(id);
      final skin = spec?.skin;
      if (skin != null && !skinIds.contains(skin)) skinIds.add(skin);
    }

    final rigId = node.id;
    // Union of every skin's joint nodes, in first-seen skin order.
    final jointIds = <LocalId>[];
    for (final skinId in skinIds) {
      for (final joint in doc.skin(skinId)?.joints ?? const <LocalId>[]) {
        if (!jointIds.contains(joint)) jointIds.add(joint);
      }
    }

    final bones = <Map<String, Object?>>[];
    for (final jointId in jointIds) {
      final bone = doc.node(jointId);
      if (bone == null) continue; // a skin referencing a missing joint
      final parentId = query.parentOf(jointId);
      bones.add(
        _boneEntry(
          doc,
          query,
          bone: bone,
          parent: parentId == null ? null : doc.node(parentId),
          rigId: rigId,
        ),
      );
    }

    return {
      'node': {
        'id': hostNode.id.toToken(),
        'name': hostNode.name,
        'path': _query.namePathOf(hostNode.id),
      },
      // Which view the bones came from: composed means prefab-expanded
      // (imported rig); document means natively-authored skin.
      'view': identical(doc, session.document) ? 'document' : 'composed',
      'skins': [for (final skinId in skinIds) _skinSummary(doc, skinId)],
      'bones': bones,
    };
  }

  /// Parses an id token, or null when [token] is not one (a name or path).
  LocalId? _tryParseId(String token) {
    try {
      return LocalId.parse(token);
    } on FormatException {
      return null;
    }
  }

  /// The `get_skin` result: skinning-order joints with transforms, the
  /// skeleton root, and every mesh bound to the skin.
  Map<String, Object?> _skinResult(
    NodeSpec hostNode,
    Map<String, Object?> args,
  ) {
    final (doc, query, node) = _armatureView(hostNode);

    final skinIdsInSubtree = <LocalId>[];
    for (final id in query.subtreeOf(node.id)) {
      final spec = doc.node(id);
      final skin = spec?.skin;
      if (skin != null && !skinIdsInSubtree.contains(skin)) {
        skinIdsInSubtree.add(skin);
      }
    }
    if (skinIdsInSubtree.isEmpty) {
      final label = hostNode.name.isEmpty
          ? hostNode.id.toToken()
          : hostNode.name;
      throw ToolError('No skin is bound in the subtree of $label');
    }

    final requested = args['skin'];
    final LocalId skinId;
    if (requested is String && requested.isNotEmpty) {
      final parsed = _tryParseId(requested);
      if (parsed == null || !skinIdsInSubtree.contains(parsed)) {
        throw ToolError(
          'No skin "$requested" is bound in this subtree; bound skins: '
          '[${skinIdsInSubtree.map((s) => s.toToken()).join(', ')}]',
        );
      }
      skinId = parsed;
    } else if (skinIdsInSubtree.length > 1) {
      throw ToolError(
        'This subtree binds ${skinIdsInSubtree.length} skins; pass a "skin" '
        'id token: [${skinIdsInSubtree.map((s) => s.toToken()).join(', ')}]',
      );
    } else {
      skinId = skinIdsInSubtree.first;
    }

    final skin = doc.skin(skinId);
    final rigId = node.id;
    final joints = [...(skin?.joints ?? const <LocalId>[])];

    return {
      'id': skinId.toToken(),
      // Joint order is the order the skin's inverse-bind matrices are
      // indexed by — the skinning contract, not just a list.
      'jointOrder': [for (final j in joints) j.toToken()],
      'jointCount': joints.length,
      if (skin?.skeleton case final skeleton?)
        'skeleton': {
          'id': skeleton.toToken(),
          'name': doc.node(skeleton)?.name,
          'path': query.namePathOf(skeleton),
        },
      'joints': [
        for (final (index, jointId) in joints.indexed)
          if (doc.node(jointId) case final bone?)
            () {
              final parentId = query.parentOf(bone.id);
              return {
                ..._boneEntry(
                  doc,
                  query,
                  bone: bone,
                  parent: parentId == null ? null : doc.node(parentId),
                  rigId: rigId,
                  withTransform: true,
                ),
                'jointIndex': index,
              };
            }(),
      ],
      // Every node bound to this skin (the meshes it deforms).
      'boundMeshes': [
        for (final entry in doc.nodes.entries)
          if (entry.value.skin == skinId)
            {
              'id': entry.key.toToken(),
              'name': entry.value.name,
              'path': query.namePathOf(entry.key),
            },
      ],
    };
  }

  /// The `highlight_bones` result: validates the request against the rig,
  /// applies the highlight through the host, and echoes the names.
  Map<String, Object?> _highlightBonesResult(Map<String, Object?> args) {
    final highlight = highlightBones;
    if (highlight == null) {
      throw const ToolError('No bone highlight control in this session');
    }
    final node = _resolve(_requireRef(args));
    final names = [
      for (final bone in args['bones'] as List? ?? const [])
        if (bone is String && bone.isNotEmpty) bone,
    ];
    // Validate against the rig before touching the host, so a typo comes
    // back as a self-correctable ToolError naming the rig's bones.
    if (names.isNotEmpty) {
      final (_, query, _) = _armatureView(node);
      final boneNames = {
        for (final id in query.subtreeOf(node.id))
          if (query.node(id)?.name case final name?) name,
      };
      final unknown = [
        for (final name in names)
          if (!boneNames.contains(name)) name,
      ];
      if (unknown.isNotEmpty) {
        final label = node.name.isEmpty ? node.id.toToken() : node.name;
        final sorted = boneNames.toList()..sort();
        throw ToolError(
          'No bone(s) $unknown on $label. Bones: $sorted',
        );
      }
    }
    return {'node': node.id.toToken(), 'highlighted': highlight(node.id, names)};
  }

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

  String _requireAnimationRef(Map<String, Object?> args) {
    final ref = args['ref'];
    if (ref is! String || ref.isEmpty) {
      throw const ToolError(
        'An animation "ref" (exact name or id token) is required',
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

  /// Resolves an animation reference, preferring an id token, then an exact
  /// name (an ambiguous name is rejected so agents fall back to the token).
  AnimationSpec _resolveAnimation(String ref) {
    try {
      final animation = session.document.animation(LocalId.parse(ref));
      if (animation != null) return animation;
    } on FormatException {
      // Not an id token; fall through to a name lookup.
    }
    final matches = [
      for (final animation in session.document.animations.values)
        if (animation.name == ref) animation,
    ];
    if (matches.length == 1) return matches.single;
    throw ToolError(
      matches.isEmpty
          ? 'No animation matches: $ref'
          : 'Animation name is ambiguous; use its id token: $ref',
    );
  }

  /// The last keyframe time across every channel of [animation].
  double _animationDuration(AnimationSpec animation) {
    var duration = 0.0;
    for (final channel in animation.channels) {
      for (final time in _channelTimes(channel)) {
        if (time > duration) duration = time;
      }
    }
    return duration;
  }

  /// The compact per-animation shape carried by `list_animations` and
  /// `describe_scene`: enough to pick an animation and see what it drives,
  /// without decoding every keyframe.
  Map<String, Object?> _animationSummary(AnimationSpec animation) => {
    'id': animation.id.toToken(),
    'name': animation.name,
    'duration': _animationDuration(animation),
    'channels': [
      for (final channel in animation.channels)
        {'target': _channelTarget(channel), 'property': channel.property.name},
    ],
  };

  /// Full detail for one animation, with each channel's keyframes decoded
  /// out of its float32 timeline/keyframes payloads.
  /// Full detail for one animation, with each channel's keyframes decoded,
  /// capped at [maxKeys] entries per channel.
  Map<String, Object?> _animationDetail(
    AnimationSpec animation, {
    int? maxKeys,
  }) => {
    'id': animation.id.toToken(),
    'name': animation.name,
    'duration': _animationDuration(animation),
    'channels': [
      for (final channel in animation.channels)
        _channelWindow(channel, null, null, maxKeys ?? _defaultMaxKeys),
    ],
  };

  /// A channel's target node, addressed the same way nodes are everywhere
  /// else on this surface (slash path first, id token as the stable form).
  Map<String, Object?> _channelTarget(AnimationChannelSpec channel) => {
    'id': channel.target.toToken(),
    if (_query.namePathOf(channel.target) case final path?) 'path': path,
    // Prefab-member channels carry the member's name (e.g. a bone).
    if (channel.targetName != null) 'member': channel.targetName,
  };

  /// One channel's decoded keyframes within an optional inclusive time
  /// range, capped at [maxKeys] entries. `totalKeys` counts every keyframe
  /// in range and `keysTruncated` says when the cap bit, so callers know to
  /// page with get_keyframes instead of flooding context. Rotation carries
  /// a quaternion per keyframe, translation and scale a vec3, and weights
  /// the flattened glTF shape (one weight per morph target per keyframe).
  Map<String, Object?> _channelWindow(
    AnimationChannelSpec channel,
    double? fromTime,
    double? toTime,
    int maxKeys,
  ) {
    final times = _channelTimes(channel);
    final valueBytes = session.document.payload(channel.keyframes)?.bytes;
    final floats = valueBytes == null ? Float32List(0) : _floatsOf(valueBytes);
    final cubic = channel.interpolation == AnimationInterpolation.cubic;
    // Row width per keyframe: transform channels carry one vector (three
    // for cubic, [inTangent, value, outTangent]); weights channels carry
    // one weight vector per morph target.
    final isRotation = channel.property == AnimationProperty.rotation;
    final isWeights = channel.property == AnimationProperty.weights;
    final componentStride = isRotation ? 4 : 3;
    final rowWidth = isWeights
        ? (times.isEmpty ? 0 : floats.length ~/ times.length)
        : componentStride * (cubic ? 3 : 1);
    final valuesPerKey = isWeights && cubic ? rowWidth ~/ 3 : rowWidth;
    // The float offset of keyframe [index]'s value slot: cubic rows carry
    // [inTangent, value, outTangent], so the value sits one component
    // stride into the row.
    int baseOf(int index) =>
        cubic ? index * rowWidth + componentStride : index * rowWidth;
    Object? valueAt(int index) {
      final base = baseOf(index);
      return switch (channel.property) {
        AnimationProperty.rotation =>
          floats.length >= base + 4
              ? {
                  'x': floats[base],
                  'y': floats[base + 1],
                  'z': floats[base + 2],
                  'w': floats[base + 3],
                }
              : null,
        AnimationProperty.weights => [
          for (var j = 0; j < valuesPerKey && base + j < floats.length; j++)
            floats[base + j],
        ],
        _ =>
          floats.length >= base + 3
              ? {
                  'x': floats[base],
                  'y': floats[base + 1],
                  'z': floats[base + 2],
                }
              : null,
      };
    }

    final inRange = <int>[
      // Times live in float32 payloads while callers pass decimal doubles,
      // so the bounds get a small tolerance (matching the authoring
      // commands' keyframe-time epsilon) instead of exact comparison.
      for (var i = 0; i < times.length; i++)
        if ((fromTime == null || times[i] >= fromTime - _rangeEpsilon) &&
            (toTime == null || times[i] <= toTime + _rangeEpsilon))
          i,
    ];
    final shown = inRange.length > maxKeys
        ? inRange.sublist(0, maxKeys)
        : inRange;
    return {
      'target': _channelTarget(channel),
      'property': channel.property.name,
      'interpolation': channel.interpolation?.name ?? 'linear',
      'totalKeys': inRange.length,
      'keysTruncated': shown.length < inRange.length,
      'keyframes': [
        for (final i in shown)
          {
            'time': times[i],
            'value': valueAt(i),
            if (cubic && !isWeights && floats.length >= baseOf(i)) ...{
              'inTangent': [
                for (var j = 0; j < componentStride; j++)
                  floats[i * rowWidth + j],
              ],
              'outTangent': [
                for (var j = 0; j < componentStride; j++)
                  floats[i * rowWidth + componentStride * 2 + j],
              ],
            },
            if (channel.property == AnimationProperty.rotation &&
                floats.length >= baseOf(i) + 4)
              'eulerDeg': _eulerDeg(
                Quaternion(
                  floats[baseOf(i)],
                  floats[baseOf(i) + 1],
                  floats[baseOf(i) + 2],
                  floats[baseOf(i) + 3],
                ),
              ),
          },
      ],
    };
  }

  /// A rotation quaternion as `{yaw, pitch, roll}` in degrees — the exact
  /// inverse of the `rotationEuler` input the authoring commands accept
  /// (extracted from the same rotation-matrix layout the engine composes,
  /// `Matrix4.setFromTranslationRotation`).
  Map<String, Object?> _eulerDeg(Quaternion q) {
    final x2 = q.x * 2;
    final y2 = q.y * 2;
    final z2 = q.z * 2;
    final m02 = q.x * z2 + q.w * y2;
    final m12 = q.y * z2 - q.w * x2;
    final m10 = q.x * y2 + q.w * z2;
    final m11 = 1.0 - (q.x * x2 + q.z * z2);
    final m22 = 1.0 - (q.x * x2 + q.y * y2);
    const degrees = 180.0 / math.pi;
    return {
      'yaw': math.atan2(m02, m22) * degrees,
      'pitch': -math.asin(m12.clamp(-1.0, 1.0)) * degrees,
      'roll': math.atan2(m10, m11) * degrees,
    };
  }

  /// The `get_keyframes` tool: one channel's keyframes over a time range.
  Map<String, Object?> _keyframeWindow(Map<String, Object?> args) {
    final animation = _resolveAnimation(_requireAnimationRef(args));
    final nodeArg = args['node'];
    if (nodeArg is! String || nodeArg.isEmpty) {
      throw const ToolError('"node" must be a non-empty node ref');
    }
    final target = _resolve(_requireRef({'ref': nodeArg})).id;
    final propertyArg = args['property'];
    AnimationProperty? property;
    for (final p in AnimationProperty.values) {
      if (p.name == propertyArg) property = p;
    }
    if (property == null) {
      throw ToolError(
        '"property" must be one of translation, rotation, scale, weights; '
        'got $propertyArg',
      );
    }
    AnimationChannelSpec? channel;
    for (final c in animation.channels) {
      if (c.target == target && c.property == property) {
        channel = c;
      }
    }
    if (channel == null) {
      throw ToolError('No $propertyArg channel on ${args['node']}');
    }
    double? bound(String key) => switch (args[key]) {
      null => null,
      final num seconds => seconds.toDouble(),
      _ => throw ToolError('"$key" must be a number'),
    };
    final maxKeys = switch (args['maxKeys']) {
      null => _defaultMaxKeys,
      final int keys when keys >= 1 => keys,
      final int _ => throw const ToolError('"maxKeys" must be at least 1'),
      _ => throw const ToolError('"maxKeys" must be an integer'),
    };
    return _channelWindow(channel, bound('fromTime'), bound('toTime'), maxKeys);
  }

  /// A payload chunk's bytes as float32s (chunks can be unaligned views).
  Float32List _floatsOf(Uint8List bytes) {
    if (bytes.offsetInBytes % 4 == 0) {
      return bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
    }
    return Uint8List.fromList(
      bytes,
    ).buffer.asFloat32List(0, bytes.lengthInBytes ~/ 4);
  }

  List<double> _channelTimes(AnimationChannelSpec channel) {
    final bytes = session.document.payload(channel.timeline)?.bytes;
    if (bytes == null) return const [];
    return [for (final t in _floatsOf(bytes)) t];
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
