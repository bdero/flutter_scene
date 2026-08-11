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
        ViewportCameraPose,
        ViewportScreenshot;

export 'src/controller/editor_controller.dart' show EditorController;
export 'src/io/glb_import_options.dart'
    show GlbImportOptions, ImportUpAxis, showGlbImportOptions;
export 'src/io/scene_io.dart'
    show
        importEnvironmentMap,
        importLinkedModel,
        importModel,
        importModelDocument,
        openFscene,
        pickModelPath,
        pickOpenPath,
        saveFscene;
export 'src/materials/fmat_library.dart'
    show
        EditorFmatLibrary,
        FmatToolchain,
        findFmatToolchain,
        fmatToolchainForInstallation;
export 'src/mcp/viewport_capture.dart' show viewportScreenshot;
export 'src/settings/editor_settings.dart'
    show EditorSettings, EditorSettingsStore;
export 'src/settings/managed_checkout_dialog.dart'
    show showManagedCheckoutDialog;
export 'src/settings/settings_dialog.dart'
    show SettingsDialog, showSettingsDialog;
export 'src/toolchains/managed_checkout.dart'
    show
        ManagedCheckoutJob,
        ManagedCheckoutPaths,
        ManagedCheckoutPhase,
        ManagedCheckouts;
export 'src/toolchains/editor_build_info.dart' show EditorBuildInfo;
export 'src/toolchains/flutter_installation.dart'
    show
        FlutterInstallation,
        InstallationInspector,
        InstallationProbe,
        InstallationSeverity,
        InstallationValidation;
export 'src/shell/editor_shell.dart' show EditorShell;
export 'src/shell/editor_theme.dart'
    show EditorThemeScope, editorDarkTheme, editorForuiDarkTheme;
export 'src/viewport/viewport_camera_handle.dart' show ViewportCameraHandle;
export 'src/viewport/viewport_panel.dart' show ViewportPanel;
