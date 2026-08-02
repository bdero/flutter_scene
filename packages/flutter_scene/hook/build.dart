import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:flutter_gpu_shaders/build.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    if (!config.config.buildDataAssets) {
      return;
    }
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/base.shaderbundle.json',
      // The compiled bundle is tied to this Flutter engine. Keep it as a
      // managed build output rather than a checked-in or pubspec asset.
      assetMode: ShaderBundleAssetMode.dataAssetsRequired,
      // GLSL ES 3.00 for the OpenGL ES dialect. The radiance sampling uses
      // textureLod, which is core in 300 es; the 1.00 form needs
      // GL_EXT_shader_texture_lod, which software GL stacks (Mesa llvmpipe,
      // Android emulators) reject at compile time. Sets the native GLES
      // floor at OpenGL ES 3.0.
      glesLanguageVersion: 300,
    );
  });
}
