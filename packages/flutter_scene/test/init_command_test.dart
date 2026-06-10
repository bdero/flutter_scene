import 'dart:io';

import 'package:flutter_scene/src/fmat/init_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a DataAssets build hook in a project without one', () async {
    final temp = Directory.systemTemp.createTempSync('flutter_scene_init');
    try {
      final result = await installFlutterSceneBuildHook(projectRoot: temp);
      final hook = File.fromUri(temp.uri.resolve('hook/build.dart'));

      expect(result.status, InitHookStatus.created);
      expect(hook.existsSync(), isTrue);
      final contents = hook.readAsStringSync();
      expect(contents, contains(hookStartMarker));
      expect(contents, contains('MaterialAssetMode.dataAssetsRequired'));
      expect(contents, contains('buildScenes('));
      expect(contents, contains('SceneAssetMode.dataAssetsRequired'));
      expect(contents, isNot(contains('flutter.assets')));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('updates the managed block in an existing generated hook', () async {
    final temp = Directory.systemTemp.createTempSync('flutter_scene_init');
    try {
      final hook = File.fromUri(temp.uri.resolve('hook/build.dart'));
      hook.createSync(recursive: true);
      hook.writeAsStringSync('''
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
      final contents = hook.readAsStringSync();
      expect(contents, isNot(contains('stale contents')));
      expect(
        contents,
        contains('assetMode: MaterialAssetMode.dataAssetsRequired'),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test(
    'leaves custom hooks untouched and prints manual instructions',
    () async {
      final temp = Directory.systemTemp.createTempSync('flutter_scene_init');
      try {
        final hook = File.fromUri(temp.uri.resolve('hook/build.dart'));
        hook.createSync(recursive: true);
        hook.writeAsStringSync('void main() {}\n');

        final result = await installFlutterSceneBuildHook(projectRoot: temp);

        expect(result.status, InitHookStatus.needsManualInstall);
        expect(hook.readAsStringSync(), 'void main() {}\n');
        expect(
          result.message,
          contains('Add this call to your existing hook/build.dart'),
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
  );
}
