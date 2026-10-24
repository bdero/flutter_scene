import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Compiles the benchmark's raw shaders for every backend.
void main(List<String> args) {
  build(args, (input, output) async {
    await buildTargetShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/volume_bench.shaderbundle.json',
      glesLanguageVersion: 300,
    );
  });
}
