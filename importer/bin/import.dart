import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_scene_importer/offline_import.dart';

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('input', abbr: 'i', help: 'Input glTF file path')
    ..addOption('output', abbr: 'o', help: 'Output model file path')
    ..addOption('working-directory', abbr: 'w', help: 'Working directory');

  final results = parser.parse(args);

  final input = results['input'] as String?;
  final output = results['output'] as String?;
  final workingDirectory = results['working-directory'] as String?;

  if (input == null || output == null) {
    // ignore: avoid_print
    print(
        'Usage: importer --input <input> --output <output> [--working-directory <working-directory>]');
    exit(1);
  }

  importGltf(input, output, workingDirectory: workingDirectory);
}
