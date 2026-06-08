import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_scene/src/fscene/binary/fsceneb.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/node.dart';

/// Parses and realizes a `.fscene` document from [source] text into a live
/// node graph.
///
/// The returned root carries the document's handedness (see [realizeScene]);
/// add it to a scene. Realizing meshes builds GPU geometry and materials, so
/// call this after the engine's static resources are ready.
Node loadFsceneString(String source, {FsceneComponentRegistry? registry}) =>
    realizeScene(readFscene(source), registry: registry);

/// Loads a `.fscene` text asset by [assetPath] and realizes it into a live
/// node graph.
///
/// Mirrors `loadModel`: returns a root node to add to a scene. Pass a custom
/// [registry] to realize app-defined component types.
Future<Node> loadFsceneAsset(
  String assetPath, {
  FsceneComponentRegistry? registry,
}) async {
  final source = await rootBundle.loadString(assetPath);
  return loadFsceneString(source, registry: registry);
}

/// Parses and realizes a `.fsceneb` binary container from [bytes] into a live
/// node graph.
///
/// Unlike the text form, the container carries embedded payload chunks, so
/// payload-backed geometry and image textures realize. Realizing meshes builds
/// GPU resources, so call this after the engine's static resources are ready.
Node loadFscenebBytes(Uint8List bytes, {FsceneComponentRegistry? registry}) =>
    realizeScene(readFsceneb(bytes), registry: registry);

/// Loads a `.fsceneb` binary asset by [assetPath] and realizes it into a live
/// node graph.
///
/// Mirrors `loadModel`: returns a root node to add to a scene. Pass a custom
/// [registry] to realize app-defined component types.
Future<Node> loadFscenebAsset(
  String assetPath, {
  FsceneComponentRegistry? registry,
}) async {
  final data = await rootBundle.load(assetPath);
  return loadFscenebBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    registry: registry,
  );
}
