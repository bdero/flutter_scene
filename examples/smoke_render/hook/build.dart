import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      materials: ['assets/custom_material.fmat', 'assets/noise_parity.fmat'],
    );
  });
}
