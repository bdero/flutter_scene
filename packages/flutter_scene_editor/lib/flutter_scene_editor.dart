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
// The launcher: the project gallery the editor opens to.
export 'src/launcher/project_covers.dart'
    show ProjectCoverStore, coverKey, placeholderHue;
export 'src/launcher/project_launcher.dart'
    show LauncherTab, ProjectCard, ProjectCover, ProjectLauncher;
export 'src/launcher/scene_templates.dart'
    show
        SceneTemplate,
        buildEmptyScene,
        buildOutdoorScene,
        buildPlaygroundScene,
        buildStudioScene,
        pickSceneTemplate,
        sceneTemplateById,
        sceneTemplates;
export 'src/launcher/project_library.dart'
    show
        ProjectEntry,
        ProjectLibrary,
        ProjectSort,
        buildProjectLibrary,
        describeAge,
        projectDisplayName,
        readProjectEntry,
        scanForProjects;

export 'src/mcp/render_graph_tools.dart' show RenderGraphMcp;
export 'src/mcp/viewport_capture.dart' show viewportScreenshot;
export 'src/panels/console_panel.dart' show ConsolePanel;
export 'src/project/app_session.dart' show AppSession, AppSessionState;
export 'src/project/build_config_dialog.dart' show showBuildConfigDialog;
export 'src/project/build_toolbar.dart' show BuildToolbar, BuildToolbarPart;
export 'src/project/fproject.dart'
    show
        BuildConfiguration,
        FProject,
        ProjectTask,
        RunParameters,
        SceneProjectContext,
        buildConfigurationTemplate,
        commandVariables,
        defaultBuildConfigurations,
        findSceneProjectContext,
        migrateV1RunCommand,
        pathIsWithin,
        resolveWorkingDirectory,
        substituteCommandVariables,
        tokenizeCommand;
export 'src/project/project_runner.dart'
    show ConsoleLine, ConsoleLineKind, ProjectRunner;
export 'src/project/project_version_check.dart'
    show
        FlutterSceneVersionCheck,
        VersionCheckSeverity,
        checkFlutterSceneVersion;
export 'src/settings/editor_settings.dart'
    show EditorSettings, EditorSettingsStore;
export 'src/settings/managed_checkout_dialog.dart'
    show showManagedCheckoutDialog;
export 'src/settings/open_in_editor.dart'
    show buildEditorInvocation, openSourceInEditor;
export 'src/settings/settings_dialog.dart'
    show SettingsDialog, showSettingsDialog;
export 'src/shell/editor_dialog.dart' show showEditorDialog;
export 'src/toolchains/managed_checkout.dart'
    show
        ManagedCheckoutJob,
        ManagedCheckoutPaths,
        ManagedCheckoutPhase,
        ManagedCheckouts;
export 'src/toolchains/device_catalog.dart' show DeviceCatalog, FlutterDevice;
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
export 'src/viewport/component_gizmos.dart' show GizmoPreferences;
export 'src/viewport/viewport_camera_handle.dart' show ViewportCameraHandle;
export 'src/viewport/viewport_panel.dart' show ViewportPanel;
