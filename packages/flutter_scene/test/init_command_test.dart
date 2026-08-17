import 'dart:io';

import 'package:flutter_scene/src/fmat/init_command.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('flutter_scene_init');
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync(
      'name: app\n\nflutter:\n  uses-material-design: true\n',
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File hookFile() => File.fromUri(temp.uri.resolve('hook/build.dart'));

  test('sets up a project that has nothing yet', () async {
    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.created);
    final contents = hookFile().readAsStringSync();
    expect(contents, contains(hookStartMarker));
    expect(contents, contains('buildScenes('));
    expect(contents, contains('buildMaterials('));
    // flutter_scene's own hook builds the engine's shaders, so an app's hook
    // does not have to.
    expect(contents, isNot(contains('buildEngineAssets(')));
    // Nothing in the normal path mentions data assets.
    expect(contents.toLowerCase(), isNot(contains('dataassets')));
    expect(contents, isNot(contains('enable-dart-data-assets')));

    expect(
      File.fromUri(
        temp.uri.resolve(
          '$generatedAssetsDirectory/$generatedAssetsGitignoreFileName',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(
      parsePubspecAssets(
        File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      ),
      contains(normalizeAssetEntry(generatedAssetsEntry)),
    );
  });

  test('is idempotent', () async {
    await installFlutterSceneBuildHook(projectRoot: temp);
    final hook = hookFile().readAsStringSync();
    final pubspec = File.fromUri(
      temp.uri.resolve('pubspec.yaml'),
    ).readAsStringSync();

    final again = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(again.status, InitHookStatus.alreadyConfigured);
    expect(hookFile().readAsStringSync(), hook);
    expect(
      File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      pubspec,
    );
  });

  test('keeps pubspec comments when adding the entry', () async {
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync('''
name: app

flutter:
  assets:
    # my own assets
    - assets/logo.png
''');
    await installFlutterSceneBuildHook(projectRoot: temp);
    expect(
      File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      '''
name: app

flutter:
  assets:
    # my own assets
    - assets/logo.png
    - $generatedAssetsEntry
''',
    );
  });

  test('refreshes the managed block in a generated hook', () async {
    hookFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
$hookStartMarker
    // stale contents
$hookEndMarker
  });
}
''');

    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.updated);
    final contents = hookFile().readAsStringSync();
    expect(contents, isNot(contains('stale contents')));
    expect(contents, contains('buildScenes('));
  });

  test('leaves a foreign hook alone and prints what to paste', () async {
    hookFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');

    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.needsManualInstall);
    expect(hookFile().readAsStringSync(), 'void main() {}\n');
    expect(
      result.message,
      allOf(
        contains('Add this call to your existing hook/build.dart'),
        contains(generatedAssetsEntry),
      ),
    );
  });

  test(
    'recognizes a hand-written hook that already calls the builders',
    () async {
      hookFile()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'package:flutter_scene/build_hooks.dart';\n"
          'void main(List<String> args) async {\n'
          '  await buildEngineAssets(buildInput: i, buildOutput: o);\n'
          '}\n',
        );

      final result = await installFlutterSceneBuildHook(projectRoot: temp);

      expect(result.status, InitHookStatus.alreadyConfigured);
    },
  );

  test('adds the entry to an inline assets list', () async {
    File.fromUri(
      temp.uri.resolve('pubspec.yaml'),
    ).writeAsStringSync('name: app\nflutter:\n  assets: [assets/logo.png]\n');

    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.created);
    expect(
      parsePubspecAssets(
        File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      ),
      contains(normalizeAssetEntry(generatedAssetsEntry)),
    );
  });
}
