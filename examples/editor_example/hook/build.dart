import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // The shaders and material bundle flutter_scene itself needs.
    await buildEngineAssets(buildInput: input, buildOutput: output);
    // Scenes and materials the example project authors under assets/.
    buildScenes(buildInput: input, buildOutput: output);
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
