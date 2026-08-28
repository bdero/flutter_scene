// The main window is created through the framework's experimental windowing
// API (the macOS runner is headless; multi-view mode must be entered before
// any view controller exists, so every window originates from Dart).
// TODO(docking): drop these ignores when the windowing API is stable.
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';
import 'package:scene/schema.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart' show ToolError;
import 'package:flutter_scene_mcp/socket_host.dart';

void main() {
  // The windowing guards in the framework read this at call time, and the
  // flag is a plain mutable bool rather than a const, so opting in here is
  // equivalent to the FLUTTER_ENABLED_FEATURE_FLAGS dart-define the tool
  // refuses to pass on stable. The runner creates no window of its own, so
  // without the opt-in every windowing call throws and there is nothing to
  // render into. Drop this once windowing reaches stable upstream
  // (flutter/flutter#30701) and the dart-define arrives on its own.
  isWindowingEnabled = true;
  WidgetsFlutterBinding.ensureInitialized();
  final controller = RegularWindowController(
    size: const Size(1280, 800),
    // The runner styles the window with a hidden title bar by this title
    // (see AppDelegate.swift); keep the two in sync.
    title: 'Scene Editor',
    delegate: _MainWindowDelegate(),
  );
  runWidget(
    RegularWindow(controller: controller, child: const FlutterSceneEditorApp()),
  );
}

/// Quits the app when the main editor window closes, taking any floating
/// panel windows with it.
class _MainWindowDelegate with RegularWindowControllerDelegate {
  @override
  void onWindowDestroyed() {
    exit(0);
  }
}

/// Window services the runner exposes for the hidden-title-bar chrome.
const _windowChannel = MethodChannel('scene_editor/window');

/// Asks the runner to move the window with the in-progress drag (the menu
/// bar acts as the title bar).
void _startWindowDrag() {
  _windowChannel.invokeMethod<void>('startDrag');
}

/// Clears the macOS traffic lights, which draw over the content now that the
/// title bar is hidden.
const double _windowControlsInset = 78;

/// The standalone Flutter Scene Editor.
///
/// Launches a start screen to create a new scene or open an existing
/// `.fscene`, then drops into the full editor. A localhost MCP server is
/// hosted so an agent can drive the live editor (see `socket_host.dart`).
class FlutterSceneEditorApp extends StatelessWidget {
  const FlutterSceneEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scene Editor',
      theme: editorDarkTheme(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => EditorThemeScope(child: child!),
      home: const _EditorHome(),
    );
  }
}

class _EditorHome extends StatefulWidget {
  const _EditorHome();

  @override
  State<_EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<_EditorHome> {
  EditorController? _controller;
  String? _busy;
  String? _error;

  // Key on the viewport's RepaintBoundary so the MCP screenshot tool can
  // capture exactly what the user sees.
  final _viewportKey = GlobalKey();

  // Key on a RepaintBoundary around the whole editor, so screenshot_window
  // captures the panels around the viewport too.
  final _windowKey = GlobalKey();

  // Remote control on the primary viewport's camera, for the MCP camera
  // tools (agents composing their own screenshots).
  final _cameraHandle = ViewportCameraHandle();
  ServerSocket? _mcpServer;

  late final EditorSettingsStore _settingsStore;
  late final EditorSettings _settings;

  // Component-gizmo visibility, shared by every viewport and persisted with
  // the settings.
  final GizmoPreferences _gizmoPreferences = GizmoPreferences();

  // Render graph inspection over MCP, bound to the live controller's scene.
  late final RenderGraphMcp _renderGraphMcp = RenderGraphMcp(
    () => _controller?.scene,
  );

  // TODO(path-provider): resolve through path_provider if this app ever
  // targets more than macOS; only macos/ scaffolding is committed today.
  Directory _settingsDirectory() {
    final home = Platform.environment['HOME'] ?? '.';
    return Directory('$home/Library/Application Support/FlutterSceneEditor');
  }

  // The open document's file path (null for a new unsaved scene). The app
  // owns this so both the shell's File menu and the MCP document tools stay
  // in agreement.
  String? _scenePath;

  // The identity this build was made with (bundled by the build hook) and
  // the prober behind installation health badges.
  EditorBuildInfo _buildInfo = EditorBuildInfo.unknown;
  final InstallationInspector _inspector = InstallationInspector();

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChangedForSchemas);
    final directory = _settingsDirectory();
    _settingsStore = EditorSettingsStore(
      file: File('${directory.path}/settings.json'),
      legacyDockLayoutFile: File('${directory.path}/dock_layout.json'),
    );
    _settings = _settingsStore.load();
    _gizmoPreferences.load(
      enabled: _settings.gizmosEnabled,
      hiddenTypes: _settings.hiddenGizmoTypes,
    );
    _gizmoPreferences.addListener(_persistGizmoPreferences);
    unawaited(
      EditorBuildInfo.load(
        'packages/flutter_scene_editor_app/editor_build_info.json',
      ).then((info) {
        if (mounted) setState(() => _buildInfo = info);
      }),
    );
    // The MCP server runs for the app's whole life (not per document), so an
    // agent can create or open a document itself and drive the editor
    // start to finish.
    _startMcpServer();
  }

  // Routes the fmat compiler through the selected Flutter installation; no
  // selection falls back to the bundled/detected toolchain.
  Future<FmatToolchain> _resolveToolchain() {
    final selected = _settings.selectedInstallation;
    if (selected == null) return findFmatToolchain();
    return fmatToolchainForInstallation(selected);
  }

  void _configureController(EditorController controller) {
    controller.fmatLibrary.toolchainResolver = _resolveToolchain;
    // Foreign component types already learned (cache, package manifests,
    // source extraction, or a live session) carry over to every controller
    // the editor swaps in, keeping their original provenance.
    final byProvenance = <String, List<ComponentSchema>>{};
    for (final entry in _foreignSchemas.entries) {
      byProvenance
          .putIfAbsent(_foreignSchemaProvenance[entry.key] ?? 'cache', () => [])
          .add(entry.value);
    }
    // Cache first so fresher provenances win their type slots.
    for (final provenance in ['cache', ...byProvenance.keys]) {
      final schemas = byProvenance.remove(provenance);
      if (schemas == null || schemas.isEmpty) continue;
      controller.adoptForeignSchemas(schemas, provenance: provenance);
    }
    controller.componentSourcePaths.addAll(_componentSourcePaths);
    controller.sourceFileOpener = (path) =>
        openSourceInEditor(_settings.editorCommand, path);
    controller.nodeFramer = (id) {
      final bounds = controller.liveNode(id)?.combinedWorldBounds;
      if (bounds == null) return false;
      _cameraHandle.frame(bounds);
      return true;
    };
  }

  // The latest foreign component schemas by type, with their provenance.
  final Map<String, ComponentSchema> _foreignSchemas = {};
  final Map<String, String> _foreignSchemaProvenance = {};

  // Absolute source file per component type, from source extraction.
  final Map<String, String> _componentSourcePaths = {};

  // Types the project's source extraction has yielded this session, the
  // ownership record sweep-retirement keys on (provenance labels flip to
  // `live` after a Play fetch, so they cannot carry ownership).
  final Set<String> _sourceOwnedTypes = {};
  AppSessionState _lastSessionState = AppSessionState.idle;

  String _schemaCachePath(FProject project) =>
      '${project.resolvedProjectRoot}/.dart_tool/flutter_scene_editor/'
      'component_schemas.json';

  /// Loads the per-project schema cache so foreign components are known
  /// before any Play session runs (they stay marked cache-sourced until a
  /// live fetch confirms them).
  void _loadCachedComponentSchemas(FProject project) {
    try {
      final file = File(_schemaCachePath(project));
      if (!file.existsSync()) return;
      final schemas = decodeComponentSchemas(
        jsonDecode(file.readAsStringSync()),
      );
      if (schemas.isEmpty) return;
      for (final schema in schemas) {
        // The cache never overwrites a fresher in-memory provenance.
        if (_foreignSchemas.containsKey(schema.type)) continue;
        _foreignSchemas[schema.type] = schema;
        _foreignSchemaProvenance[schema.type] = 'cache';
      }
      _controller?.adoptForeignSchemas(schemas, provenance: 'cache');
    } catch (_) {
      // A stale or corrupt cache regenerates on the next live fetch.
    }
  }

  /// The session reached running; fetch its registered component schemas
  /// (authoritative) and refresh the project cache. The dev channel registers
  /// when the app first touches flutter_scene, so retry once shortly after.
  void _onSessionChangedForSchemas() {
    final state = _session.state;
    if (state == _lastSessionState) return;
    _lastSessionState = state;
    if (state != AppSessionState.running) return;
    unawaited(() async {
      for (final delay in const [Duration(seconds: 2), Duration(seconds: 6)]) {
        await Future<void>.delayed(delay);
        if (_session.state != AppSessionState.running) return;
        final schemas = await _session.fetchComponentSchemas();
        if (schemas == null || schemas.isEmpty) continue;
        if (!mounted) return;
        // The app's registry is authoritative for app-derived types: a
        // cache/live-provenance type absent from the fetch was deleted from
        // the project (its stale cache entry would otherwise resurrect it
        // every open). Source and package types re-derive locally.
        final fetched = {for (final schema in schemas) schema.type};
        // Source-owned types are excluded by ownership, not the provenance
        // label (a Play fetch stamps them 'live'): a fetch from a stale
        // build whose registrar predates the type must not retire a
        // component whose .dart source is intact on disk.
        final stale = [
          for (final entry in _foreignSchemaProvenance.entries)
            if ((entry.value == 'cache' || entry.value == 'live') &&
                !fetched.contains(entry.key) &&
                !_sourceOwnedTypes.contains(entry.key))
              entry.key,
        ];
        for (final type in stale) {
          _foreignSchemas.remove(type);
          _foreignSchemaProvenance.remove(type);
          _componentSourcePaths.remove(type);
        }
        if (stale.isNotEmpty) _controller?.retireForeignSchemas(stale);
        for (final schema in schemas) {
          _foreignSchemas[schema.type] = schema;
          _foreignSchemaProvenance[schema.type] = 'live';
        }
        _controller?.adoptForeignSchemas(schemas, provenance: 'live');
        final project = _project;
        if (project != null) {
          try {
            File(_schemaCachePath(project))
              ..createSync(recursive: true)
              ..writeAsStringSync(jsonEncode(encodeComponentSchemas(schemas)));
          } catch (_) {
            // Cache write is best effort.
          }
        }
        return;
      }
    }());
  }

  // The selected installation changed; recompile fmats through the new
  // toolchain.
  void _onInstallationSelectionChanged() {
    final controller = _controller;
    if (controller == null) return;
    controller.fmatLibrary.invalidateToolchain();
    unawaited(controller.recompose());
  }

  late final ManagedCheckouts _managedCheckouts = ManagedCheckouts(
    paths: ManagedCheckoutPaths('${_settingsDirectory().path}/sdks'),
  );

  // The open project, independent of the open scene (either may be open
  // without the other).
  FProject? _project;

  // Task subprocess owner, feeding the Console panel. One per app so console
  // history survives project and scene swaps.
  final ProjectRunner _runner = ProjectRunner();

  // The Play session (flutter run --machine), logging into the same console.
  late final AppSession _session = AppSession(log: _runner.addLine);

  // Device listing against the selected installation (the toolbar's device
  // dropdown and the \${DEVICE}/\${BUILD_TARGET} variables).
  final DeviceCatalog _deviceCatalog = DeviceCatalog();

  /// The selected device for the open project. Resolved through the catalog
  /// cache when listed; a persisted id not yet listed keeps working for
  /// \${DEVICE} with an unknown platform.
  FlutterDevice? get _selectedDevice {
    final project = _project;
    if (project == null) return null;
    final id = _settings.selectedDevices[project.path];
    if (id == null) return null;
    final installation = _settings.selectedInstallation;
    final listed = installation == null
        ? null
        : _deviceCatalog.cached(installation);
    if (listed != null) {
      for (final device in listed) {
        if (device.id == id) return device;
      }
    }
    return FlutterDevice(id: id, name: id, targetPlatform: '');
  }

  void _selectDevice(FlutterDevice device) {
    final project = _project;
    if (project == null) return;
    setState(() => _settings.selectedDevices[project.path] = device.id);
    _persistSettings();
  }

  // Warms the device cache so a persisted selection regains its platform.
  void _warmDeviceCache() {
    final installation = _settings.selectedInstallation;
    if (installation == null) return;
    unawaited(
      _deviceCatalog
          .list(installation)
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object _) {}),
    );
  }

  /// The selected build configuration for the open project (per-user state in
  /// settings), falling back to the project's first configuration.
  BuildConfiguration? get _selectedBuildConfiguration {
    final project = _project;
    if (project == null) return null;
    final remembered = project.configurationById(
      _settings.selectedBuildConfigurations[project.path],
    );
    if (remembered != null) return remembered;
    return project.buildConfigurations.isEmpty
        ? null
        : project.buildConfigurations.first;
  }

  void _setProject(FProject? project) {
    setState(() => _project = project);
    _sourceWatch?.cancel();
    _sourceWatch = null;
    _sourceDebounce?.cancel();
    _sourceDebounce = null;
    if (project != null) {
      _settings.rememberProject(project.path);
      _persistSettings();
      _warmDeviceCache();
      _loadCachedComponentSchemas(project);
      _loadPackageManifestSchemas(project);
      _startComponentSourceWatch(project);
    }
  }

  StreamSubscription<FileSystemEvent>? _sourceWatch;
  Timer? _sourceDebounce;

  /// Adopts component schemas shipped by the project's resolved dependencies
  /// (their flutter_scene_components.json manifests), so installing a
  /// component package is enough for the editor to know its types.
  void _loadPackageManifestSchemas(FProject project) {
    try {
      final root = project.resolvedProjectRoot;
      for (final found in scanPackageManifests(
        '$root/.dart_tool/package_config.json',
      )) {
        final schemas = decodeComponentSchemas(found.manifest['schemas']);
        if (schemas.isEmpty) continue;
        for (final schema in schemas) {
          _foreignSchemas[schema.type] = schema;
          _foreignSchemaProvenance[schema.type] = 'package:${found.package}';
        }
        _controller?.adoptForeignSchemas(
          schemas,
          provenance: 'package:${found.package}',
        );
      }
    } catch (_) {
      // Manifest scanning is best effort; the live channel still covers
      // registered packages.
    }
  }

  /// Watches the project's Dart sources; a save re-extracts annotated
  /// components, regenerates their codecs/registrar/manifest, and updates
  /// the editor's schemas, so saving the file is the whole gesture.
  void _startComponentSourceWatch(FProject project) {
    final lib = Directory('${project.resolvedProjectRoot}/lib');
    if (!lib.existsSync()) return;
    unawaited(_runComponentGeneration(project));
    _sourceWatch = lib.watch(recursive: true).listen((event) {
      final path = event.path;
      if (!path.endsWith('.dart') ||
          path.endsWith('.fscene.dart') ||
          path.endsWith('.g.dart')) {
        return;
      }
      _sourceDebounce?.cancel();
      _sourceDebounce = Timer(const Duration(milliseconds: 400), () {
        unawaited(_runComponentGeneration(project));
      });
    });
  }

  // The tier-1 parse is CPU-bound, so it runs on its own isolate. The closure
  // lives in a static method so it captures only [root]; built inline in an
  // instance method it drags `this` into the isolate message, and the MCP
  // server socket `this` holds is unsendable.
  static Future<ProjectGenerationResult> _extractComponents(String root) =>
      Isolate.run(() => generateProjectComponents(root));

  Future<void> _runComponentGeneration(FProject project) async {
    final root = project.resolvedProjectRoot;
    final ProjectGenerationResult result;
    try {
      result = await _extractComponents(root);
    } catch (e) {
      _runner.addLine('Component extraction failed, $e', ConsoleLineKind.error);
      return;
    }
    if (!mounted) return;
    for (final diagnostic in result.diagnostics) {
      _runner.addLine('$diagnostic', ConsoleLineKind.status);
    }
    for (final path in result.filesWritten) {
      _runner.addLine(
        'Generated ${path.substring(root.length + 1)}',
        ConsoleLineKind.status,
      );
    }
    for (final path in result.filesDeleted) {
      _runner.addLine(
        'Removed ${path.substring(root.length + 1)}',
        ConsoleLineKind.status,
      );
    }
    // Types this project's source has yielded before but the sweep stopped
    // yielding were deleted; retire them everywhere. Ownership is tracked in
    // [_sourceOwnedTypes] rather than read from the provenance label, which
    // a Play session's schema fetch overwrites to `live` (the running app
    // keeps the class compiled until its next restart). Types declared by a
    // file that failed to parse this sweep (a mid-edit syntax error) are
    // held, not retired; the next parsing sweep settles them.
    final parseFailed = result.parseFailedPaths.toSet();
    final current = {for (final schema in result.schemas) schema.type};
    final gone = _sourceOwnedTypes
        .difference(current)
        .where((type) => !parseFailed.contains(_componentSourcePaths[type]))
        .toList();
    _sourceOwnedTypes
      ..removeAll(gone)
      ..addAll(current);
    if (gone.isNotEmpty) {
      for (final type in gone) {
        _foreignSchemas.remove(type);
        _foreignSchemaProvenance.remove(type);
        _componentSourcePaths.remove(type);
      }
      _controller?.retireForeignSchemas(gone);
      _pruneSchemaCache(project, gone);
      for (final type in gone) {
        _runner.addLine('Retired component "$type"', ConsoleLineKind.status);
      }
    }
    if (result.schemas.isEmpty) return;
    for (final schema in result.schemas) {
      _foreignSchemas[schema.type] = schema;
      _foreignSchemaProvenance[schema.type] = 'source';
    }
    _componentSourcePaths.addAll(result.sourcePaths);
    _controller?.componentSourcePaths.addAll(result.sourcePaths);
    _controller?.adoptForeignSchemas(result.schemas, provenance: 'source');
  }

  /// Drops [types] from the on-disk schema cache so a deleted component does
  /// not resurrect from it at the next project open.
  void _pruneSchemaCache(FProject project, List<String> types) {
    try {
      final file = File(_schemaCachePath(project));
      if (!file.existsSync()) return;
      final schemas = decodeComponentSchemas(
        jsonDecode(file.readAsStringSync()),
      ).where((schema) => !types.contains(schema.type)).toList();
      file.writeAsStringSync(jsonEncode(encodeComponentSchemas(schemas)));
    } catch (_) {
      // A stale or corrupt cache regenerates on the next live fetch.
    }
  }

  Future<void> _openProject() async {
    const group = XTypeGroup(
      label: 'Flutter Scene project',
      extensions: ['fproject'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    _openProjectPath(file.path);
  }

  void _openProjectPath(String path) {
    final FProject project;
    try {
      project = FProject.load(path);
    } on Exception catch (e) {
      _settings.forgetProject(path);
      _persistSettings();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open project, $e')));
      }
      return;
    }
    _setProject(project);
    unawaited(_openProjectScene(project));
  }

  Future<void> _newProject() async {
    final directory = await getDirectoryPath();
    if (directory == null) return;
    try {
      final project = FProject.createDefault(directory);
      _setProject(project);
      unawaited(_openProjectScene(project));
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  // Through _setProject so the lib/ source watcher and its debounce end with
  // the project instead of generating into a closed one.
  void _closeProject() => _setProject(null);

  /// The MCP `get_project` payload.
  Map<String, Object?>? _projectInfo() {
    final project = _project;
    if (project == null) return null;
    return {
      'projectOpen': true,
      'name': project.name,
      'path': project.path,
      'flutterProjectRoot': project.resolvedProjectRoot,
      if (project.defaultScene != null) 'defaultScene': project.defaultScene,
      'selectedConfigurationId': _selectedBuildConfiguration?.id,
      'selectedDeviceId': _settings.selectedDevices[project.path],
      'configurations': [
        for (final config in project.buildConfigurations)
          {'id': config.id, 'name': config.name, 'mode': config.mode},
      ],
    };
  }

  /// The gated launch context (installation, project, configuration), or a
  /// [FormatException] naming what is missing.
  (FlutterInstallation, FProject, BuildConfiguration) _launchContext() {
    final installation = _settings.selectedInstallation;
    final project = _project;
    final configuration = _selectedBuildConfiguration;
    if (installation == null) {
      throw const FormatException(
        'No Flutter installation is selected (the built-in toolchain cannot '
        'run flutter). Configure one in Settings.',
      );
    }
    if (project == null || configuration == null) {
      throw const FormatException(
        'Open a project and select a build configuration first',
      );
    }
    return (installation, project, configuration);
  }

  /// Starts the selected configuration's build command (the Build button and
  /// the MCP build_project tool).
  Future<bool> _startBuild() async {
    final (installation, project, configuration) = _launchContext();
    unawaited(
      _runner.startBuild(
        installation: installation,
        project: project,
        configuration: configuration,
        device: _selectedDevice,
      ),
    );
    return true;
  }

  /// Launches the Play session (the Play button and the MCP run_project
  /// tool). The session always targets a concrete device.
  Future<bool> _startPlaySession() async {
    final (installation, project, configuration) = _launchContext();
    final device = _selectedDevice;
    if (device == null) {
      throw const FormatException('Select a device in the toolbar');
    }
    return _session.launch(
      installation: installation,
      project: project,
      configuration: configuration,
      device: device,
    );
  }

  void _runTask(ProjectTask task) {
    try {
      final (installation, project, configuration) = _launchContext();
      unawaited(
        _runner.startTask(
          installation: installation,
          project: project,
          configuration: configuration,
          task: task,
          device: _selectedDevice,
        ),
      );
    } on FormatException catch (e) {
      _runner.addLine(e.message, ConsoleLineKind.error);
    }
  }

  bool get _restartOnSceneSave {
    final project = _project;
    return project != null &&
        (_settings.restartOnSceneSave[project.path] ?? false);
  }

  void _toggleRestartOnSceneSave() {
    final project = _project;
    if (project == null) return;
    setState(
      () => _settings.restartOnSceneSave[project.path] = !_restartOnSceneSave,
    );
    _persistSettings();
  }

  /// The scene was written to disk; refresh the running session when the
  /// per-project toggle is on. A debug session patches scenes in place over
  /// the VM service; anything else falls back to a hot restart.
  void _onSceneSaved(String path) {
    if (!_restartOnSceneSave) return;
    if (_session.state != AppSessionState.running) return;
    unawaited(() async {
      if (await _session.reloadScenes()) return;
      await _session.restart(reason: 'save');
    }());
  }

  /// The MCP get_app_state payload.
  Map<String, Object?> _appState() => {
    'state': _session.state.name,
    if (_session.appId != null) 'appId': _session.appId,
    if (_session.active) 'mode': _session.mode,
    if (_session.deviceId != null) 'deviceId': _session.deviceId,
    if (_session.vmServiceUri != null) 'vmServiceUri': _session.vmServiceUri,
    'supportsHotReload': _session.active && _session.supportsHotReload,
    'supportsHotRestart': _session.active && _session.supportsHotRestart,
  };

  void _editBuildConfigs() {
    final project = _project;
    if (project == null) return;
    showBuildConfigDialog(
      context,
      project: project,
      onChanged: () {
        if (mounted) setState(() {});
      },
      previewVariables: (configuration) =>
          _previewVariables(project, configuration),
    );
  }

  /// Live variable values for the config editor's preview panel.
  Map<String, String> _previewVariables(
    FProject project,
    BuildConfiguration configuration,
  ) {
    final installation = _settings.selectedInstallation;
    final device = _selectedDevice;
    if (installation == null) {
      return {
        'PROJECT_ROOT': project.resolvedProjectRoot,
        'MODE': configuration.mode,
      };
    }
    return commandVariables(
      flutterBin: installation.flutterBin,
      dartBin: installation.dartBin,
      sdkRoot: installation.sdkRoot,
      impellerc: installation.resolvedImpellerc,
      projectRoot: project.resolvedProjectRoot,
      configuration: configuration,
      deviceId: device?.id,
      buildTarget: device == null || device.targetPlatform.isEmpty
          ? null
          : device.buildTarget,
    );
  }

  Future<void> _showSettings() => showSettingsDialog(
    context,
    settings: _settings,
    inspector: _inspector,
    buildInfo: _buildInfo,
    onChanged: () {
      _persistSettings();
      if (mounted) setState(() {});
    },
    onSelectionChanged: _onInstallationSelectionChanged,
    onCreateManaged: _buildInfo.isKnown ? _createManagedCheckout : null,
    onDeleteManaged: _deleteManagedCheckout,
  );

  Future<FlutterInstallation?> _createManagedCheckout(
    BuildContext context,
  ) async {
    final job = _managedCheckouts.create(_buildInfo);
    await showManagedCheckoutDialog(context, job);
    if (!job.done) job.cancel();
    final result = job.result;
    if (result != null) _inspector.invalidate(result.flutterBin);
    return result;
  }

  Future<bool> _deleteManagedCheckout(
    BuildContext context,
    FlutterInstallation installation,
  ) async {
    final (cacheBytes, checkoutBytes) = await _managedCheckouts.sizeOf(
      installation,
    );
    if (!context.mounted) return false;
    String gb(int bytes) => (bytes / (1 << 30)).toStringAsFixed(2);
    final confirmed = await showEditorDialog<bool>(
      context,
      builder: (context) => AlertDialog(
        title: const Text('Delete managed checkout?'),
        content: Text(
          '"${installation.name}" will be removed from disk.\n\n'
          'Tool and artifact cache, ${gb(cacheBytes)} GB\n'
          'Git checkout, ${gb(checkoutBytes)} GB\n\n'
          'Recreating it later downloads the caches again (the shared git '
          'mirror is kept).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await _managedCheckouts.delete(installation);
    } on FileSystemException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('Failed to delete the checkout, $e')),
        );
      }
      return false;
    }
    _inspector.invalidate(installation.flutterBin);
    return true;
  }

  EditorController get _requireController {
    final controller = _controller;
    if (controller == null) {
      throw const ToolError(
        'No document is open; call new_document or open_document first',
      );
    }
    return controller;
  }

  void _replaceController(EditorController controller, {String? path}) {
    _configureController(controller);
    final old = _controller;
    setState(() {
      _controller = controller;
      _busy = null;
      _error = null;
    });
    // Route through _setScenePath so every open path (start screen, recents,
    // MCP) gets the project-first hooks (recents, ancestor discovery, last
    // scene).
    _setScenePath(path);
    old?.dispose();
  }

  void _saveDockLayout(String json) {
    _settings.dockLayout = json;
    _persistSettings();
  }

  void _persistGizmoPreferences() {
    _settings.gizmosEnabled = _gizmoPreferences.enabled;
    _settings.hiddenGizmoTypes
      ..clear()
      ..addAll(_gizmoPreferences.hiddenTypes);
    _persistSettings();
  }

  void _persistSettings() {
    try {
      _settingsStore.save(_settings);
    } on FileSystemException {
      // The active in-memory settings remain usable.
    }
  }

  void _rememberScene(String path) {
    _settings.rememberScene(path);
    _persistSettings();
    if (mounted) setState(() {});
  }

  void _forgetRecentScene(String path) {
    setState(() => _settings.forgetScene(path));
    _persistSettings();
  }

  void _forgetRecentProject(String path) {
    setState(() => _settings.forgetProject(path));
    _persistSettings();
  }

  void _clearRecentScenes() {
    if (_settings.recentScenes.isEmpty) return;
    final removed = List.of(_settings.recentScenes);
    setState(() => _settings.recentScenes.clear());
    _persistSettings();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Recent scenes cleared'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() => _settings.restoreRecentScenes(removed));
            _persistSettings();
          },
        ),
      ),
    );
  }

  void _saveNamedLayout(String name, String layout) {
    setState(() => _settings.saveNamedLayout(name, layout));
    _persistSettings();
  }

  void _deleteNamedLayout(String name) {
    setState(() => _settings.deleteNamedLayout(name));
    _persistSettings();
  }

  void _setScenePath(String? path) {
    setState(() => _scenePath = path);
    if (path == null) return;
    _rememberScene(path);
    _resolveProjectForScene(path);
    _recordLastScene(path);
  }

  /// Project-first scene context. A scene opened on its own joins the
  /// nearest ancestor project (opening or switching to it); without one, a
  /// nearby pubspec earns a one-tap offer to initialize a project there.
  void _resolveProjectForScene(String scenePath) {
    final discovery = findSceneProjectContext(scenePath);
    final discovered = discovery.fprojectPath;
    if (discovered != null) {
      if (_project?.path == discovered) return;
      try {
        _setProject(FProject.load(discovered));
      } on Exception catch (e) {
        _runner.addLine(
          'Could not open the scene\'s project ($discovered), $e',
          ConsoleLineKind.error,
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opened project ${_project!.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final pubspecDirectory = discovery.pubspecDirectory;
    if (_project == null && pubspecDirectory != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This scene lives in a Flutter project without an .fproject '
            '($pubspecDirectory)',
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Create project',
            onPressed: () {
              try {
                _setProject(FProject.createDefault(pubspecDirectory));
                _recordLastScene(_scenePath ?? scenePath);
              } on FormatException catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
          ),
        ),
      );
    }
  }

  /// Remembers the open scene as the project's resume point when it lives
  /// under the project root.
  void _recordLastScene(String path) {
    final project = _project;
    if (project == null) return;
    if (!pathIsWithin(project.resolvedProjectRoot, path)) return;
    if (_settings.lastScenes[project.path] == path) return;
    _settings.lastScenes[project.path] = path;
    _persistSettings();
  }

  /// Opens the project's resume scene (per-user last scene, then the
  /// committed defaultScene), or an empty scene so the editor shell appears
  /// even for a scene-less project. A scene already open inside the project
  /// stays.
  Future<void> _openProjectScene(FProject project) async {
    final current = _scenePath;
    if (current != null && pathIsWithin(project.resolvedProjectRoot, current)) {
      return;
    }
    var scenePath = _settings.lastScenes[project.path];
    if (scenePath == null || !File(scenePath).existsSync()) {
      final fallback = project.resolvedDefaultScene;
      scenePath = fallback != null && File(fallback).existsSync()
          ? fallback
          : null;
    }
    if (scenePath != null) {
      final path = scenePath;
      await _load('Opening scene', () => openFscene(path), path: path);
    } else if (_controller == null) {
      await _load('Creating scene', () => EditorController.empty());
    }
  }

  Future<void> _newScene() async {
    await _load('Creating scene', () => EditorController.empty());
  }

  Future<void> _openScene() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Flutter Scene', extensions: ['fscene']),
      ],
    );
    if (file == null) return;
    await _load('Opening scene', () => openFscene(file.path), path: file.path);
  }

  Future<void> _openRecentScene(String path) async {
    await _load('Opening scene', () => openFscene(path), path: path);
  }

  Future<void> _importGltf() async {
    final path = await pickModelPath();
    if (path == null || !mounted) return;
    final options = await showGlbImportOptions(context);
    if (options == null) return;
    await _load(
      'Importing glTF',
      () => importModel(
        path,
        compressTextures: options.compressTextures,
        scale: options.scale,
        upAxis: options.upAxis,
      ),
    );
  }

  Future<void> _load(
    String label,
    Future<EditorController> Function() open, {
    String? path,
  }) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      final ctrl = await open();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      _replaceController(ctrl, path: path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = e.toString();
        });
      }
    }
  }

  // Serves the editor to an agent over a localhost port for the app's whole
  // life. The surface resolves the session per call, so one connection stays
  // valid across New/Open, and the document tools mean an agent can drive a
  // scene start to finish with no clicks in the UI. Connect a client through
  // the stdio bridge:
  //   dart run flutter_scene_mcp:flutter_scene_mcp_connect 7007
  Future<void> _startMcpServer() async {
    try {
      _mcpServer = await serveEditorMcpOverTcp(
        // Mutations route through the controller so agent edits reach the
        // rendered scene (and the panels), not just the document.
        () => EditorToolSurface(
          () => _controller?.session,
          screenshot: () {
            final dpr = View.of(context).devicePixelRatio;
            return viewportScreenshot(_viewportKey, pixelRatio: dpr)();
          },
          windowScreenshot: () {
            final dpr = View.of(context).devicePixelRatio;
            return viewportScreenshot(_windowKey, pixelRatio: dpr)();
          },
          commandRunner: (command, params) =>
              _requireController.run(command, params),
          undoRunner: () async {
            final controller = _requireController;
            final can = controller.history.canUndo;
            await controller.undo();
            return can;
          },
          redoRunner: () async {
            final controller = _requireController;
            final can = controller.history.canRedo;
            await controller.redo();
            return can;
          },
          readCamera: () {
            final pose = _cameraHandle.pose;
            if (pose == null) return null;
            return ViewportCameraPose(
              azimuth: pose.azimuth,
              elevation: pose.elevation,
              radius: pose.radius,
              target: pose.target,
              orthographic: pose.orthographic,
            );
          },
          writeCamera: (pose) => _cameraHandle.setPose(
            azimuth: pose.azimuth,
            elevation: pose.elevation,
            radius: pose.radius,
            target: pose.target,
            orthographic: pose.orthographic,
          ),
          frameNode: (id) {
            final bounds = _requireController.liveNode(id)?.combinedWorldBounds;
            if (bounds == null) return false;
            _cameraHandle.frame(bounds);
            return true;
          },
          nodeBounds: (id) =>
              _requireController.liveNode(id)?.combinedWorldBounds,
          importModel: (path, {parentId, scale = 1.0}) => importLinkedModel(
            _requireController,
            path,
            GlbImportOptions(scale: scale),
            parentId: parentId,
          ),
          importEnvironment: (path, {environmentId}) => importEnvironmentMap(
            _requireController,
            path,
            environmentId: environmentId,
          ),
          newDocument: () async {
            final controller = await EditorController.empty();
            if (!mounted) {
              controller.dispose();
              return;
            }
            _replaceController(controller);
          },
          openDocument: (path) async {
            final EditorController controller;
            try {
              controller = await openFscene(path);
            } on IOException catch (e) {
              throw FormatException('Could not open "$path", $e');
            }
            if (!mounted) {
              controller.dispose();
              return;
            }
            _replaceController(controller, path: path);
          },
          saveDocument: ({path}) async {
            final controller = _requireController;
            final resolved = path ?? _scenePath;
            if (resolved == null) {
              throw const FormatException(
                'The document has never been saved; pass a "path"',
              );
            }
            await saveFscene(controller, resolved);
            controller.setBaseDirectory(File(resolved).parent.path);
            if (mounted) _setScenePath(resolved);
            _onSceneSaved(resolved);
            return resolved;
          },
          openProject: (path) async {
            final FProject project;
            if (FileSystemEntity.isDirectorySync(path)) {
              final existing = Directory(path)
                  .listSync()
                  .whereType<File>()
                  .where((file) => file.path.endsWith('.fproject'))
                  .toList();
              project = existing.isNotEmpty
                  ? FProject.load(existing.first.path)
                  : FProject.createDefault(path);
            } else {
              project = FProject.load(path);
            }
            _setProject(project);
            // Resume the project's scene without holding up the response (a
            // large scene loads for a while).
            unawaited(_openProjectScene(project));
            return _projectInfo()!;
          },
          closeProject: () async => _closeProject(),
          projectInfo: _projectInfo,
          selectBuildConfiguration: (id) async {
            final project = _project;
            if (project == null) {
              throw const FormatException('No project is open');
            }
            if (project.configurationById(id) == null) {
              throw FormatException('No build configuration "$id"');
            }
            setState(
              () => _settings.selectedBuildConfigurations[project.path] = id,
            );
            _persistSettings();
          },
          buildProject: _startBuild,
          runProject: _startPlaySession,
          stopProject: () => _session.stop(),
          hotRestart: () => _session.restart(),
          hotReload: () => _session.restart(fullRestart: false),
          reloadScene: () => _session.reloadScenes(),
          appState: _appState,
          listComponentTypes: () {
            final controller = _requireController;
            return [
              for (final type in controller.componentTypes())
                {
                  'type': type,
                  if (controller.componentSchemaFor(type)?.doc case final doc?)
                    'doc': doc,
                  'provenance':
                      controller.foreignTypeProvenance[type] ?? 'registered',
                },
            ];
          },
          describeComponentType: (type) =>
              _requireController.componentSchemaFor(type)?.toJson(),
          listDevices: ({bool refresh = false}) async {
            final installation = _settings.selectedInstallation;
            if (installation == null) {
              throw const FormatException(
                'No Flutter installation is selected; devices come from '
                'flutter devices against it.',
              );
            }
            final devices = await _deviceCatalog.list(
              installation,
              refresh: refresh,
            );
            if (mounted) setState(() {});
            return {
              'devices': [
                for (final device in devices)
                  {
                    'id': device.id,
                    'name': device.name,
                    'targetPlatform': device.targetPlatform,
                    'emulator': device.emulator,
                  },
              ],
            };
          },
          selectDevice: (id) async {
            final project = _project;
            if (project == null) {
              throw const FormatException('No project is open');
            }
            setState(() => _settings.selectedDevices[project.path] = id);
            _persistSettings();
          },
          readConsole: (tail) => {
            'building': _runner.building,
            'running': _session.active,
            'lines': [
              for (final line
                  in _runner.console.reversed.take(tail).toList().reversed)
                line.text,
            ],
          },
          renderGraphCapture: ({required bool thumbnails, int? maxDimension}) =>
              _renderGraphMcp.capture(
                thumbnails: thumbnails,
                maxDimension: maxDimension,
              ),
          renderGraphImage: _renderGraphMcp.passOutput,
          renderGraphPixel: _renderGraphMcp.readPixel,
          renderGraphScan: _renderGraphMcp.scanForNans,
          listDebugModes: _renderGraphMcp.listModes,
          setDebugMode: _renderGraphMcp.setMode,
        ),
      );
      debugPrint('Editor MCP server listening on 127.0.0.1:7007');
    } on SocketException catch (e) {
      debugPrint('Editor MCP server not started: $e');
    }
  }

  @override
  void dispose() {
    _mcpServer?.close();
    _session.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _windowKey, child: _buildHome(context));

  Widget _buildHome(BuildContext context) {
    final ctrl = _controller;
    if (ctrl != null) {
      return EditorShell(
        controller: ctrl,
        viewportRepaintBoundaryKey: _viewportKey,
        viewportCameraHandle: _cameraHandle,
        gizmoPreferences: _gizmoPreferences,
        currentPath: _scenePath,
        onDocumentPathChanged: _setScenePath,
        recentScenePaths: _settings.recentScenes,
        onRemoveRecentScene: _forgetRecentScene,
        onClearRecentScenes: _clearRecentScenes,
        namedLayouts: _settings.namedLayouts,
        onSaveNamedLayout: _saveNamedLayout,
        onDeleteNamedLayout: _deleteNamedLayout,
        dockLayoutJson: _settings.dockLayout,
        onDockLayoutChanged: _saveDockLayout,
        menuBarLeadingInset: _windowControlsInset,
        onMenuBarDragStart: _startWindowDrag,
        onControllerReplaced: (newCtrl) {
          _configureController(newCtrl);
          final old = _controller;
          setState(() => _controller = newCtrl);
          old?.dispose();
        },
        onShowSettings: _showSettings,
        projectName: _project?.name,
        projectRootDirectory: _project?.resolvedProjectRoot,
        onOpenProject: _openProject,
        onNewProject: _newProject,
        onCloseProject: _closeProject,
        recentProjectPaths: _settings.recentProjects,
        onOpenRecentProject: _openProjectPath,
        onEditBuildConfigs: _project == null ? null : _editBuildConfigs,
        projectRunner: _runner,
        appSession: _session,
        onDocumentSaved: _onSceneSaved,
        trailing: [
          BuildToolbar(
            settings: _settings,
            buildInfo: _buildInfo,
            inspector: _inspector,
            runner: _runner,
            session: _session,
            project: _project,
            selectedConfiguration: _selectedBuildConfiguration,
            onSelectInstallation: (id) {
              if (_settings.selectedInstallationId == id) return;
              setState(() => _settings.selectedInstallationId = id);
              _persistSettings();
              _onInstallationSelectionChanged();
            },
            onSelectConfiguration: (id) {
              final project = _project;
              if (project == null) return;
              setState(
                () => _settings.selectedBuildConfigurations[project.path] = id,
              );
              _persistSettings();
            },
            deviceCatalog: _deviceCatalog,
            selectedDevice: _selectedDevice,
            onSelectDevice: _selectDevice,
            onManageInstallations: _showSettings,
            onEditConfigs: _project == null ? null : _editBuildConfigs,
            onPlay: () {
              // The throw lands in the future, not here; handle it there so
              // launch-blocked errors still reach the console.
              unawaited(
                _startPlaySession().catchError((Object e) {
                  _runner.addLine(
                    e is FormatException ? e.message : '$e',
                    ConsoleLineKind.error,
                  );
                  return false;
                }),
              );
            },
            onRunTask: _runTask,
            restartOnSave: _restartOnSceneSave,
            onToggleRestartOnSave: _project == null
                ? null
                : _toggleRestartOnSceneSave,
          ),
        ],
      );
    }
    // With no native title bar, the start screen offers a drag strip along
    // the window's top edge (the editor's menu bar serves that role later).
    return Stack(
      children: [
        _StartScreen(
          busy: _busy,
          error: _error,
          onNewProject: _newProject,
          onOpenProject: _openProject,
          recentProjects: _settings.recentProjects,
          onOpenRecentProject: _openProjectPath,
          onRemoveRecentProject: _forgetRecentProject,
          onNew: _newScene,
          onOpen: _openScene,
          onImport: _importGltf,
          recentScenes: _settings.recentScenes,
          onOpenRecent: _openRecentScene,
          onRemoveRecent: _forgetRecentScene,
          onClearRecent: _clearRecentScenes,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 28,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => _startWindowDrag(),
          ),
        ),
      ],
    );
  }
}

class _StartScreen extends StatelessWidget {
  const _StartScreen({
    required this.busy,
    required this.error,
    required this.onNewProject,
    required this.onOpenProject,
    required this.recentProjects,
    required this.onOpenRecentProject,
    required this.onRemoveRecentProject,
    required this.onNew,
    required this.onOpen,
    required this.onImport,
    required this.recentScenes,
    required this.onOpenRecent,
    required this.onRemoveRecent,
    required this.onClearRecent,
  });

  final String? busy;
  final String? error;
  final VoidCallback onNewProject;
  final VoidCallback onOpenProject;
  final List<String> recentProjects;
  final ValueChanged<String> onOpenRecentProject;
  final ValueChanged<String> onRemoveRecentProject;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onImport;
  final List<String> recentScenes;
  final ValueChanged<String> onOpenRecent;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 52),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'packages/flutter_scene_editor/assets/flutter_scene_logo.png',
                    width: 104,
                    height: 104,
                    cacheWidth: 208,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Scene Editor',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 28),
                if (busy != null) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(busy!, textAlign: TextAlign.center),
                ] else ...[
                  // A project (an .fproject beside a Flutter app's pubspec)
                  // is the primary entry point; scenes open inside it.
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onOpenProject,
                          icon: const Icon(Icons.folder_special_outlined),
                          label: const Text('Open project'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: onNewProject,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('New project'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onNew,
                          icon: const Icon(Icons.add),
                          label: const Text('New scene'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onOpen,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Open .fscene'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onImport,
                          icon: const Icon(Icons.view_in_ar),
                          label: const Text('Import glTF'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (recentProjects.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Text(
                    'Recent projects',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: recentProjects.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _RecentProjectTile(
                        path: recentProjects[index],
                        onOpen: () =>
                            onOpenRecentProject(recentProjects[index]),
                        onRemove: () =>
                            onRemoveRecentProject(recentProjects[index]),
                      ),
                    ),
                  ),
                ],
                if (recentScenes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(
                        'Recent scenes',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onClearRecent,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: recentScenes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _RecentSceneTile(
                        path: recentScenes[index],
                        onOpen: () => onOpenRecent(recentScenes[index]),
                        onRemove: () => onRemoveRecent(recentScenes[index]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentProjectTile extends StatelessWidget {
  const _RecentProjectTile({
    required this.path,
    required this.onOpen,
    required this.onRemove,
  });

  final String path;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final missing = !file.existsSync();
    final base = file.path.split(Platform.pathSeparator).last;
    final name = base.endsWith('.fproject')
        ? base.substring(0, base.length - '.fproject'.length)
        : base;
    return ListTile(
      dense: true,
      leading: Icon(
        Icons.folder_special_outlined,
        size: 18,
        color: missing
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        missing ? 'Missing  ${file.parent.path}' : file.parent.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Remove from recent projects',
        onPressed: onRemove,
        icon: const Icon(Icons.close, size: 16),
      ),
      onTap: onOpen,
    );
  }
}

class _RecentSceneTile extends StatelessWidget {
  const _RecentSceneTile({
    required this.path,
    required this.onOpen,
    required this.onRemove,
  });

  final String path;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final missing = !file.existsSync();
    return ListTile(
      dense: true,
      leading: Icon(
        missing ? Icons.insert_drive_file_outlined : Icons.description_outlined,
        size: 18,
        color: missing ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(
        file.path.split(Platform.pathSeparator).last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        missing ? 'Missing  ${file.parent.path}' : file.parent.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Remove from recent scenes',
        onPressed: onRemove,
        icon: const Icon(Icons.close, size: 16),
      ),
      onTap: onOpen,
    );
  }
}
