// A package's own hook that compiles shaders against the engine's GLSL names
// the engine's include directory and GLSL ES version through build_hooks.dart.
// A hook a `flutter test` calls in process has no package resolver, so the
// directory comes from the package config above the building package instead.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene/build_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('engine_include'));

  tearDown(() => temp.deleteSync(recursive: true));

  test(
    'the engine shader include directory resolves under flutter test',
    () async {
      final engineRoot = Directory.current.absolute.uri;
      final config = File.fromUri(
        temp.uri.resolve('.dart_tool/package_config.json'),
      )..createSync(recursive: true);
      config.writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'flutter_scene',
              'rootUri': engineRoot.toString(),
              'packageUri': 'lib/',
            },
          ],
        }),
      );
      final app = Directory.fromUri(temp.uri.resolve('packages/app/'))
        ..createSync(recursive: true);

      final include = await engineShaderIncludeDirectory(_buildInput(app.uri));

      expect(include, engineRoot.resolve('shaders/'));
      expect(
        File.fromUri(include.resolve('scene_inputs.glsl')).existsSync(),
        isTrue,
      );
    },
  );

  test('the engine compiles its shaders for GLSL ES 3.00', () {
    expect(engineGlesLanguageVersion, 300);
  });
}

BuildInput _buildInput(Uri packageRoot) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'app',
      outputDirectoryShared: packageRoot.resolve('.dart_tool/hook/'),
      outputFile: packageRoot.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  return builder.build();
}
