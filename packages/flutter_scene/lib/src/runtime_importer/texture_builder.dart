import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/gltf.dart';

import '../importer/texture_roles.dart';
import '../texture/basisu/basis_ktx2.dart';
import '../texture/basisu/basis_ktx2_loader.dart';
import '../texture/compressed_texture.dart';
import '../texture/ktx2/ktx2.dart';
import '../texture/mipmap.dart';
import '../texture/texture2d.dart';
import 'gltf_resources.dart';

/// Decode each glTF texture into a [gpu.Texture]. Each entry in the returned
/// list corresponds 1:1 to `doc.textures` so material indexes resolve directly.
///
/// Image data is sourced from the GLB binary chunk (images referenced
/// via `bufferView`), from a `data:` URI (decoded inline), or from an
/// external file URI fetched through [resolveUri] when one is given
/// (multi-file glTF). A texture with a KHR_texture_basisu extension prefers
/// its KTX2 image; KTX2 payloads (detected by magic bytes or an image/ktx2
/// mime type) decode on a shared background isolate, everything else goes
/// through the platform image codec. An image that can't be sourced or
/// decoded falls back to a 1x1 white placeholder so material binding never
/// sees a null texture.
/// The encoded bytes of `doc.images[imageIndex]`, sourced from the GLB binary
/// chunk, a `data:` URI, or [resolveUri] for an external file (percent-decoded
/// per the glTF spec). Returns null when the image cannot be sourced, routing
/// the reason through [onMessage] (debug-printed when none is given).
Future<Uint8List?> resolveGltfImageBytes(
  GltfDocument doc,
  Uint8List bufferData,
  int imageIndex, {
  GltfResourceResolver? resolveUri,
  void Function(String message)? onMessage,
}) async {
  void report(String message) =>
      onMessage != null ? onMessage(message) : debugPrint(message);
  if (imageIndex < 0 || imageIndex >= doc.images.length) return null;
  final image = doc.images[imageIndex];
  if (image.bufferView != null) {
    final bv = doc.bufferViews[image.bufferView!];
    return Uint8List.sublistView(
      bufferData,
      bv.byteOffset,
      bv.byteOffset + bv.byteLength,
    );
  }
  final uri = image.uri;
  if (uri == null) return null;
  if (uri.startsWith('data:')) return decodeGltfDataUri(uri);
  if (resolveUri == null) {
    report(
      'glTF image $imageIndex references external URI "$uri" but no '
      'resource resolver was provided. Using placeholder.',
    );
    return null;
  }
  try {
    return await resolveUri(Uri.decodeComponent(uri));
  } catch (e) {
    report(
      'Failed to resolve glTF image $imageIndex URI "$uri": $e. '
      'Using placeholder.',
    );
    return null;
  }
}

Future<List<Texture2D>> buildTextures(
  GltfDocument doc,
  Uint8List bufferData, {
  GltfResourceResolver? resolveUri,
  GltfWarningCallback? onWarning,
}) async {
  void warn(String message) {
    if (onWarning != null) {
      onWarning(GltfImportWarning(message));
    } else {
      debugPrint(message);
    }
  }

  final results = List<Texture2D?>.filled(doc.textures.length, null);
  final contents = gltfTextureContents(doc);
  // Standard KTX2 files batch into one decode isolate so the transcoder's
  // lookup tables build once per import; the engine's own cooked files keep
  // their compressed upload path.
  final standardIndices = <int>[];
  final standardRequests = <StandardKtx2Request>[];
  final internalIndices = <int>[];
  final internalPayloads = <Uint8List>[];
  for (int i = 0; i < doc.textures.length; i++) {
    final tex = doc.textures[i];
    final imageIdx = tex.basisuSource ?? tex.source;
    if (imageIdx == null || imageIdx < 0 || imageIdx >= doc.images.length) {
      warn('glTF texture $i has no image source, using a placeholder.');
      continue;
    }
    final imageBytes = await resolveGltfImageBytes(
      doc,
      bufferData,
      imageIdx,
      resolveUri: resolveUri,
      onMessage: warn,
    );
    if (imageBytes == null) continue;

    if (looksLikeKtx2(imageBytes) ||
        doc.images[imageIdx].mimeType == 'image/ktx2') {
      try {
        if (isInternalKtx2(readKtx2(imageBytes))) {
          internalIndices.add(i);
          internalPayloads.add(imageBytes);
        } else {
          standardIndices.add(i);
          standardRequests.add((bytes: imageBytes, content: contents[i]));
        }
      } on Ktx2FormatException catch (e) {
        warn('Failed to parse glTF KTX2 image $imageIdx: $e');
      }
      continue;
    }
    try {
      results[i] = await _decodeAndUpload(imageBytes, contents[i]);
    } catch (e, st) {
      warn('Failed to decode glTF image $imageIdx: $e\n$st');
    }
  }

  if (standardRequests.isNotEmpty) {
    final decoded = await loadStandardKtx2Batch(standardRequests);
    for (int j = 0; j < standardIndices.length; j++) {
      results[standardIndices[j]] = decoded[j];
    }
  }
  for (int j = 0; j < internalIndices.length; j++) {
    try {
      results[internalIndices[j]] = Texture2D.fromGpuTexture(
        await gpuTextureFromKtx2Async(internalPayloads[j]),
      );
    } catch (e) {
      warn('Failed to load glTF KTX2 texture: $e');
    }
  }
  return [for (final result in results) result ?? _placeholder()];
}

Future<Texture2D> _decodeAndUpload(
  Uint8List bytes,
  TextureContent content,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    return await Texture2D.fromImage(frame.image, content: content);
  } finally {
    frame.image.dispose();
  }
}

Texture2D _placeholder() {
  // Re-uses a shared 1x1 white texture so we never insert null entries.
  return _whitePlaceholder ??= Texture2D.fromPixels(
    Uint8List.fromList(<int>[255, 255, 255, 255]),
    1,
    1,
    sampling: const TextureSampling(mipmaps: false),
  );
}

Texture2D? _whitePlaceholder;
