/// Build-hook helpers for flutter_scene.
///
/// Call these from your app's `hook/build.dart` at build time. [buildScenes]
/// converts glTF (`.glb`) and authored `.fscene` sources into flutter_scene's
/// `.fsceneb` package format, [buildMaterials] compiles `.fmat`
/// custom-material files into a Flutter GPU shader bundle plus a parameter
/// sidecar, [buildTextures] cooks loose images into the engine's compressed
/// `.fstex` container, and [buildTargetShaderBundleJson] compiles raw shader
/// manifests without unused platform backends. [buildEngineAssets] is
/// optional, putting the shaders flutter_scene itself needs in this app's
/// generated assets rather than in flutter_scene's own.
///
/// Everything lands in the app's `flutter_scene_generated/` directory and is
/// loaded by source path through `loadScene`/`loadFmatMaterial`/`loadTexture`.
/// `dart run flutter_scene:init` writes this hook and the one pubspec entry the
/// directory needs.
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (input, output) async {
///     buildScenes(buildInput: input, buildOutput: output);
///     await buildMaterials(buildInput: input, buildOutput: output);
///   });
/// }
/// ```
library;

export 'src/native/build_native_components.dart' show buildNativeComponents;

// Native uses the real dart:io implementations; web/wasm resolves to stubs so
// dart:io (and package:hooks) stay off the wasm dependency graph, keeping the
// package WASM-compatible. Build hooks only ever run on the native host.
export 'src/generated_assets/build_engine_assets.dart'
    if (dart.library.js_interop) 'src/generated_assets/build_engine_assets_unsupported.dart'
    show buildEngineAssets;
export 'src/importer/build_hooks.dart'
    if (dart.library.js_interop) 'src/importer/build_hooks_unsupported.dart'
    show SceneAssetMode, buildScenes;
export 'src/fmat/build_materials.dart'
    if (dart.library.js_interop) 'src/fmat/build_materials_unsupported.dart'
    show
        MaterialAssetMode,
        buildMaterials,
        buildTerrainMaterial,
        terrainMaterialSource;
export 'src/fmat/target_shader_bundle.dart'
    if (dart.library.js_interop) 'src/fmat/target_shader_bundle_unsupported.dart'
    show TargetShaderBundleAssetMode, buildTargetShaderBundleJson;
export 'src/texture/build_textures.dart'
    if (dart.library.js_interop) 'src/texture/build_textures_unsupported.dart'
    show TextureAssetMode, buildTextures;
// The per-texture downsample rule accepted by [buildTextures]. Also exported
// by `package:flutter_scene/scene.dart`; re-exported here because hook code
// runs on the plain Dart VM and cannot import the Flutter library.
export 'src/texture/mipmap.dart' show TextureContent;
