import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_mcp/socket_host.dart';

void main() {
  runApp(const EditorApp());
}

/// Root app: opens an empty scene and drives the [EditorShell].
class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scene Editor',
      theme: ThemeData.dark(useMaterial3: true),
      home: const _EditorLoader(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _EditorLoader extends StatefulWidget {
  const _EditorLoader();

  @override
  State<_EditorLoader> createState() => _EditorLoaderState();
}

class _EditorLoaderState extends State<_EditorLoader> {
  EditorController? _controller;
  String? _error;

  // Key on the viewport's RepaintBoundary so the MCP screenshot tool can
  // capture exactly what the user sees.
  final _viewportKey = GlobalKey();
  ServerSocket? _mcpServer;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final ctrl = await EditorController.empty();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _controller = ctrl);
      await _startMcpServer();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // Serves the live editor to an agent over a localhost port. Each connection
  // gets a surface over the current controller's session plus a viewport
  // screenshot provider. Connect an MCP client through the stdio bridge:
  //   dart run flutter_scene_mcp:flutter_scene_mcp_connect 7007
  Future<void> _startMcpServer() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      _mcpServer = await serveEditorMcpOverTcp(
        () => EditorToolSurface(
          _controller!.session,
          screenshot: viewportScreenshot(_viewportKey, pixelRatio: dpr),
        ),
      );
      debugPrint('Editor MCP server listening on 127.0.0.1:7007');
    } on SocketException catch (e) {
      // A stale instance may already hold the port; the editor still runs.
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
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    if (ctrl == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
}
