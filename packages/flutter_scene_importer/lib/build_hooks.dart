import 'dart:io';

import 'package:hooks/hooks.dart';

void buildModels({
  required BuildInput buildInput,
  required List<String> inputFilePaths,
  String outputDirectory = 'build/models/',
}) {
  final outDir = Directory.fromUri(
    buildInput.packageRoot.resolve(outputDirectory),
  );
  outDir.createSync(recursive: true);

  final Uri dartExec = Uri.file(Platform.resolvedExecutable);

  for (final inputFilePath in inputFilePaths) {
    String outputFileName = Uri(path: inputFilePath).pathSegments.last;

    // Verify that the input file is a glTF file
    if (!outputFileName.endsWith('.glb')) {
      throw Exception(
        'Input file must be a .glb file. Given file path: $inputFilePath',
      );
    }

    // Replace output extension with .model
    outputFileName =
        '${outputFileName.substring(0, outputFileName.lastIndexOf('.'))}.model';

    /// dart run flutter_scene_importer:import \
    ///     --input <input> --output <output> --working-directory <working-directory>
    final importerResult = Process.runSync(dartExec.toFilePath(), [
      'run',
      'flutter_scene_importer:import',
      '--input',
      inputFilePath,
      '--output',
      outDir.uri.resolve(outputFileName).toFilePath(),
      '--working-directory',
      buildInput.packageRoot.toFilePath(),
    ]);
    if (importerResult.exitCode != 0) {
      throw Exception(
        'Failed to run flutter_scene_importer:import command in build hook (exit code ${importerResult.exitCode}):\nSTDERR: ${importerResult.stderr}\nSTDOUT: ${importerResult.stdout}',
      );
    }
  }
}
