import 'dart:typed_data';

import '../fscene/scene_document.dart';
import 'gltf.dart';
import 'src/fb_emitter/model_emitter.dart';
import 'src/fscene_emitter/fscene_emitter.dart';

/// Converts a single-file glTF binary (`.glb`) to flutter_scene's `.model`
/// flatbuffer bytes, entirely in memory.
///
/// This is the exact conversion the offline (ahead-of-time) importer performs
/// (the same `parseGlb` -> `parseGltfJson` -> `emitModel` pipeline that
/// `importGltf` / the `buildModels` build hook run), minus the file I/O. It
/// uses no `dart:io`, so it runs at runtime on any platform.
///
/// Single-file `.glb` only; multi-file `.gltf` (external `.bin`/image
/// resources) is not supported by the offline importer.
Uint8List importGlbToModelBytes(Uint8List glbBytes) {
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  return emitModel(doc, container.binaryChunk);
}

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
/// Geometry is packed with the same code the `.model` path uses, so a
/// primitive's vertex/index payload bytes match the `.model` output. Uses no
/// `dart:io`, so it runs at runtime on any platform.
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
