import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene_importer/gltf.dart';

import '../asset_helpers.dart';
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
Future<List<gpu.Texture>> buildTextures(
  GltfDocument doc,
  Uint8List bufferData, {
  GltfResourceResolver? resolveUri,
}) async {
  final results = <gpu.Texture>[];
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

Future<gpu.Texture> _decodeAndUpload(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return gpuTextureFromImage(frame.image);
}

gpu.Texture _placeholder() {
  // Re-uses the static-resource white placeholder so we never insert null
  // entries (callers can index directly without a null check).
  return _whitePlaceholder ??= _makeWhite();
}

gpu.Texture? _whitePlaceholder;

gpu.Texture _makeWhite() {
  final t = gpu.gpuContext.createTexture(gpu.StorageMode.hostVisible, 1, 1);
  t.overwrite(Uint32List.fromList(<int>[0xFFFFFFFF]).buffer.asByteData());
  return t;
}
