/// The flutter_scene scene editor UI.
///
/// Built in Flutter on top of the headless `flutter_scene_editor_core`, with
/// the viewport rendered by flutter_scene's own renderer. The entry point is
/// [EditorController] (the bridge to a live scene) and the editor widgets.
library;

export 'src/controller/editor_controller.dart' show EditorController;
