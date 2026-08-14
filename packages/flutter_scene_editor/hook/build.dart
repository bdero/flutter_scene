import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:flutter_scene/build_hooks.dart';

/// Compiles the editor's debug shader bundle (the render graph inspector's
/// display remap and the viewport debug-output modes). Build hooks run for
/// every package in the app's dependency graph, so any host embedding the
/// editor UI gets the bundle without app-side hook changes, and consumer
/// apps of flutter_scene never ship it.
void main(List<String> args) async {
  await build(args, (config, output) async {
    // Also false when Dart data assets are disabled; runtime loading
    // reports the required Flutter configuration in that case.
    if (!config.config.buildDataAssets) {
      return;
    }
    await buildTargetShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/editor_debug.shaderbundle.json',
      assetMode: TargetShaderBundleAssetMode.dataAssetsRequired,
      // Matches the engine bundle's GLES floor (see flutter_scene's hook).
      glesLanguageVersion: 300,
    );
  });
}
