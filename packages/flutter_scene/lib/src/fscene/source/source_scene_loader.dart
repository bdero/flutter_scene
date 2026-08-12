/// Debug-only source-direct scene loading.
///
/// A debug app launched with `--dart-define=FLUTTER_SCENE_SOURCE_ROOT=<dir>`
/// (the editor's Play session does this) reads `.fscene`/`.fsceneb` sources
/// straight from that directory instead of the bundled DataAssets, so a
/// scene save is visible to `ext.flutter_scene.reloadScene` without riding a
/// rebuild. Native only; web/wasm resolves to a stub that never activates,
/// keeping dart:io off the web dependency graph.
library;

export 'source_scene_loader_stub.dart'
    if (dart.library.io) 'source_scene_loader_io.dart'
    show
        SceneSourceLoader,
        activeSceneSourceLoader,
        sceneSourceLoadingActive,
        debugSetSceneSourceRoot;
