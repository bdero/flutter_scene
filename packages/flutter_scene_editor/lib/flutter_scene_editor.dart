/// The flutter_scene scene editor UI.
///
/// Built in Flutter on top of the headless `flutter_scene_editor_core`, with
/// the viewport rendered by flutter_scene's own renderer. Start with
/// [EditorController] to open or create a scene, then wrap it with
/// [EditorShell] to get the full 4-panel editing surface.
library;

export 'src/controller/editor_controller.dart' show EditorController;
export 'src/shell/editor_shell.dart' show EditorShell;
