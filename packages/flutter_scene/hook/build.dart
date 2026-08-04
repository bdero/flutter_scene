import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:flutter_scene/build_hooks.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    // This is also false when Dart data assets are disabled. Runtime loading
    // reports the required Flutter configuration in that case.
    if (!config.config.buildDataAssets) {
      return;
    }
    await buildTargetShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/base.shaderbundle.json',
      // The compiled bundle is tied to this Flutter engine. Keep it as a
      // managed build output rather than a checked-in or pubspec asset.
      assetMode: TargetShaderBundleAssetMode.dataAssetsRequired,
      // GLSL ES 3.00 for the OpenGL ES dialect. The radiance sampling uses
      // textureLod, which is core in 300 es; the 1.00 form needs
      // GL_EXT_shader_texture_lod, which software GL stacks (Mesa llvmpipe,
      // Android emulators) reject at compile time. Sets the native GLES
      // floor at OpenGL ES 3.0.
      glesLanguageVersion: 300,
    );
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      materials: const [
        'assets/materials/physical_opaque.fmat',
        'assets/materials/physical_transmission.fmat',
      ],
      bundleName: 'physical',
      assetMode: MaterialAssetMode.dataAssetsIfAvailable,
    );
  });
}
