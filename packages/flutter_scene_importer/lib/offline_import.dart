import 'dart:io';
import 'dart:isolate';

/// Searches for a built native executable named [executableName] under
/// `<packageRoot>/<dir>`, checking the conventional CMake layouts
/// (`Release/`, `Debug/`, and the bare directory) on both POSIX and
/// Windows.
///
/// Returns the first matching [Uri], or throws with the list of paths it
/// tried.
Uri findBuiltExecutable(
  String executableName,
  Uri packageRoot, {
  String dir = 'build/',
}) {
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
      'Unable to find build executable $executableName! Tried the following locations: $tried',
    );
  }
  return found;
}

/// Returns the file-system root of the resolved
/// `flutter_scene_importer` package.
///
/// Used when running build tooling that needs to locate the bundled
/// importer binary or its `.fbs` schema regardless of where the package
/// was resolved from (workspace, pub-cache, or path dependency).
Uri findImporterPackageRoot() {
  Uri importerPackageUri =
      Isolate.resolvePackageUriSync(
        Uri.parse('package:flutter_scene_importer/'),
      )!;
  return importerPackageUri.resolve('../');
}

/// Regenerates the Dart bindings for the flatbuffer schema bundled with
/// this package by invoking `flatc`.
///
/// Used by the importer's own build to (re)generate
/// `lib/generated/scene_impeller.fb_flatbuffers.dart`. Consumer apps do
/// not need to call this — the bindings are committed to the package.
///
/// After generation, the import line is rewritten to point at the
/// vendored `flat_buffers` copy under `third_party/`.
void generateImporterFlatbufferDart({
  String generatedOutputDirectory = "lib/generated/",
}) {
  final packageRoot = findImporterPackageRoot();
  final flatc = findBuiltExecutable(
    'flatc',
    packageRoot,
    dir: 'build/_deps/flatbuffers-build/',
  );

  final flatcResult = Process.runSync(flatc.toFilePath(), [
    '-o',
    generatedOutputDirectory,
    '--warnings-as-errors',
    '--gen-object-api',
    '--filename-suffix',
    '_flatbuffers',
    '--dart',
    'scene.fbs',
  ], workingDirectory: packageRoot.toFilePath());
  if (flatcResult.exitCode != 0) {
    throw Exception(
      'Failed to generate importer flatbuffer: ${flatcResult.stderr}\n${flatcResult.stdout}',
    );
  }

  /// Update the generated file's flatbuffer include to use a patched version
  /// that allows for flatbuffer arrays to be accessed without copies.
  /// TODO(bdero): Remove after https://github.com/google/flatbuffers/pull/8289
  ///              makes it into the Dart package.
  final generatedFile = File.fromUri(
    packageRoot
        .resolve(generatedOutputDirectory)
        .resolve('scene_impeller.fb_flatbuffers.dart'),
  );
  final lines = generatedFile.readAsLinesSync();
  final importLineIndex = lines.indexWhere(
    (element) => element.contains(
      "import 'package:flat_buffers/flat_buffers.dart' as fb;",
    ),
  );
  if (importLineIndex == -1) {
    throw Exception('Failed to find flat_buffer import line in generated file');
  }
  lines[importLineIndex] =
      "import 'package:flutter_scene_importer/third_party/flat_buffers.dart' as fb;";
  generatedFile.writeAsStringSync(lines.join('\n'));
}

/// Converts a single glTF binary at [inputGltfFilePath] to a Flutter
/// Scene `.model` file at [outputModelFilePath], invoking the bundled
/// native importer as a subprocess.
///
/// Both paths can be relative; they are resolved against
/// [workingDirectory] (defaulting to the caller's current working
/// directory). The `dart run flutter_scene_importer:import` CLI is a
/// thin wrapper around this function.
///
/// Throws if the importer process exits with a non-zero status.
void importGltf(
  String inputGltfFilePath,
  String outputModelFilePath, {
  String? workingDirectory,
}) {
  final packageRoot = findImporterPackageRoot();
  final importer = findBuiltExecutable('importer', packageRoot);

  // Parse the paths via Uri.file/Uri.directory and use resolveUri to resolve
  // the paths relative to the working directory. Using raw strings doesn't
  // bode well with Windows paths.
  final inputGltfFilePathUri = Uri.file(inputGltfFilePath);
  final outputModelFilePathUri = Uri.file(outputModelFilePath);
  // Default to the caller's CWD when no working directory is supplied, so
  // command-line invocations like `dart run flutter_scene_importer:import`
  // resolve input/output paths relative to where the user ran the command
  // (not relative to the importer package's root in pub-cache).
  final workingDirectoryUri = Uri.directory(
    workingDirectory ?? Directory.current.path,
  );
  inputGltfFilePath =
      workingDirectoryUri.resolveUri(inputGltfFilePathUri).toFilePath();
  outputModelFilePath =
      workingDirectoryUri.resolveUri(outputModelFilePathUri).toFilePath();
  //throw Exception('root $packageRoot input $inputGltfFilePath output $outputModelFilePath');

  final importerResult = Process.runSync(importer.toFilePath(), [
    inputGltfFilePath,
    outputModelFilePath,
  ], workingDirectory: workingDirectory);
  if (importerResult.exitCode != 0) {
    throw Exception(
      'Failed to run importer: ${importerResult.stderr}\n${importerResult.stdout}',
    );
  }
}
