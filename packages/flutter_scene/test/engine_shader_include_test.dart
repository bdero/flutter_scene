// A hook that `flutter test` calls in process has no package resolver, so the
// engine's shader include directory comes from the package config above the
// building package instead.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/framework_shaders.dart';
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
