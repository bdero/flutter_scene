import 'package:hooks/hooks.dart';
import 'package:flutter_scene_importer/build_hooks.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    buildModels(
      buildInput: config,
      inputFilePaths: [
        '../assets_src/two_triangles.glb',
        '../assets_src/flutter_logo_baked.glb',
        '../assets_src/dash.glb',
        '../assets_src/fcar.glb',
      ],
    );
  });
}
