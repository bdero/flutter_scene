import 'dart:io';

import 'package:flutter_scene/src/fmat/init_command.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln('Usage: dart run flutter_scene:init');
    stdout.writeln('');
    stdout.writeln(
      'Sets this project up for flutter_scene: installs hook/build.dart, '
      'creates flutter_scene_generated/, and lists it in pubspec.yaml.',
    );
    stdout.writeln('');
    stdout.writeln(manualInstallInstructions);
    return;
  }

  final result = await installFlutterSceneBuildHook();
  final sink = result.status == InitHookStatus.needsManualInstall
      ? stderr
      : stdout;
  sink.writeln(result.message);
  if (result.status == InitHookStatus.needsManualInstall) {
    exitCode = 1;
    return;
  }
  stdout.writeln('');
  stdout.writeln(
    'The hook converts .glb and .fscene models, .fmat materials, and loose '
    'images under assets/ at build time. Load them by source path with '
    'loadScene / loadFmatMaterial / loadTexture, render with SceneView, and '
    'edits hot reload in place.',
  );
}
