import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/gltf.dart';

import '../texture/texture2d.dart';
import 'gltf_resources.dart';

/// Decode each glTF texture into a [gpu.Texture]. Each entry in the returned
/// list corresponds 1:1 to `doc.textures` so material indexes resolve directly.
///
/// Image data is sourced from the GLB binary chunk (images referenced
/// via `bufferView`), from a `data:` URI (decoded inline), or from an
/// external file URI fetched through [resolveUri] when one is given
/// (multi-file glTF). An image that can't be sourced or decoded falls
/// back to a 1x1 white placeholder so material binding never sees a
/// null texture.
Future<List<Texture2D>> buildTextures(
  GltfDocument doc,
  Uint8List bufferData, {
  GltfResourceResolver? resolveUri,
}) async {
  final results = <Texture2D>[];
  for (int i = 0; i < doc.textures.length; i++) {
    final tex = doc.textures[i];
    final imageIdx = tex.source;
    if (imageIdx == null || imageIdx < 0 || imageIdx >= doc.images.length) {
      debugPrint('glTF texture $i has no image source — using a placeholder.');
      results.add(_placeholder());
      continue;
    }
    final image = doc.images[imageIdx];
    Uint8List? imageBytes;
    if (image.bufferView != null) {
      final bv = doc.bufferViews[image.bufferView!];
      imageBytes = Uint8List.sublistView(
        bufferData,
        bv.byteOffset,
        bv.byteOffset + bv.byteLength,
      );
    } else if (image.uri != null) {
      final uri = image.uri!;
      if (uri.startsWith('data:')) {
        imageBytes = decodeGltfDataUri(uri);
      } else if (resolveUri != null) {
        try {
          imageBytes = await resolveUri(uri);
        } catch (e) {
          debugPrint(
            'Failed to resolve glTF image $imageIdx URI "$uri": $e. '
            'Using placeholder.',
          );
          results.add(_placeholder());
          continue;
        }
      } else {
        debugPrint(
          'glTF image $imageIdx references external URI "$uri" but no '
          'resource resolver was provided. Using placeholder.',
        );
        results.add(_placeholder());
        continue;
      }
    } else {
      results.add(_placeholder());
      continue;
    }

    try {
      final texture = await _decodeAndUpload(imageBytes);
      results.add(texture);
    } catch (e, st) {
      debugPrint('Failed to decode glTF image $imageIdx: $e\n$st');
      results.add(_placeholder());
    }
  }
  return results;
}

// TODO(mipmaps): classify each image's content (color vs normal vs data) from
// how materials reference it, so normal/metallic-roughness maps get linear
// (renormalized) mips instead of the sRGB-color default.
Future<Texture2D> _decodeAndUpload(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    return await Texture2D.fromImage(frame.image);
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
