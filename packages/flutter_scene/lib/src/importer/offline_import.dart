import 'dart:io';

import 'gltf.dart';
import 'src/fb_emitter/model_emitter.dart';

/// Converts a single glTF binary at [inputGltfFilePath] to a Flutter
/// Scene `.model` file at [outputModelFilePath].
///
/// Both paths can be relative; they are resolved against
/// [workingDirectory] (defaulting to the caller's current working
/// directory). The `dart run flutter_scene_importer:import` CLI is a
/// thin wrapper around this function.
///
/// Pure Dart — does not depend on any native binary. Output is
/// structurally equivalent to what the previous C++ importer produced
/// (same `fb.SceneT` shape, same packed vertex/index bytes, same texture
/// dimensions).
void importGltf(
  String inputGltfFilePath,
  String outputModelFilePath, {
  String? workingDirectory,
}) {
  // Parse paths via Uri so Windows-style paths round-trip correctly.
  final inputGltfFilePathUri = Uri.file(inputGltfFilePath);
  final outputModelFilePathUri = Uri.file(outputModelFilePath);
  // Default to the caller's CWD when no working directory is supplied, so
  // command-line invocations like `dart run flutter_scene_importer:import`
  // resolve input/output paths relative to where the user ran the command.
  final workingDirectoryUri = Uri.directory(
    workingDirectory ?? Directory.current.path,
  );
  inputGltfFilePath =
      workingDirectoryUri.resolveUri(inputGltfFilePathUri).toFilePath();
  outputModelFilePath =
      workingDirectoryUri.resolveUri(outputModelFilePathUri).toFilePath();

  final inputBytes = File(inputGltfFilePath).readAsBytesSync();
  final container = parseGlb(inputBytes);
  final doc = parseGltfJson(container.json);
  final outputBytes = emitModel(doc, container.binaryChunk);
  final outputFile = File(outputModelFilePath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(outputBytes);
}
