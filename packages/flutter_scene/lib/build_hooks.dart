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

export 'src/importer/build_hooks.dart' show buildModels;
