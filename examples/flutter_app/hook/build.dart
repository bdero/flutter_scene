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
    // Compile the .fmat custom material into its own bundle plus a parameter
    // sidecar, consumed by the "Toon (.fmat)" example through
    // PreprocessedMaterial. Produces build/shaderbundles/materials.shaderbundle
    // and materials.fmat.json (both listed as assets in pubspec.yaml).
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      materials: ['materials/toon.fmat'],
    );
  });
}
