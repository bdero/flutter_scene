import 'dart:io';

import 'package:dart_mcp/stdio.dart';

import 'package:flutter_scene_mcp/src/mcp_server.dart';
import 'package:flutter_scene_mcp/src/tool_surface.dart';

/// Hosts an [EditorMcpServer] over a localhost TCP port so an external agent
/// can drive the running editor. Each accepted connection gets its own server
/// over a fresh [EditorToolSurface] from [surfaceFactory], so a connection
/// always targets the editor's current session (which a host may replace when
/// the user opens a different scene) and its viewport-screenshot provider.
///
/// A GUI app cannot speak the protocol over stdio (its stdout is the
/// framework's), so it listens here and a tiny stdio proxy bridges an MCP
/// client to the port (see `bin/flutter_scene_mcp_connect.dart`). Defaults to
/// the loopback address so the port is not exposed off the machine.
///
/// Returns the listening [ServerSocket]; close it to stop accepting clients.
Future<ServerSocket> serveEditorMcpOverTcp(
  EditorToolSurface Function() surfaceFactory, {
  InternetAddress? address,
  int port = 7007,
}) async {
  final server = await ServerSocket.bind(
    address ?? InternetAddress.loopbackIPv4,
    port,
  );
  server.listen((socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final channel = stdioChannel(input: socket, output: socket);
    EditorMcpServer(channel, surfaceFactory());
  });
  return server;
}
