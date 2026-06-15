// A headless MCP server over stdio for editing a `.fscene` scene.
//
// Usage:
//   dart run flutter_scene_mcp [scene.fscene] [--out out.fscene]
//
// With no scene path it starts from an empty scene. An agent connects over
// stdio, reads the scene, and runs editor commands (each one undoable). When
// `--out` is given, the edited scene is written there on a clean disconnect.
//
// This is the headless transport; a running editor app hosts the same
// EditorMcpServer with a live viewport-screenshot provider.

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';

Future<void> main(List<String> args) async {
  String? scenePath;
  String? outPath;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--out') {
      outPath = i + 1 < args.length ? args[++i] : null;
    } else if (!arg.startsWith('-')) {
      scenePath = arg;
    }
  }

  final session = scenePath == null
      ? EditorSession.empty()
      : EditorSession.fromFscene(File(scenePath).readAsStringSync());

  final server = serveOverChannel(
    stdioChannel(input: stdin, output: stdout),
    EditorToolSurface(session),
  );

  await server.done;

  if (outPath != null) {
    File(outPath).writeAsStringSync(session.toFscene());
  }
}
