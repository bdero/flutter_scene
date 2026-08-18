// A fresh `flutter create` app has no assets/ directory, so the hook the init
// command writes must build cleanly against one. Declaring a directory that
// does not exist fails the build with "Flutter failed to list directory".

import 'dart:io';

import 'package:flutter_scene/src/fmat/build_materials.dart';
import 'package:flutter_scene/src/fmat/init_command.dart';
import 'package:flutter_scene/src/importer/build_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('missing_assets');
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync(
      'name: example_app\n'
      'environment:\n'
      "  sdk: '>=3.0.0 <5.0.0'\n",
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('buildScenes declares only directories that exist', () {
    final outputBuilder = BuildOutputBuilder();
    buildScenes(buildInput: _buildInput(temp.uri), buildOutput: outputBuilder);

    _expectDirectoriesExist(outputBuilder.build().dependencies);
  });

  test('buildMaterials declares only directories that exist', () async {
    final outputBuilder = BuildOutputBuilder();
    await buildMaterials(
      buildInput: _buildInput(temp.uri),
      buildOutput: outputBuilder,
    );

    _expectDirectoriesExist(outputBuilder.build().dependencies);
  });

  test(
    'the discovery dependency falls back to the nearest existing parent',
    () {
      // Nothing under the package root yet.
      expect(discoveryDependencyDirectory(temp.uri, 'assets/'), temp.uri);
      expect(
        discoveryDependencyDirectory(temp.uri, 'assets/scenes'),
        temp.uri,
        reason: 'a nested root walks all the way up',
      );

      Directory.fromUri(temp.uri.resolve('assets/')).createSync();
      expect(
        discoveryDependencyDirectory(temp.uri, 'assets/scenes/'),
        temp.uri.resolve('assets/'),
      );

      Directory.fromUri(temp.uri.resolve('assets/scenes/')).createSync();
      expect(
        discoveryDependencyDirectory(temp.uri, 'assets/scenes'),
        temp.uri.resolve('assets/scenes/'),
        reason: 'a missing trailing slash resolves the same directory',
      );
    },
  );

  test('the sequence the getting-started docs give builds clean', () async {
    await installFlutterSceneBuildHook(projectRoot: temp);
    expect(
      Directory.fromUri(temp.uri.resolve('assets/')).existsSync(),
      isFalse,
      reason: 'a fresh flutter create app has no assets/',
    );

    // What the hook init writes calls, in the order it calls it.
    final input = _buildInput(temp.uri);
    final outputBuilder = BuildOutputBuilder();
    buildScenes(buildInput: input, buildOutput: outputBuilder);
    await buildMaterials(buildInput: input, buildOutput: outputBuilder);

    _expectDirectoriesExist(outputBuilder.build().dependencies);
  });

  test('a discovered source still declares its own directory', () {
    Directory.fromUri(temp.uri.resolve('assets/')).createSync();
    final outputBuilder = BuildOutputBuilder();
    buildScenes(buildInput: _buildInput(temp.uri), buildOutput: outputBuilder);

    expect(
      outputBuilder.build().dependencies,
      contains(temp.uri.resolve('assets/')),
    );
  });
}

void _expectDirectoriesExist(Iterable<Uri> dependencies) {
  for (final dependency in dependencies) {
    if (!dependency.path.endsWith('/')) continue;
    expect(
      Directory.fromUri(dependency).existsSync(),
      isTrue,
      reason: 'declared a dependency on a missing directory: $dependency',
    );
  }
}

BuildInput _buildInput(Uri packageRoot) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'example_app',
      outputDirectoryShared: packageRoot.resolve('.dart_tool/hook/'),
      outputFile: packageRoot.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  return builder.build();
}
