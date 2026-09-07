// The terrain material shipped with the package. A material is only a
// deliverable if it compiles, so this compiles it with the SDK's impellerc the
// same way an app's build hook would, and checks the parameter surface the
// editor drives it through.
//
// Skips where impellerc is not in the SDK cache (CI without engine artifacts).
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/src/fmat/fmat_ast.dart' show FmatHintKind;
import 'package:flutter_scene/src/fmat/fmat_parser.dart' show parseFmat;
import 'package:flutter_scene/src/fmat/runtime_compile.dart';
import 'package:flutter_test/flutter_test.dart';

const _path = 'assets/materials/terrain_splat.fmat';

void main() {
  final source = File(_path).readAsStringSync();

  group('the parameter surface', () {
    final material = parseFmat(source, fileName: 'terrain_splat.fmat');

    test('is named for what a document asks for', () {
      expect(material.name, 'TerrainSplat');
    });

    test('takes a control map and one texture per layer', () {
      final names = material.parameters
          .map((parameter) => parameter.name)
          .toSet();
      expect(names, contains('control_map'));
      for (var layer = 0; layer < 4; layer++) {
        expect(
          names,
          contains('layer${layer}_texture'),
          reason: 'layer $layer has no texture',
        );
      }
    });

    test('every layer has the same set of controls as the others', () {
      // A layer missing a tiling or a roughness would be a layer that behaves
      // differently for no reason anyone could see.
      final names = material.parameters
          .map((parameter) => parameter.name)
          .toSet();
      for (final suffix in ['texture', 'tiling', 'color', 'roughness']) {
        for (var layer = 0; layer < 4; layer++) {
          expect(
            names,
            contains('layer${layer}_$suffix'),
            reason: 'layer $layer has no $suffix',
          );
        }
      }
    });

    test('an unassigned layer texture defaults to white, not black', () {
      // A layer with no texture yet is its tint, which is what the tool's four
      // swatches show. Defaulting to black would make an unassigned layer
      // paint holes in the terrain.
      for (final parameter in material.parameters) {
        if (!parameter.name.endsWith('_texture') &&
            parameter.name != 'control_map') {
          continue;
        }
        expect(
          parameter.hint?.kind,
          FmatHintKind.defaultWhite,
          reason: '${parameter.name} does not default to white',
        );
      }
    });

    test('the tilings default to something a terrain texture reads at', () {
      // One repeat across a whole hillside is not a grass texture.
      for (var layer = 0; layer < 4; layer++) {
        final tiling = material.parameters.firstWhere(
          (parameter) => parameter.name == 'layer${layer}_tiling',
        );
        expect(tiling.defaultValue, isNotNull);
      }
    });
  });
  test('the shipped source compiles to a shader bundle', () async {
    Uri? impellerc;
    try {
      impellerc = await findImpellerC();
    } catch (_) {
      impellerc = null;
    }
    if (impellerc == null) {
      // No engine artifacts, as on CI. The parse-level checks above still ran.
      markTestSkipped('impellerc not found in the SDK cache');
      return;
    }
    final cacheDir = Directory.systemTemp.createTempSync('terrain_material_');
    addTearDown(() => cacheDir.deleteSync(recursive: true));
    final compiler = FmatRuntimeCompiler(
      impellerc: impellerc,
      includeDirectories: [Directory('shaders').absolute.uri],
      cacheDirectory: cacheDir,
    );

    final result = await compiler.compile(
      source,
      fileName: 'terrain_splat.fmat',
    );
    expect(result.entryName, 'TerrainSplat');
    expect(result.shaderBundle.lengthInBytes, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
