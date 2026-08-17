import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // The shaders and material bundle flutter_scene itself needs. This app has
    // no assets of its own; the scenarios build their geometry in code.
    await buildEngineAssets(buildInput: input, buildOutput: output);
  });
}
