import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    final logger = Logger('')
      ..level = Level.ALL
      // ignore: avoid_print
      ..onRecord.listen((record) => print(record.message));

    //-------------------------------------------------------------------------
    /// Ensure the "build/" directory exists.
    /// `mkdir -p build`
    ///
    final buildUri = config.packageRoot.resolve('build');
    final outDir = Directory.fromUri(buildUri);
    outDir.createSync(recursive: true);

    //-------------------------------------------------------------------------
    /// Run the cmake gen step.
    /// `cmake -Bbuild -DCMAKE_BUILD_TYPE=Debug`
    ///
    logger.info('Running cmake gen step...');
    final cmakeGenResult = Process.runSync(
        'cmake',
        [
          '-Bbuild',
          '-DCMAKE_BUILD_TYPE=Debug',
        ],
        workingDirectory: config.packageRoot.toFilePath());
    if (cmakeGenResult.exitCode != 0) {
      String error =
          'CMake generate step failed (exit code ${cmakeGenResult.exitCode}):\nSTDERR: ${cmakeGenResult.stderr}\nSTDOUT: ${cmakeGenResult.stdout}';
      logger.severe(error);
      throw Exception(error);
    }

    //-------------------------------------------------------------------------
    /// Run the cmake gen step.
    /// `cmake --build build --target=importer -j 4`
    ///
    logger.info('Running cmake build step...');
    final cmakeBuildResult = Process.runSync(
        'cmake',
        [
          '--build',
          'build',
          '--target=importer',
          '-j',
          '4',
        ],
        workingDirectory: config.packageRoot.toFilePath());
    if (cmakeBuildResult.exitCode != 0) {
      String error =
          'CMake build step failed (exit code ${cmakeBuildResult.exitCode}):\nSTDERR: ${cmakeBuildResult.stderr}\nSTDOUT: ${cmakeBuildResult.stdout}';
      logger.severe(error);
      throw Exception(error);
    }
  });
}
