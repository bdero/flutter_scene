import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_scene/src/importer/offline_import.dart';

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'input',
      abbr: 'i',
      help:
          'Input glTF (.glb) file path. Resolved relative to '
          '--working-directory.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help:
          'Output .fsceneb file path. Resolved relative to '
          '--working-directory.',
    )
    ..addFlag(
      'compress-textures',
      help:
          'Store images as mipped, supercompressed KTX2 block payloads '
          'instead of raw rgba8.',
    )
    ..addOption(
      'working-directory',
      abbr: 'w',
      help:
          'Directory used to resolve relative --input and --output paths. '
          'Defaults to the current working directory.',
    );

  final results = parser.parse(args);

  final input = results['input'] as String?;
  final output = results['output'] as String?;
  final workingDirectory = results['working-directory'] as String?;
  final compressTextures = results['compress-textures'] as bool;

  if (input == null || output == null) {
    // ignore: avoid_print
    print(
      'Usage: importer --input <input> --output <output> [--working-directory <working-directory>]',
    );
    exit(1);
  }

  importGltfToFsceneb(
    input,
    output,
    workingDirectory: workingDirectory,
    compressTextures: compressTextures,
  );
}
