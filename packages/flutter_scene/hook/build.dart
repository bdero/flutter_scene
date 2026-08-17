import 'package:hooks/hooks.dart';

import 'package:flutter_scene/src/generated_assets/build_engine_assets.dart';

/// Compiles the engine's own shaders for whatever app is being built, so
/// `flutter pub add flutter_scene` is the whole setup. A shader bundle is only
/// valid for the engine that consumes it, so it is compiled here rather than
/// published.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildOwnEngineAssets(buildInput: input, buildOutput: output);
  });
}
