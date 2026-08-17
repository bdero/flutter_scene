import 'dart:io';

import '../generated_assets/generated_assets.dart';
import '../generated_assets/generated_tree.dart';

const String hookStartMarker = '// flutter_scene:init:start';
const String hookEndMarker = '// flutter_scene:init:end';

const String _hookSnippet =
    '''
$hookStartMarker
    // Import .glb and .fscene sources under assets/, loadable by source path
    // with loadScene (and hot-reloadable). A no-op when there are no scenes.
    buildScenes(buildInput: input, buildOutput: output);
    // Compile .fmat materials under assets/, loadable by source path with
    // loadFmatMaterial (and hot-reloadable). A no-op when there are none.
    await buildMaterials(buildInput: input, buildOutput: output);
$hookEndMarker''';

const String generatedBuildHook =
    '''
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
$_hookSnippet
  });
}
''';

const String manualInstallInstructions =
    '''
Add this call to your existing hook/build.dart:

$_hookSnippet

Then list the generated directory in pubspec.yaml:

$generatedAssetsPubspecSnippet
''';

enum InitHookStatus { created, updated, alreadyConfigured, needsManualInstall }

final class InitHookResult {
  const InitHookResult(this.status, this.message);

  final InitHookStatus status;
  final String message;
}

/// Sets a project up for flutter_scene's build hook: installs (or refreshes)
/// `hook/build.dart`, creates `flutter_scene_generated/` with its `.gitignore`,
/// and lists that directory in `pubspec.yaml`. Idempotent.
Future<InitHookResult> installFlutterSceneBuildHook({
  Directory? projectRoot,
}) async {
  final root = projectRoot ?? Directory.current;
  final notes = <String>[];

  final hook = _installHook(root);
  notes.add(hook.message);

  // Creating the tree keeps the listed asset directory present in a fresh
  // clone, where its contents are ignored.
  createGeneratedAssetsDirectory(root.uri);
  notes.add('Created $generatedAssetsEntry with a .gitignore for its outputs.');

  final pubspec = ensureGeneratedAssetsEntry(
    File.fromUri(root.uri.resolve('pubspec.yaml')),
  );
  notes.add(pubspec.message);

  final needsHand =
      pubspec.status == PubspecEditStatus.unsupported ||
      pubspec.status == PubspecEditStatus.missingPubspec;
  return InitHookResult(
    needsHand ? InitHookStatus.needsManualInstall : hook.status,
    notes.join('\n'),
  );
}

InitHookResult _installHook(Directory root) {
  final hookDirectory = Directory.fromUri(root.uri.resolve('hook/'));
  final hookFile = File.fromUri(hookDirectory.uri.resolve('build.dart'));

  if (!hookFile.existsSync()) {
    hookDirectory.createSync(recursive: true);
    hookFile.writeAsStringSync(generatedBuildHook);
    return const InitHookResult(
      InitHookStatus.created,
      'Created hook/build.dart, which converts your assets at build time.',
    );
  }

  final contents = hookFile.readAsStringSync();
  if (contents.contains(hookStartMarker) && contents.contains(hookEndMarker)) {
    final updated = contents.replaceRange(
      contents.indexOf(hookStartMarker),
      contents.indexOf(hookEndMarker) + hookEndMarker.length,
      _hookSnippet.trimRight(),
    );
    if (updated == contents) {
      return const InitHookResult(
        InitHookStatus.alreadyConfigured,
        'hook/build.dart is already set up.',
      );
    }
    hookFile.writeAsStringSync(updated);
    return const InitHookResult(
      InitHookStatus.updated,
      'Refreshed the flutter_scene block in hook/build.dart.',
    );
  }

  if (contents.contains('buildScenes(') ||
      contents.contains('buildMaterials(') ||
      contents.contains('buildEngineAssets(')) {
    return const InitHookResult(
      InitHookStatus.alreadyConfigured,
      'hook/build.dart already calls the flutter_scene builders.',
    );
  }

  return InitHookResult(
    InitHookStatus.needsManualInstall,
    'hook/build.dart already exists and was not written by flutter_scene.\n\n'
    '$manualInstallInstructions',
  );
}
