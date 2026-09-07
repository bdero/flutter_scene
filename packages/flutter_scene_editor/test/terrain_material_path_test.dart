// The one string that ties a painted terrain to the shader that draws it.
//
// The generated material index records a material by its source path relative
// to the package that compiled it, and loadFmatMaterial looks one up by exactly
// that. flutter_scene_editor_core is the headless command core and cannot
// import flutter_scene at runtime, so it spells the path again — and this is
// where the two are held together. They cannot be checked in editor_core, whose
// tests run on the plain VM where flutter_scene's dart:ui imports do not exist.

import 'package:flutter_scene/fscene.dart' show terrainMaterialSource;
// ignore: implementation_imports
import 'package:flutter_scene_editor_core/src/builtin_commands.dart'
    show terrainMaterialAsset;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the command writes the path the engine compiles the material as', () {
    // Drift here fails silently and late: the material resolves to nothing at
    // load, and the terrain draws as though it had no material at all.
    expect(terrainMaterialAsset, terrainMaterialSource);
  });

  test('it is a package-relative source path, not an asset-bundle key', () {
    // A `packages/flutter_scene/...` key is the shape that looks right and
    // resolves to nothing, so it is worth saying which shape this is.
    expect(terrainMaterialAsset, isNot(startsWith('packages/')));
    expect(terrainMaterialAsset, endsWith('.fmat'));
  });
}
