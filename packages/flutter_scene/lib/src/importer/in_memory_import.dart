import 'dart:typed_data';

import '../fscene/scene_document.dart';
import 'gltf.dart';
import 'src/fscene_emitter/fscene_emitter.dart';

/// Converts a single-file glTF binary (`.glb`) to an `.fscene` [SceneDocument]
/// entirely in memory.
///
/// The document declares right-handed coordinates; realize it with
/// `realizeScene` (or write it with `writeFscene` / `writeFsceneb`). Uses no
/// `dart:io`, so it runs at runtime on any platform.
SceneDocument importGlbToSceneDocument(
  Uint8List glbBytes, {
  bool compressTextures = false,
}) {
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  return buildSceneDocument(
    doc,
    container.binaryChunk,
    compressTextures: compressTextures,
  );
}

/// Converts a single-file glTF binary (`.glb`) to `.fsceneb` binary container
/// bytes entirely in memory.
///
/// The same conversion the `buildScenes` build hook performs, minus the file
/// I/O. Uses no `dart:io`, so it runs at runtime on any platform. Single-file
/// `.glb` only; multi-file `.gltf` (external `.bin`/image resources) is not
/// supported by the offline importer.
Uint8List importGlbToFscenebBytes(
  Uint8List glbBytes, {
  bool compressTextures = false,
}) {
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  return emitFsceneb(
    doc,
    container.binaryChunk,
    compressTextures: compressTextures,
  );
}
