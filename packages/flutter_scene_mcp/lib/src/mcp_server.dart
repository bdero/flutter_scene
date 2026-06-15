/// A `dart_mcp` server that speaks the Model Context Protocol over a
/// [StreamChannel], delegating every call to an [EditorToolSurface].
///
/// The surface is transport-free and GPU-free; this is the thin protocol
/// adapter around it. Run it over stdio (a headless agent editing a
/// `.fscene`) or any other channel a host wires up. Every command runs as a
/// single undoable edit, identical to the same action in the UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:flutter_scene_mcp/src/tool_surface.dart';

/// Wraps an [EditorToolSurface] as an MCP server.
base class EditorMcpServer extends MCPServer with ToolsSupport {
  /// Serves [surface] over [channel].
  EditorMcpServer(super.channel, this.surface, {String version = '0.0.1'})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter_scene_editor',
          version: version,
        ),
        instructions:
            'Edit a flutter_scene 3D scene. Start with describe_scene to see '
            'the node tree, get_node for detail, and search_commands + '
            'run_command to make edits (every command is one undoable step, '
            'identical to the editor UI). Address nodes by slash path '
            '(Root/Cube) first, id token as a fallback.',
      );

  /// The tool surface every call is delegated to.
  final EditorToolSurface surface;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    for (final def in surface.bootstrapTools()) {
      registerTool(
        Tool(
          name: def.name,
          description: def.description,
          inputSchema: ObjectSchema.fromMap(def.inputSchema),
        ),
        // The surface validates and reports its own errors as ToolErrors, so
        // skip dart_mcp's schema validation (the schemas are hand-written
        // JSON, not built ObjectSchemas).
        (request) => _call(def.name, request),
        validateArguments: false,
      );
    }
    return super.initialize(request);
  }

  FutureOr<CallToolResult> _call(String name, CallToolRequest request) async {
    final args = request.arguments ?? const <String, Object?>{};
    try {
      if (name == 'screenshot_viewport') {
        final result = await surface.capture();
        return CallToolResult(
          content: [
            ImageContent(
              data: result['base64'] as String,
              mimeType: result['mimeType'] as String,
            ),
          ],
        );
      }
      final result = surface.dispatch(name, args);
      return CallToolResult(content: [TextContent(text: jsonEncode(result))]);
    } on ToolError catch (e) {
      return CallToolResult(
        content: [TextContent(text: e.message)],
        isError: true,
      );
    }
  }
}

/// Serves [surface] over a newline-delimited stdio [channel] (the shape
/// `stdioChannel` from `package:dart_mcp/stdio.dart` produces). Returns the
/// running server; await its `done` to know when the peer disconnects.
EditorMcpServer serveOverChannel(
  StreamChannel<String> channel,
  EditorToolSurface surface, {
  String version = '0.0.1',
}) => EditorMcpServer(channel, surface, version: version);
