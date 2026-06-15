import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_mcp/socket_host.dart';

void main() {
  runApp(const FlutterSceneEditorApp());
}

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
      title: 'Flutter Scene Editor',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
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
  ServerSocket? _mcpServer;

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
    await _load('Opening scene', () async {
      final source = await File(file.path).readAsString();
      return EditorController.fromFscene(
        source,
        baseDirectory: File(file.path).parent.path,
      );
    });
  }

  Future<void> _importGltf() async {
    final path = await pickGlbPath();
    if (path == null || !mounted) return;
    final options = await showGlbImportOptions(context);
    if (options == null) return;
    await _load(
      'Importing glTF',
      () => importGlb(path, compressTextures: options.compressTextures),
    );
  }

  Future<void> _load(
    String label,
    Future<EditorController> Function() open,
  ) async {
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
      setState(() {
        _controller = ctrl;
        _busy = null;
      });
      await _ensureMcpServer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = e.toString();
        });
      }
    }
  }

  // Serves the live editor to an agent over a localhost port. The surface is
  // built per connection from the current controller, so it always targets
  // the scene on screen and can screenshot the viewport. Connect a client
  // through the stdio bridge:
  //   dart run flutter_scene_mcp:flutter_scene_mcp_connect 7007
  Future<void> _ensureMcpServer() async {
    if (_mcpServer != null) return;
    try {
      final dpr = View.of(context).devicePixelRatio;
      _mcpServer = await serveEditorMcpOverTcp(
        () => EditorToolSurface(
          _controller!.session,
          screenshot: viewportScreenshot(_viewportKey, pixelRatio: dpr),
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
        onControllerReplaced: (newCtrl) {
          final old = _controller;
          setState(() => _controller = newCtrl);
          old?.dispose();
        },
      );
    }
    return _StartScreen(
      busy: _busy,
      error: _error,
      onNew: _newScene,
      onOpen: _openScene,
      onImport: _importGltf,
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
  });

  final String? busy;
  final String? error;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Flutter Scene Editor',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 32),
              if (busy != null) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(busy!, textAlign: TextAlign.center),
              ] else ...[
                FilledButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add),
                  label: const Text('New scene'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open .fscene'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.view_in_ar),
                  label: const Text('Import glTF (.glb)'),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 24),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
