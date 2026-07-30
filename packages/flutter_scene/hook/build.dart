import 'package:hooks/hooks.dart';

import 'package:flutter_gpu_shaders/build.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/base.shaderbundle.json',
      // Registers a data asset on toolchains with Dart data assets enabled
      // (per-project output, hash-tracked); everyone else keeps the pubspec
      // asset. The runtime probes for whichever key shipped.
      assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
      // GLSL ES 3.00 for the OpenGL ES dialect. The radiance sampling uses
      // textureLod, which is core in 300 es; the 1.00 form needs
      // GL_EXT_shader_texture_lod, which software GL stacks (Mesa llvmpipe,
      // Android emulators) reject at compile time. Sets the native GLES
      // floor at OpenGL ES 3.0.
      glesLanguageVersion: 300,
    );
  });
}
