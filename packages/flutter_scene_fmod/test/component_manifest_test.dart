// Keeps the shipped component manifest in sync with the registered codecs,
// so the editor's package-manifest scan always matches this version's
// schemas. Regenerate with
// flutter test --dart-define=UPDATE_COMPONENT_MANIFEST=true \
//   test/component_manifest_test.dart

import 'dart:io';

import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';
import 'package:flutter_scene_fmod/flutter_scene_fmod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_scene_components.json matches the registered codecs', () {
    final expected =
        '${encodeComponentManifest(schemas: [FmodEventCodec().schema], registrarLibrary: 'package:flutter_scene_fmod/flutter_scene_fmod.dart', registrarFunction: 'registerFmodComponentCodecs')}\n';
    final file = File('flutter_scene_components.json');
    if (const bool.fromEnvironment('UPDATE_COMPONENT_MANIFEST')) {
      file.writeAsStringSync(expected);
    }
    expect(
      file.existsSync() ? file.readAsStringSync() : null,
      expected,
      reason: 'regenerate with --dart-define=UPDATE_COMPONENT_MANIFEST=true',
    );
  });
}
