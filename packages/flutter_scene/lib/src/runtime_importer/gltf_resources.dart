import 'dart:convert';
import 'dart:typed_data';

import '../texture/mipmap.dart';
import '../texture/texture2d.dart';

/// Resolves an external resource referenced by a multi-file glTF
/// document (a `.bin` buffer or an image file).
///
/// Given the raw relative URI string from the glTF, returns the
/// resource's bytes. Supplied by the caller of [Node.fromGltfBytes] /
/// `importGltf`; `data:` URIs are decoded internally and never reach
/// the resolver.
/// {@category Assets and loading}
typedef GltfResourceResolver = Future<Uint8List> Function(String uri);

/// Supplies the texture for an image a glTF or GLB document references by
/// external URI, in place of fetching and decoding its bytes.
///
/// [uri] is the raw relative URI string from the document, percent-decoded.
/// [content] is the role the importer derived from the material slots that
/// sample the image; it selects mip downsampling, so a caller that caches
/// textures keys them by both. The returned texture may be shared across
/// imports: the importer applies the glTF sampler through a wrapper over the
/// same GPU texture and never mutates or disposes it. Returning null or
/// throwing reports a warning and binds the 1x1 white placeholder.
/// `data:` URIs and images embedded via `bufferView` never reach the
/// resolver. A resolver that decodes bytes itself can use
/// [Texture2D.fromEncodedBytes].
/// {@category Assets and loading}
typedef GltfTextureResolver =
    Future<Texture2D?> Function(String uri, TextureContent content);

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
