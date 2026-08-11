// The main window is created through the framework's experimental windowing
// API (the macOS runner is headless; multi-view mode must be entered before
// any view controller exists, so every window originates from Dart).
// TODO(docking): drop these ignores when the windowing API is stable.
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart' show ToolError;
import 'package:flutter_scene_mcp/socket_host.dart';

void main() {
  if (!isWindowingEnabled) {
    // The runner creates no window of its own, so without the flag there is
    // nothing to render into.
    stderr.writeln(
      'The Flutter Scene Editor requires the windowing feature. '
      'Run "flutter config --enable-windowing" and rebuild.',
    );
    exit(1);
  }
  WidgetsFlutterBinding.ensureInitialized();
  final controller = WindowController(
    size: const Size(1280, 800),
    // The runner styles the window with a hidden title bar by this title
    // (see AppDelegate.swift); keep the two in sync.
    title: 'Scene Editor',
    delegate: _MainWindowDelegate(),
  );
  runWidget(
    Window(controller: controller, child: const FlutterSceneEditorApp()),
  );
}

/// Quits the app when the main editor window closes, taking any floating
/// panel windows with it.
class _MainWindowDelegate with WindowControllerDelegate {
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
    final directory = _settingsDirectory();
    _settingsStore = EditorSettingsStore(
      file: File('${directory.path}/settings.json'),
      legacyDockLayoutFile: File('${directory.path}/dock_layout.json'),
    );
    _settings = _settingsStore.load();
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

  // Build/run subprocess owner, feeding the Console panel. One per app so
  // console history survives project and scene swaps.
  final ProjectRunner _runner = ProjectRunner();

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
    if (project != null) {
      _settings.rememberProject(project.path);
      _persistSettings();
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
    try {
      _setProject(FProject.load(path));
    } on Exception catch (e) {
      _settings.forgetProject(path);
      _persistSettings();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open project, $e')));
      }
    }
  }

  Future<void> _newProject() async {
    final directory = await getDirectoryPath();
    if (directory == null) return;
    try {
      _setProject(FProject.createDefault(directory));
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _closeProject() => setState(() => _project = null);

  /// The MCP `get_project` payload.
  Map<String, Object?>? _projectInfo() {
    final project = _project;
    if (project == null) return null;
    return {
      'projectOpen': true,
      'name': project.name,
      'path': project.path,
      'flutterProjectRoot': project.resolvedProjectRoot,
      'selectedConfigurationId': _selectedBuildConfiguration?.id,
      'configurations': [
        for (final config in project.buildConfigurations)
          {
            'id': config.id,
            'name': config.name,
            'platform': config.platform,
            'mode': config.mode,
          },
      ],
    };
  }

  /// Starts the selected configuration over MCP, mirroring the toolbar's
  /// gating (a real installation, a project, a configuration).
  Future<bool> _startFromMcp({required bool run}) async {
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
    if (run) {
      unawaited(
        _runner.startRun(
          installation: installation,
          project: project,
          configuration: configuration,
        ),
      );
    } else {
      unawaited(
        _runner.startBuild(
          installation: installation,
          project: project,
          configuration: configuration,
        ),
      );
    }
    return true;
  }

  void _editBuildConfigs() {
    final project = _project;
    if (project == null) return;
    showBuildConfigDialog(
      context,
      project: project,
      onChanged: () {
        if (mounted) setState(() {});
      },
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
    final confirmed = await showDialog<bool>(
      context: context,
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
      _scenePath = path;
      _busy = null;
      _error = null;
    });
    if (path != null) _rememberScene(path);
    old?.dispose();
  }

  void _saveDockLayout(String json) {
    _settings.dockLayout = json;
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
    if (path != null) _rememberScene(path);
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
          buildProject: () => _startFromMcp(run: false),
          runProject: () => _startFromMcp(run: true),
          stopProject: () async => _runner.stopRun(),
          readConsole: (tail) => {
            'building': _runner.building,
            'running': _runner.running,
            'lines': [
              for (final line
                  in _runner.console.reversed.take(tail).toList().reversed)
                line.text,
            ],
          },
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
        onOpenProject: _openProject,
        onNewProject: _newProject,
        onCloseProject: _closeProject,
        recentProjectPaths: _settings.recentProjects,
        onOpenRecentProject: _openProjectPath,
        onEditBuildConfigs: _project == null ? null : _editBuildConfigs,
        projectRunner: _runner,
        trailing: [
          BuildToolbar(
            settings: _settings,
            buildInfo: _buildInfo,
            inspector: _inspector,
            runner: _runner,
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
            onManageInstallations: _showSettings,
            onEditConfigs: _project == null ? null : _editBuildConfigs,
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
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
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
                if (recentScenes.isNotEmpty) ...[
                  const SizedBox(height: 32),
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
                    constraints: const BoxConstraints(maxHeight: 360),
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
