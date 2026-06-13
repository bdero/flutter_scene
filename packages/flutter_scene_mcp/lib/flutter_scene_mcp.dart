/// The MCP tool surface for the flutter_scene editor.
///
/// Exposes the editor's command registry and scene perception to AI agents as
/// a tiered, discoverable set of tools. This library is transport-free and
/// GPU-free; a dart_mcp server wraps [EditorToolSurface] to speak the protocol,
/// and a running editor adds a viewport-screenshot perception tool.
library;

export 'src/tool_surface.dart'
    show ToolDefinition, ToolError, EditorToolSurface;
