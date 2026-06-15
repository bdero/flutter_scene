// Bridges an MCP client's stdio to a running editor's TCP MCP server.
//
// Usage:
//   dart run flutter_scene_mcp:flutter_scene_mcp_connect [port]
//
// An MCP client (Claude Code, the MCP Inspector, ...) launches this and talks
// over stdio; it forwards bytes to and from the editor listening on
// 127.0.0.1:[port] (default 7007, the serveEditorMcpOverTcp default). Run the
// editor first.

import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 7007;
  final Socket socket;
  try {
    socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  } on SocketException catch (e) {
    stderr.writeln(
      'Could not connect to the editor on port $port. Is it running? ($e)',
    );
    exitCode = 1;
    return;
  }
  socket.setOption(SocketOption.tcpNoDelay, true);

  // Editor -> client, and client -> editor. When either side closes, tear the
  // bridge down so the client process exits.
  socket.listen(
    stdout.add,
    onDone: () async {
      await stdout.flush();
      exit(0);
    },
    onError: (_) => exit(1),
  );
  stdin.listen(
    socket.add,
    onDone: () => socket.destroy(),
    onError: (_) => socket.destroy(),
  );

  await socket.done;
}
