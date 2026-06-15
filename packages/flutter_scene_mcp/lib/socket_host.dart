/// TCP hosting for the editor MCP server, for a running GUI editor.
///
/// Kept out of the main `flutter_scene_mcp.dart` barrel so that library stays
/// free of `dart:io` and usable on the web; import this only from a desktop
/// host that serves its live session to an agent.
library;

export 'src/socket_host.dart' show serveEditorMcpOverTcp;
