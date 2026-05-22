import 'dart:typed_data';

import 'gltf.dart';
import 'src/fb_emitter/model_emitter.dart';

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
