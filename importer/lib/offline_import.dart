import 'dart:io';
import 'dart:isolate';

Uri findBuiltExecutable(String executableName, Uri packageRoot,
    {String dir = 'build/'}) {
  List<String> locations = [
    'Release/$executableName',
    'Release/$executableName.exe',
    'Debug/$executableName',
    'Debug/$executableName.exe',
    executableName,
    '$executableName.exe',
  ];

  final Uri buildDirectory = packageRoot.resolve(dir);
  Uri? found;
  List<Uri> tried = [];
  for (final location in locations) {
    final uri = buildDirectory.resolve(location);
    tried.add(uri);
    if (File.fromUri(uri).existsSync()) {
      found = uri;
      break;
    }
  }
  if (found == null) {
    throw Exception(
        'Unable to find build executable $executableName! Tried the following locations: $tried');
  }
  return found;
}

Uri findImporterPackageRoot() {
  Uri importerPackageUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:flutter_scene_importer/'))!;
  return importerPackageUri.resolve('../');
}

void generateImporterFlatbufferDart(
    {String generatedOutputDirectory = "lib/generated/"}) {
  final packageRoot = findImporterPackageRoot();
  final flatc = findBuiltExecutable('flatc', packageRoot,
      dir: 'build/_deps/flatbuffers-build/');

  final flatcResult = Process.runSync(
      flatc.toFilePath(),
      [
        '-o',
        generatedOutputDirectory,
        '--warnings-as-errors',
        '--gen-object-api',
        '--filename-suffix',
        '_flatbuffers',
        '--dart',
        'scene.fbs',
      ],
      workingDirectory: packageRoot.toFilePath());
  if (flatcResult.exitCode != 0) {
    throw Exception(
        'Failed to generate importer flatbuffer: ${flatcResult.stderr}\n${flatcResult.stdout}');
  }

  /// Update the generated file's flatbuffer include to use a patched version
  /// that allows for flatbuffer arrays to be accessed without copies.
  /// TODO(bdero): Remove after https://github.com/google/flatbuffers/pull/8289
  ///              makes it into the Dart package.
  final generatedFile = File.fromUri(packageRoot
      .resolve(generatedOutputDirectory)
      .resolve('scene_impeller.fb_flatbuffers.dart'));
  final lines = generatedFile.readAsLinesSync();
  final importLineIndex = lines.indexWhere((element) => element
      .contains("import 'package:flat_buffers/flat_buffers.dart' as fb;"));
  if (importLineIndex == -1) {
    throw Exception('Failed to find flat_buffer import line in generated file');
  }
  lines[importLineIndex] =
      "import 'package:flutter_scene_importer/third_party/flat_buffers.dart' as fb;";
  generatedFile.writeAsStringSync(lines.join('\n'));
}

/// Takes an input model (glTF file) and
void importGltf(String inputGltfFilePath, String outputModelFilePath,
    {String? workingDirectory}) {
  final packageRoot = findImporterPackageRoot();
  final importer = findBuiltExecutable('importer', packageRoot);

  final workingDirectoryUri =
      Uri.parse(workingDirectory ?? packageRoot.toFilePath());
  inputGltfFilePath =
      workingDirectoryUri.resolve(inputGltfFilePath).toFilePath();
  outputModelFilePath =
      workingDirectoryUri.resolve(outputModelFilePath).toFilePath();
  //throw Exception('root $packageRoot input $inputGltfFilePath output $outputModelFilePath');

  final importerResult = Process.runSync(
      importer.toFilePath(),
      [
        inputGltfFilePath,
        outputModelFilePath,
      ],
      workingDirectory: workingDirectory);
  if (importerResult.exitCode != 0) {
    throw Exception(
        'Failed to run importer: ${importerResult.stderr}\n${importerResult.stdout}');
  }
}
