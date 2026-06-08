import 'package:hooks/hooks.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_scene/build_hooks.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    buildModels(
      buildInput: config,
      buildOutput: output,
      // Reference the shared corpus through the in-package `assets_src` symlink
      // so each model is keyed by a path relative to the package root.
      inputFilePaths: [
        'assets_src/two_triangles.glb',
        'assets_src/flutter_logo_baked.glb',
        'assets_src/dash.glb',
        'assets_src/fcar.glb',
      ],
      assetMode: ModelAssetMode.dataAssetsIfAvailable,
    );
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/example.shaderbundle.json',
    );
    // Compile .fmat custom materials into a bundle plus a parameter sidecar,
    // consumed by the "Toon (.fmat)" example through loadFmatMaterial. With no
    // explicit list, assets/**/*.fmat is auto-discovered (assets/toon.fmat
    // here). dataAssetsIfAvailable registers the bundle, sidecar, and index as
    // DataAssets (so materials resolve by source path and hot reload), falling
    // back to the legacy build/shaderbundles/* files otherwise.
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsIfAvailable,
    );
  });
}
