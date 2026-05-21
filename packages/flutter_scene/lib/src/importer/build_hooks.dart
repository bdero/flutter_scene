import 'dart:io';

import 'package:hooks/hooks.dart';

import 'offline_import.dart';

/// Converts each `.glb` file in [inputFilePaths] to the Flutter Scene
/// `.model` format and writes the result into [outputDirectory] (resolved
/// relative to [BuildInput.packageRoot]).
///
/// Intended to be called from a `build_hooks.dart` entry point in the
/// consuming package. The [outputDirectory] is created if it doesn't
/// already exist; conversion runs in-process via Dart (no subprocess
/// shell-out, no native binary dependency).
///
/// Throws if any input file does not have a `.glb` extension.
void buildModels({
  required BuildInput buildInput,
  required List<String> inputFilePaths,
  String outputDirectory = 'build/models/',
}) {
  final outDir = Directory.fromUri(
    buildInput.packageRoot.resolve(outputDirectory),
  );
  outDir.createSync(recursive: true);

  for (final inputFilePath in inputFilePaths) {
    String outputFileName = Uri(path: inputFilePath).pathSegments.last;

    if (!outputFileName.endsWith('.glb')) {
      throw Exception(
        'Input file must be a .glb file. Given file path: $inputFilePath',
      );
    }
    outputFileName =
        '${outputFileName.substring(0, outputFileName.lastIndexOf('.'))}.model';

    importGltf(
      inputFilePath,
      outDir.uri.resolve(outputFileName).toFilePath(),
      workingDirectory: buildInput.packageRoot.toFilePath(),
    );
  }
}
