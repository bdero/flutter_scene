import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';

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

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final ctrl = await EditorController.empty();
      if (mounted) setState(() => _controller = ctrl);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
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
      onControllerReplaced: (newCtrl) {
        final old = _controller;
        setState(() => _controller = newCtrl);
        old?.dispose();
      },
    );
  }
}
