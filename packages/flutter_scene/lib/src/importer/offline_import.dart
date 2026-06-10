import 'dart:io';

import 'gltf.dart';
import 'src/fscene_emitter/fscene_emitter.dart';

/// Converts a single glTF binary at [inputGltfFilePath] to a flutter_scene
/// `.fsceneb` package at [outputFscenebFilePath].
///
/// Both paths can be relative; they are resolved against [workingDirectory]
/// (defaulting to the caller's current directory, so Windows-style paths
/// round-trip correctly via Uri). Pure Dart, no native binary.
void importGltfToFsceneb(
  String inputGltfFilePath,
  String outputFscenebFilePath, {
  String? workingDirectory,
  bool compressTextures = false,
}) {
  final workingDirectoryUri = Uri.directory(
    workingDirectory ?? Directory.current.path,
  );
  inputGltfFilePath = workingDirectoryUri
      .resolveUri(Uri.file(inputGltfFilePath))
      .toFilePath();
  outputFscenebFilePath = workingDirectoryUri
      .resolveUri(Uri.file(outputFscenebFilePath))
      .toFilePath();

  final inputBytes = File(inputGltfFilePath).readAsBytesSync();
  final container = parseGlb(inputBytes);
  final doc = parseGltfJson(container.json);
  final outputBytes = emitFsceneb(
    doc,
    container.binaryChunk,
    compressTextures: compressTextures,
  );
  final outputFile = File(outputFscenebFilePath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(outputBytes);
}
