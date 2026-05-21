/// Build-hook helpers for flutter_scene.
///
/// Call [buildModels] from your app's `hook/build.dart` to convert glTF
/// (`.glb`) source assets into flutter_scene's `.model` format at build time:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     buildModels(buildInput: config, inputFilePaths: ['assets/dash.glb']);
///   });
/// }
/// ```
library;

// Native uses the real dart:io implementation; web/wasm resolves to a stub so
// dart:io (and package:hooks) stay off the wasm dependency graph, keeping the
// package WASM-compatible. Build hooks only ever run on the native host.
export 'src/importer/build_hooks.dart'
    if (dart.library.js_interop) 'src/importer/build_hooks_unsupported.dart'
    show buildModels;
