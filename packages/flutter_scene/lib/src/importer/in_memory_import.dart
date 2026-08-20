import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'gltf.dart';
import 'src/fscene_emitter/fscene_emitter.dart';

/// Resolves a glTF external resource [uri] (a relative path to a `.bin` or
/// image file) to its bytes, or null when it cannot be found. Used by
/// [importGltfToSceneDocument] for multi-file `.gltf` assets; data URIs are
/// handled internally and never reach the resolver.
typedef GltfUriResolver = Uint8List? Function(String uri);

/// Converts a single-file glTF binary (`.glb`) to an `.fscene` [SceneDocument]
/// entirely in memory.
///
/// The document contains native scene coordinates. Realize it with
/// `realizeScene` (or write it with `writeFscene`/`writeFsceneb`). Uses no
/// `dart:io`, so it runs at runtime on any platform. [onWarning], when given,
/// receives non-fatal import issues (currently, an unrecognized extension);
/// without it they print instead.
SceneDocument importGlbToSceneDocument(
  Uint8List glbBytes, {
  bool compressTextures = false,
  GltfWarningCallback? onWarning,
}) {
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  _deliverWarnings(doc.warnings, onWarning);
  final gltf = decodeMeshoptBufferViews(doc, container.binaryChunk);
  return buildSceneDocument(
    gltf.doc,
    gltf.bufferData,
    compressTextures: compressTextures,
  );
}

/// Converts a single-file glTF binary (`.glb`) to `.fsceneb` binary container
/// bytes entirely in memory.
///
/// The same conversion the `buildScenes` build hook performs, minus the file
/// I/O. Uses no `dart:io`, so it runs at runtime on any platform. Single-file
/// `.glb` only; multi-file `.gltf` (external `.bin`/image resources) is not
/// supported by the offline importer. [onWarning], when given, receives
/// non-fatal import issues; without it they print instead.
Uint8List importGlbToFscenebBytes(
  Uint8List glbBytes, {
  bool compressTextures = false,
  GltfWarningCallback? onWarning,
}) {
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  _deliverWarnings(doc.warnings, onWarning);
  final gltf = decodeMeshoptBufferViews(doc, container.binaryChunk);
  return emitFsceneb(
    gltf.doc,
    gltf.bufferData,
    compressTextures: compressTextures,
  );
}

// Delivers parse-time warnings to onWarning, or prints them when absent.
void _deliverWarnings(
  List<GltfImportWarning> warnings,
  GltfWarningCallback? onWarning,
) {
  for (final warning in warnings) {
    if (onWarning != null) {
      onWarning(warning);
    } else {
      // ignore: avoid_print
      print('glTF import: $warning');
    }
  }
}

/// Converts a multi-file glTF (`.gltf` JSON plus external `.bin` and image
/// files) to an `.fscene` [SceneDocument] entirely in memory.
///
/// [gltfBytes] is the `.gltf` JSON. [resolveUri] supplies the bytes for each
/// external resource the document references (relative paths to `.bin` and
/// image files); data-URI resources are decoded internally. External resources
/// are embedded into the document, so the result is self-contained (no leftover
/// file references) and saves to a standalone `.fscene`. Throws a
/// [FormatException] when a referenced resource cannot be resolved.
/// [onWarning], when given, receives non-fatal import issues; without it
/// they print instead.
///
/// Single-file `.glb` uses [importGlbToSceneDocument] instead.
SceneDocument importGltfToSceneDocument(
  Uint8List gltfBytes, {
  required GltfUriResolver resolveUri,
  bool compressTextures = false,
  GltfWarningCallback? onWarning,
}) {
  final normalized = _normalizeGltf(gltfBytes, resolveUri);
  _deliverWarnings(normalized.doc.warnings, onWarning);
  final gltf = decodeMeshoptBufferViews(normalized.doc, normalized.bufferData);
  return buildSceneDocument(
    gltf.doc,
    gltf.bufferData,
    compressTextures: compressTextures,
  );
}

// Resolves a .gltf's external buffers and images into the single-buffer form
// the builder expects: every buffer is concatenated into one blob with its
// bufferViews rebased, and every external/data-uri image is appended as a new
// bufferView (so it embeds like a GLB image rather than staying a file ref).
// Slicing reads from a single blob by absolute offset and ignores the buffer
// index, so only the offsets need to move.
({GltfDocument doc, Uint8List bufferData}) _normalizeGltf(
  Uint8List gltfBytes,
  GltfUriResolver resolveUri,
) {
  final json = jsonDecode(utf8.decode(gltfBytes)) as Map<String, Object?>;
  final doc = parseGltfJson(json);

  final blob = BytesBuilder();
  void padTo4() {
    while (blob.length % 4 != 0) {
      blob.addByte(0);
    }
  }

  // EXT_meshopt_compression placeholder buffers hold no data the decode path
  // reads, so they contribute nothing to the blob and are never resolved.
  final placeholders = meshoptPlaceholderBuffers(doc);
  final bufferBase = <int>[];
  for (int i = 0; i < doc.buffers.length; i++) {
    padTo4();
    bufferBase.add(blob.length);
    if (placeholders.contains(i)) continue;
    blob.add(_resolveResource(doc.buffers[i].uri, resolveUri, what: 'buffer'));
  }

  final bufferViews = [
    for (final v in doc.bufferViews)
      GltfBufferView(
        buffer: 0,
        byteLength: v.byteLength,
        byteOffset: v.byteOffset + bufferBase[v.buffer],
        byteStride: v.byteStride,
        meshopt: v.meshopt?.rebased(
          buffer: 0,
          byteOffset: v.meshopt!.byteOffset + bufferBase[v.meshopt!.buffer],
        ),
      ),
  ];

  final images = <GltfImage>[];
  for (final image in doc.images) {
    if (image.uri == null) {
      images.add(image);
      continue;
    }
    final bytes = _resolveResource(image.uri, resolveUri, what: 'image');
    padTo4();
    images.add(
      GltfImage(bufferView: bufferViews.length, mimeType: image.mimeType),
    );
    bufferViews.add(
      GltfBufferView(
        buffer: 0,
        byteLength: bytes.length,
        byteOffset: blob.length,
      ),
    );
    blob.add(bytes);
  }

  final normalized = doc.copyWith(bufferViews: bufferViews, images: images);
  return (doc: normalized, bufferData: blob.toBytes());
}

Uint8List _resolveResource(
  String? uri,
  GltfUriResolver resolveUri, {
  required String what,
}) {
  if (uri == null) {
    throw FormatException(
      'glTF $what has no uri (a .gltf references external or data-uri '
      'resources; a single-file .glb should use importGlbToSceneDocument)',
    );
  }
  if (uri.startsWith('data:')) {
    return UriData.parse(uri).contentAsBytes();
  }
  final bytes = resolveUri(Uri.decodeComponent(uri));
  if (bytes == null) {
    throw FormatException('Could not resolve glTF $what uri: $uri');
  }
  return bytes;
}
