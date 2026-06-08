import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'package:flutter_scene/src/fscene/binary/fsceneb.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/node.dart';

/// Parses and realizes a `.fscene` document from [source] text into a live
/// node graph (synchronously).
///
/// The returned root carries the document's handedness (see [realizeScene]);
/// add it to a scene. Realizing meshes builds GPU geometry and materials, so
/// call this after the engine's static resources are ready. A document that
/// references external image assets or `fmat` materials needs [loadFsceneAsset]
/// (or [realizeSceneAsync]); the synchronous path uses placeholders for those.
Node loadFsceneString(String source, {FsceneComponentRegistry? registry}) =>
    realizeScene(readFscene(source), registry: registry);

/// Loads a `.fscene` text asset by [assetPath] and realizes it into a live
/// node graph, loading any external assets / `fmat` materials it references.
///
/// Mirrors `loadModel`: returns a root node to add to a scene. Pass a custom
/// [registry] to realize app-defined component types.
Future<Node> loadFsceneAsset(
  String assetPath, {
  FsceneComponentRegistry? registry,
  AssetBundle? bundle,
}) async {
  final source = await (bundle ?? rootBundle).loadString(assetPath);
  return realizeSceneAsync(
    readFscene(source),
    registry: registry,
    bundle: bundle,
  );
}

/// Parses and realizes a `.fsceneb` binary container from [bytes] into a live
/// node graph (synchronously).
///
/// The container carries embedded payload chunks, so payload-backed geometry
/// and embedded `rgba8` textures realize. For external assets, encoded image
/// payloads, or `fmat` materials, use [loadFscenebBytesAsync] (or
/// [realizeSceneAsync]); the synchronous path uses placeholders for those.
Node loadFscenebBytes(Uint8List bytes, {FsceneComponentRegistry? registry}) =>
    realizeScene(readFsceneb(bytes), registry: registry);

/// Parses a `.fsceneb` container from [bytes] and realizes it, first loading
/// any external assets, encoded image payloads, and `fmat` materials it
/// references (from [bundle], default `rootBundle`).
Future<Node> loadFscenebBytesAsync(
  Uint8List bytes, {
  FsceneComponentRegistry? registry,
  AssetBundle? bundle,
}) => realizeSceneAsync(readFsceneb(bytes), registry: registry, bundle: bundle);

/// Loads a `.fsceneb` binary asset by [assetPath] and realizes it into a live
/// node graph, loading any external assets / `fmat` materials it references.
///
/// Mirrors `loadModel`: returns a root node to add to a scene. Pass a custom
/// [registry] to realize app-defined component types.
Future<Node> loadFscenebAsset(
  String assetPath, {
  FsceneComponentRegistry? registry,
  AssetBundle? bundle,
}) async {
  final resolvedBundle = bundle ?? rootBundle;
  final data = await resolvedBundle.load(assetPath);
  return loadFscenebBytesAsync(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    registry: registry,
    bundle: bundle,
  );
}
