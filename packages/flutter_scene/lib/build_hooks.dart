/// Build-hook helpers for flutter_scene.
///
/// Call these from your app's `hook/build.dart` at build time: [buildScenes]
/// converts glTF (`.glb`) source assets into flutter_scene's `.fsceneb`
/// package format (loaded by source path with `loadScene`), [buildMaterials]
/// compiles `.fmat` custom-material files into a Flutter GPU shader bundle
/// plus a parameter sidecar, and [buildTextures] cooks loose images into the
/// engine's compressed `.fstex` texture container. In DataAssets mode, the
/// outputs are registered with the Flutter asset bundle and can be loaded by
/// source path through `loadScene` / `loadFmatMaterial` / `loadTexture`.
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     buildScenes(
///       buildInput: config,
///       buildOutput: output,
///       assetMode: SceneAssetMode.dataAssetsRequired,
///     );
///     await buildMaterials(
///       buildInput: config,
///       buildOutput: output,
///       materials: ['materials/toon.fmat'],
///     );
///   });
/// }
/// ```
library;

// Native uses the real dart:io implementations; web/wasm resolves to stubs so
// dart:io (and package:hooks) stay off the wasm dependency graph, keeping the
// package WASM-compatible. Build hooks only ever run on the native host.
export 'src/importer/build_hooks.dart'
    if (dart.library.js_interop) 'src/importer/build_hooks_unsupported.dart'
    show SceneAssetMode, buildScenes;
export 'src/fmat/build_materials.dart'
    if (dart.library.js_interop) 'src/fmat/build_materials_unsupported.dart'
    show MaterialAssetMode, buildMaterials;
export 'src/texture/build_textures.dart'
    if (dart.library.js_interop) 'src/texture/build_textures_unsupported.dart'
    show TextureAssetMode, buildTextures;
// The per-texture downsample rule accepted by [buildTextures]. Also exported
// by `package:flutter_scene/scene.dart`; re-exported here because hook code
// runs on the plain Dart VM and cannot import the Flutter library.
export 'src/texture/mipmap.dart' show TextureContent;
