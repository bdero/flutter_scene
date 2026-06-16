/// The flutter_scene scene editor UI.
///
/// Built in Flutter on top of the headless `flutter_scene_editor_core`, with
/// the viewport rendered by flutter_scene's own renderer. Start with
/// [EditorController] to open or create a scene, then wrap it with
/// [EditorShell] to get the full 4-panel editing surface.
library;

export 'package:flutter_scene_mcp/flutter_scene_mcp.dart'
    show
        EditorMcpServer,
        EditorToolSurface,
        ScreenshotResult,
        ViewportScreenshot;

export 'src/controller/editor_controller.dart' show EditorController;
export 'src/io/glb_import_options.dart'
    show GlbImportOptions, ImportUpAxis, showGlbImportOptions;
export 'src/io/scene_io.dart'
    show importGlb, openFscene, pickGlbPath, pickOpenPath;
export 'src/mcp/viewport_capture.dart' show viewportScreenshot;
export 'src/shell/editor_shell.dart' show EditorShell;
export 'src/viewport/viewport_panel.dart' show ViewportPanel;
