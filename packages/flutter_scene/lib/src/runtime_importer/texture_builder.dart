import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/gltf.dart';

import '../importer/texture_roles.dart';
import '../texture/basisu/basis_ktx2.dart';
import '../texture/basisu/basis_ktx2_loader.dart';
import '../texture/compressed_texture.dart';
import '../texture/ktx2/ktx2.dart';
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
  int? maxTextureSize,
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
      results[i] = await Texture2D.fromEncodedBytes(
        imageBytes,
        content: contents[i],
        maxSize: maxTextureSize,
      );
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
  return [
    for (int i = 0; i < results.length; i++)
      _withGltfSampler(results[i], doc, i) ?? _placeholder(),
  ];
}

/// Applies glTF texture [textureIndex]'s sampler (wrap and filter modes) to
/// [texture], which was created with the engine's default sampling.
Texture2D? _withGltfSampler(
  Texture2D? texture,
  GltfDocument doc,
  int textureIndex,
) {
  if (texture == null) return null;
  final samplerIndex = doc.textures[textureIndex].sampler;
  if (samplerIndex == null ||
      samplerIndex < 0 ||
      samplerIndex >= doc.samplers.length) {
    return texture;
  }
  final options = gltfSamplerOptions(
    doc.samplers[samplerIndex],
    texture.sampledSampler,
  );
  return identical(options, texture.sampledSampler)
      ? texture
      : texture.withSampler(options);
}

/// glTF sampler [sampler] as Flutter GPU sampler options, starting from
/// [base] (the texture's default sampling) for anything glTF leaves unset.
///
/// Wrap modes map directly (33071 CLAMP_TO_EDGE, 33648 MIRRORED_REPEAT,
/// 10497 REPEAT). An unset filter keeps [base]'s. Anisotropy survives only
/// when every filter stays linear, since pairing it with a nearest filter is
/// invalid. Returns [base] itself when the sampler changes nothing.
gpu.SamplerOptions gltfSamplerOptions(
  GltfSampler sampler,
  gpu.SamplerOptions base,
) {
  gpu.SamplerAddressMode wrap(int mode) => switch (mode) {
    33071 => gpu.SamplerAddressMode.clampToEdge,
    33648 => gpu.SamplerAddressMode.mirror,
    _ => gpu.SamplerAddressMode.repeat,
  };
  final mag = switch (sampler.magFilter) {
    9728 => gpu.MinMagFilter.nearest,
    9729 => gpu.MinMagFilter.linear,
    _ => base.magFilter,
  };
  // minFilter also selects the mip filter (9984-9987 are the mipmapped
  // variants).
  // TODO(gltf-sampler): plain NEAREST/LINEAR (9728/9729) mean base level only,
  // but keep the base mip filter since SamplerOptions has no base-only mip
  // mode. Honor it by building such textures with `mipmaps: false`, which
  // needs the sampler resolved before upload.
  final (min, mip) = switch (sampler.minFilter) {
    9728 => (gpu.MinMagFilter.nearest, base.mipFilter),
    9729 => (gpu.MinMagFilter.linear, base.mipFilter),
    9984 => (gpu.MinMagFilter.nearest, gpu.MipFilter.nearest),
    9985 => (gpu.MinMagFilter.linear, gpu.MipFilter.nearest),
    9986 => (gpu.MinMagFilter.nearest, gpu.MipFilter.linear),
    9987 => (gpu.MinMagFilter.linear, gpu.MipFilter.linear),
    _ => (base.minFilter, base.mipFilter),
  };
  final width = wrap(sampler.wrapS);
  final height = wrap(sampler.wrapT);
  if (width == base.widthAddressMode &&
      height == base.heightAddressMode &&
      min == base.minFilter &&
      mag == base.magFilter &&
      mip == base.mipFilter) {
    return base;
  }
  final allLinear =
      min == gpu.MinMagFilter.linear &&
      mag == gpu.MinMagFilter.linear &&
      mip == gpu.MipFilter.linear;
  return gpu.SamplerOptions(
    minFilter: min,
    magFilter: mag,
    mipFilter: mip,
    widthAddressMode: width,
    heightAddressMode: height,
    maxAnisotropy: allLinear ? base.maxAnisotropy : 1,
  );
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
