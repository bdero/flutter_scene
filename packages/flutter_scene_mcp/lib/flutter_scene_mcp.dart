/// The MCP tool surface for the flutter_scene editor.
///
/// [EditorToolSurface] exposes the editor's command registry and scene
/// perception to AI agents as a tiered, discoverable set of tools; it is
/// transport-free and GPU-free. [EditorMcpServer] wraps it in a `dart_mcp`
/// server to speak the protocol over any channel (stdio, a socket). A running
/// editor passes a [ViewportScreenshot] so agents can also see the rendered
/// viewport.
library;

export 'src/mcp_server.dart' show EditorMcpServer, serveOverChannel;
export 'src/tool_surface.dart'
    show
        EditorToolSurface,
        ScreenshotResult,
        ToolDefinition,
        ToolError,
        ViewportCameraPose,
        ViewportCameraRead,
        ViewportCameraWrite,
        ViewportFrameNode,
        ViewportScreenshot;
