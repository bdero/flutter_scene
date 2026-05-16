import 'dart:convert';
import 'dart:typed_data';

/// Resolves an external resource referenced by a multi-file glTF
/// document (a `.bin` buffer or an image file).
///
/// Given the raw relative URI string from the glTF, returns the
/// resource's bytes. Supplied by the caller of [Node.fromGltfBytes] /
/// `importGltf`; `data:` URIs are decoded internally and never reach
/// the resolver.
typedef GltfResourceResolver = Future<Uint8List> Function(String uri);

/// Decodes a `data:` URI into its raw bytes.
///
/// glTF embeds binary resources as base64 `data:` URIs; that is the
/// only form expected here. A non-base64 (percent-encoded text) data
/// URI is decoded as UTF-8 text for completeness.
Uint8List decodeGltfDataUri(String uri) {
  final comma = uri.indexOf(',');
  if (comma < 0) {
    throw FormatException('Malformed data URI: $uri');
  }
  final meta = uri.substring(0, comma);
  final payload = uri.substring(comma + 1);
  if (meta.contains(';base64')) {
    return base64Decode(payload);
  }
  return Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
}
