/// Build-hook helpers for flutter_scene.
///
/// Call these from your app's `hook/build.dart` at build time: [buildModels]
/// converts glTF (`.glb`) source assets into flutter_scene's `.model` format,
/// and [buildMaterials] compiles `.fmat` custom-material files into a Flutter
/// GPU shader bundle plus a parameter sidecar. In DataAssets mode, the material
/// outputs are registered with the Flutter asset bundle and can be loaded by
/// material name through `loadFmatMaterial`.
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     buildModels(buildInput: config, inputFilePaths: ['assets/dash.glb']);
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
    show buildModels;
export 'src/fmat/build_materials.dart'
    if (dart.library.js_interop) 'src/fmat/build_materials_unsupported.dart'
    show MaterialAssetMode, buildMaterials;
