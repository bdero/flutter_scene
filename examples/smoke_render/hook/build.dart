import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Builds this app's own assets as Dart data assets instead of into the generated
/// tree when the workspace pubspec declares `hooks: user_defines: smoke_render:
/// data_assets: true`, so the opt-in path stays covered by the smoke matrix.
/// buildEngineAssets keeps the engine's own shaders in this app's tree, which
/// is the app-side override of what flutter_scene's hook builds by default.
void main(List<String> args) {
  build(args, (input, output) async {
    final dataAssetsLane = input.userDefines['data_assets'] == true;
    await buildEngineAssets(buildInput: input, buildOutput: output);
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      materials: [
        'assets/custom_material.fmat',
        'assets/instance_grid.fmat',
        'assets/noise_parity.fmat',
        'assets/planar_mirror.fmat',
        'assets/decal.fmat',
      ],
      assetMode: dataAssetsLane
          ? MaterialAssetMode.dataAssetsRequired
          : MaterialAssetMode.generatedTree,
    );
    // The hand-written vertex/fragment pair the raw_shader_pair scene draws
    // with. Compiled here so every backend's compiler sees it.
    await buildTargetShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/smoke.shaderbundle.json',
      assetMode: dataAssetsLane
          ? TargetShaderBundleAssetMode.dataAssetsRequired
          : TargetShaderBundleAssetMode.generatedTree,
      glesLanguageVersion: 300,
    );
  });
}
