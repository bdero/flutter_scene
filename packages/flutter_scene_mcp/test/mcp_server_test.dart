import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// Connects an [MCPClient] to an [EditorMcpServer] over in-memory channels and
/// completes the initialize handshake, returning the live server connection.
Future<ServerConnection> _connect(EditorToolSurface surface) async {
  final clientToServer = StreamController<String>();
  final serverToClient = StreamController<String>();
  EditorMcpServer(
    StreamChannel<String>(clientToServer.stream, serverToClient.sink),
    surface,
  );
  final client = MCPClient(
    Implementation(name: 'test client', version: '1.0.0'),
  );
  final server = client.connectServer(
    StreamChannel<String>(serverToClient.stream, clientToServer.sink),
  );
  await server.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  server.notifyInitialized();
  return server;
}

EditorSession _session() =>
    EditorSession(SceneDocument(allocator: IdAllocator(session: 1)));

Map<String, Object?> _text(CallToolResult result) =>
    jsonDecode((result.content.single as TextContent).text)
        as Map<String, Object?>;

void main() {
  group('EditorMcpServer transport', () {
    test('lists the curated bootstrap tools over the protocol', () async {
      final server = await _connect(EditorToolSurface(_session()));
      final tools = (await server.listTools(
        ListToolsRequest(),
      )).tools.map((t) => t.name).toSet();
      expect(tools, containsAll(['describe_scene', 'run_command', 'undo']));
      expect(tools, isNot(contains('screenshot_viewport')));
      await server.shutdown();
    });

    test('runs a command and reflects it in a perception call', () async {
      final server = await _connect(EditorToolSurface(_session()));

      final created = await server.callTool(
        CallToolRequest(
          name: 'run_command',
          arguments: {
            'command': 'createNode',
            'params': {'name': 'Root'},
          },
        ),
      );
      expect(_text(created)['ok'], isTrue);

      final scene = await server.callTool(
        CallToolRequest(name: 'describe_scene'),
      );
      final roots = _text(scene)['roots'] as List;
      expect((roots.single as Map)['name'], 'Root');
      await server.shutdown();
    });

    test('reports a bad command as a tool error, not a crash', () async {
      final server = await _connect(EditorToolSurface(_session()));
      final result = await server.callTool(
        CallToolRequest(name: 'run_command', arguments: {'command': 'nope'}),
      );
      expect(result.isError, isTrue);
      await server.shutdown();
    });

    test(
      'offers and serves the screenshot tool when a provider is set',
      () async {
        final pixels = Uint8List.fromList([1, 2, 3, 4]);
        final surface = EditorToolSurface(
          _session(),
          screenshot: () async =>
              ScreenshotResult(pngBytes: pixels, width: 2, height: 1),
        );
        final server = await _connect(surface);

        final tools = (await server.listTools(
          ListToolsRequest(),
        )).tools.map((t) => t.name).toSet();
        expect(tools, contains('screenshot_viewport'));

        final shot = await server.callTool(
          CallToolRequest(name: 'screenshot_viewport'),
        );
        final image = shot.content.single as ImageContent;
        expect(image.mimeType, 'image/png');
        expect(base64Decode(image.data), pixels);
        await server.shutdown();
      },
    );
  });
}
