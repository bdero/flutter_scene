import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (input, output) async {
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
      buildInput: input,
      buildOutput: output,
      inputFilePaths: corpus,
      // Store imported textures as compressed KTX2 block payloads so the
      // import -> compress -> render path is exercised in the app (dash's
      // textures shrink the most).
      compressTextures: true,
    );
    // A loose (non-glTF) image cooked into the engine's compressed texture
    // container, loaded by source path through loadTexture (the Logo
    // example's ground).
    buildTextures(
      buildInput: input,
      buildOutput: output,
      textures: ['assets/ground_grid.png'],
    );
    // The hand-written shaders the Raw shader and Toon examples draw with,
    // resolved by bundle name with resolveShaderBundleKey.
    await buildTargetShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/example.shaderbundle.json',
      // Match the engine bundle's GLES dialect.
      glesLanguageVersion: 300,
    );
    // Compile .fmat custom materials into a bundle plus a parameter sidecar,
    // consumed by the "Toon (.fmat)" example through loadFmatMaterial. With no
    // explicit list, assets/**/*.fmat is auto-discovered (assets/toon.fmat
    // here), and materials resolve by source path and hot reload.
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
