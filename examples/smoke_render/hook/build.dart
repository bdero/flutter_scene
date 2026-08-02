import 'package:data_assets/data_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    if (!config.config.buildDataAssets) {
      return;
    }
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      materials: ['assets/custom_material.fmat', 'assets/noise_parity.fmat'],
      assetMode: MaterialAssetMode.dataAssetsRequired,
    );
    // The hand-written vertex/fragment pair the raw_shader_pair scene draws
    // with. Compiled here so every backend's compiler sees it.
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/smoke.shaderbundle.json',
      assetMode: ShaderBundleAssetMode.dataAssetsRequired,
      glesLanguageVersion: 300,
    );
  });
}
