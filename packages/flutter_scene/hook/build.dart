import 'package:hooks/hooks.dart';

import 'package:flutter_gpu_shaders/build.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/base.shaderbundle.json',
      // GLSL ES 3.00 for the OpenGL ES dialect. The radiance sampling uses
      // textureLod, which is core in 300 es; the 1.00 form needs
      // GL_EXT_shader_texture_lod, which software GL stacks (Mesa llvmpipe,
      // Android emulators) reject at compile time. Sets the native GLES
      // floor at OpenGL ES 3.0.
      glesLanguageVersion: 300,
    );
  });
}
