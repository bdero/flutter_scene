import 'package:hooks/hooks.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_scene/build_hooks.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    // Reference the shared corpus through the in-package `assets_src` symlink
    // so each asset is keyed by a path relative to the package root.
    const corpus = [
      'assets_src/two_triangles.glb',
      'assets_src/flutter_logo_baked.glb',
      'assets_src/dash.glb',
      'assets_src/fcar.glb',
    ];
    // The corpus as `.fsceneb` packages, loaded by source path through
    // loadScene.
    buildScenes(
      buildInput: config,
      buildOutput: output,
      inputFilePaths: corpus,
      assetMode: SceneAssetMode.dataAssetsRequired,
      // Store imported textures as compressed KTX2 block payloads so the
      // import -> compress -> render path is exercised in the app (dash's
      // textures shrink the most).
      compressTextures: true,
    );
    // A loose (non-glTF) image cooked into the engine's compressed texture
    // container, loaded by source path through loadTexture (the Logo
    // example's ground).
    buildTextures(
      buildInput: config,
      buildOutput: output,
      textures: ['assets/ground_grid.png'],
      assetMode: TextureAssetMode.dataAssetsRequired,
    );
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/example.shaderbundle.json',
      assetMode: ShaderBundleAssetMode.dataAssetsRequired,
      // Match the engine bundle's GLES dialect (see the flutter_scene hook).
      glesLanguageVersion: 300,
    );
    // Compile .fmat custom materials into a bundle plus a parameter sidecar,
    // consumed by the "Toon (.fmat)" example through loadFmatMaterial. With no
    // explicit list, assets/**/*.fmat is auto-discovered (assets/toon.fmat
    // here). The generated bundle, sidecar, and index are DataAssets, so
    // materials resolve by source path and hot reload without pubspec entries.
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsRequired,
    );
  });
}
