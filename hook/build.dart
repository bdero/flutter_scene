import 'package:flutter_scene_importer/offline_import.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

import 'package:flutter_gpu_shaders/build.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    generateImporterFlatbufferDart();

    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/base.shaderbundle.json',
    );
  });
}
