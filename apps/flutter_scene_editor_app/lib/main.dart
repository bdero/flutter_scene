// The main window is created through the framework's experimental windowing
// API (the macOS runner is headless; multi-view mode must be entered before
// any view controller exists, so every window originates from Dart).
// TODO(docking): drop these ignores when the windowing API is stable.
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
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

  @override
  void initState() {
    super.initState();
    final directory = _settingsDirectory();
    _settingsStore = EditorSettingsStore(
      file: File('${directory.path}/settings.json'),
      legacyDockLayoutFile: File('${directory.path}/dock_layout.json'),
    );
    _settings = _settingsStore.load();
    // The MCP server runs for the app's whole life (not per document), so an
    // agent can create or open a document itself and drive the editor
    // start to finish.
    _startMcpServer();
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
  Widget build(BuildContext context) {
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
          final old = _controller;
          setState(() => _controller = newCtrl);
          old?.dispose();
        },
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
