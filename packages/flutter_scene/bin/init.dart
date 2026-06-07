import 'dart:io';

import 'package:flutter_scene/src/fmat/init_command.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln('Usage: dart run flutter_scene:init');
    stdout.writeln('');
    stdout.writeln(
      'Installs a hook/build.dart that builds .fmat materials with DataAssets.',
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
  if (result.status != InitHookStatus.needsManualInstall) {
    stdout.writeln('');
    stdout.writeln(
      'DataAssets are experimental. On supported Flutter master builds, run:',
    );
    stdout.writeln('');
    stdout.writeln('  flutter config --enable-dart-data-assets');
    stdout.writeln('');
    stdout.writeln(
      'Then load materials by source path with loadFmatMaterial and render with '
      'SceneView; editing a .fmat hot reloads in place. To load and hot reload '
      '.glb models the same way (loadModel), also call buildModels in the hook.',
    );
  }
  if (result.status == InitHookStatus.needsManualInstall) {
    exitCode = 1;
  }
}
