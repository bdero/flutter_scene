import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:web/web.dart' as web;

/// Loads the generated asset at [key], revalidating against the server.
///
/// A fetch from [rootBundle] uses the browser's heuristic HTTP cache, which can
/// keep an old bundle fresh for hours after a rebuild because the asset keeps
/// its original modification time. `no-cache` always asks the server, so an
/// unchanged asset costs a 304. A custom [bundle] is read as is.
Future<ByteData> loadGeneratedAsset(String key, {AssetBundle? bundle}) async {
  if (bundle != null && !identical(bundle, rootBundle)) return bundle.load(key);
  // Encoded the way the framework encodes a key before the engine encodes it
  // again into a URL.
  final url = ui_web.assetManager.getAssetUrl(
    Uri(path: Uri.encodeFull(key)).path,
  );
  final response = await web.window
      .fetch(url.toJS, web.RequestInit(cache: 'no-cache'))
      .toDart;
  if (!response.ok) {
    throw FlutterError(
      'Unable to load asset: "$key" (HTTP ${response.status}).',
    );
  }
  final buffer = await response.arrayBuffer().toDart;
  return ByteData.view(buffer.toDart);
}

/// Loads the generated asset at [key] as UTF-8 text, revalidating like
/// [loadGeneratedAsset].
Future<String> loadGeneratedAssetString(
  String key, {
  AssetBundle? bundle,
}) async {
  if (bundle != null && !identical(bundle, rootBundle)) {
    return bundle.loadString(key);
  }
  final data = await loadGeneratedAsset(key);
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}
