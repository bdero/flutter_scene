// Uploads a flutter_scene KTX2 texture to the GPU. This is the one layer that
// touches Flutter GPU.
//
// The device may support a block-compressed family directly, in which case the
// block payload is transcoded to that format and uploaded compressed (less
// VRAM). Otherwise the payload is decoded to rgba8 and uploaded uncompressed,
// which is always correct and the only path on web today.

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/block/transcode_astc.dart';
import 'package:flutter_scene/src/texture/block/transcode_bc1.dart';
import 'package:flutter_scene/src/texture/block/transcode_etc2.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';

/// The order in which compressed families are preferred when the device
/// supports more than one: ASTC (highest quality) > BC (desktop) > ETC2
/// (mobile/GLES3/web). Reorder for testing a specific family on a device that
/// supports several.
List<gpu.TextureCompressionFamily> compressionFamilyPreference = [
  gpu.TextureCompressionFamily.astc,
  gpu.TextureCompressionFamily.bc,
  gpu.TextureCompressionFamily.etc2,
];

/// Reads a flutter_scene KTX2 file from [bytes] and uploads it as a GPU
/// texture, choosing a compressed upload when the device supports one and
/// falling back to an uncompressed rgba8 upload otherwise.
gpu.Texture gpuTextureFromKtx2(Uint8List bytes) =>
    gpuTextureFromKtx2Texture(readKtx2(bytes));

/// As [gpuTextureFromKtx2], for an already-parsed [texture].
gpu.Texture gpuTextureFromKtx2Texture(Ktx2Texture texture) {
  _logFamiliesOnce();
  // Transcode to the first supported family in the preference order for which
  // we have a transcoder; otherwise decode to rgba8 and upload uncompressed.
  for (final family in compressionFamilyPreference) {
    if (!gpu.gpuContext.supportsTextureCompression(family)) continue;
    if (family == gpu.TextureCompressionFamily.astc) {
      return _uploadAstc(texture);
    }
    if (family == gpu.TextureCompressionFamily.bc) return _uploadBc1(texture);
    if (family == gpu.TextureCompressionFamily.etc2) {
      return _uploadEtc2(texture);
    }
  }
  return _uploadRgba8(texture);
}

// TODO(texture-compression): upload the full mip chain once Flutter GPU can
// mark/generate sampleable mipmaps. Today there is no generateMipmaps API and
// Impeller does not treat per-level overwrite as a generated mipmap (it warns
// "mip count > 1, but the mipmap has not been generated" and samples wrong), so
// the base level is uploaded alone. The KTX2 still carries the precomputed
// chain for when the engine supports it.

/// Transcodes the base level to BC1 and uploads a compressed texture.
gpu.Texture _uploadBc1(Ktx2Texture texture) {
  final size = mipSize(
    texture.pixelWidth,
    texture.pixelHeight < 1 ? 1 : texture.pixelHeight,
    0,
  );
  final blocksX = (size.width + 3) ~/ 4;
  final blocksY = (size.height + 3) ~/ 4;
  final bc1 = transcodeUniversalToBc1(
    ktx2LevelBlocks(texture, 0),
    blocksX * blocksY,
  );
  final result = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    size.width,
    size.height,
    format: gpu.PixelFormat.bc1RGBAUNormInt,
    enableRenderTargetUsage: false,
    enableShaderWriteUsage: false,
  );
  result.overwrite(ByteData.sublistView(bc1));
  return result;
}

/// Transcodes the base level to ETC2 RGB8 and uploads a compressed texture.
gpu.Texture _uploadEtc2(Ktx2Texture texture) {
  final size = mipSize(
    texture.pixelWidth,
    texture.pixelHeight < 1 ? 1 : texture.pixelHeight,
    0,
  );
  final blocksX = (size.width + 3) ~/ 4;
  final blocksY = (size.height + 3) ~/ 4;
  final etc2 = transcodeUniversalToEtc2Rgb(
    ktx2LevelBlocks(texture, 0),
    blocksX * blocksY,
  );
  final result = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    size.width,
    size.height,
    format: gpu.PixelFormat.etc2RGB8UNormInt,
    enableRenderTargetUsage: false,
    enableShaderWriteUsage: false,
  );
  result.overwrite(ByteData.sublistView(etc2));
  return result;
}

/// Transcodes the base level to ASTC 4x4 LDR and uploads a compressed texture.
gpu.Texture _uploadAstc(Ktx2Texture texture) {
  final size = mipSize(
    texture.pixelWidth,
    texture.pixelHeight < 1 ? 1 : texture.pixelHeight,
    0,
  );
  final blocksX = (size.width + 3) ~/ 4;
  final blocksY = (size.height + 3) ~/ 4;
  final astc = transcodeUniversalToAstc4x4(
    ktx2LevelBlocks(texture, 0),
    blocksX * blocksY,
  );
  final result = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    size.width,
    size.height,
    format: gpu.PixelFormat.astc4x4LDR,
    enableRenderTargetUsage: false,
    enableShaderWriteUsage: false,
  );
  result.overwrite(ByteData.sublistView(astc));
  return result;
}

/// Decodes the base level to rgba8 and uploads an uncompressed texture.
gpu.Texture _uploadRgba8(Ktx2Texture texture) {
  final base = decodeKtx2Level(texture, level: 0);
  final result = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    base.width,
    base.height,
  );
  result.overwrite(ByteData.sublistView(base.rgba));
  return result;
}

bool _logged = false;

/// Logs the device's block-compression family support once. This doubles as the
/// device probe: running an app that loads a KTX2 texture reports which
/// families are available and therefore which upload path is taken.
void _logFamiliesOnce() {
  if (_logged) return;
  _logged = true;
  final context = gpu.gpuContext;
  debugPrint(
    'flutter_scene texture compression support: '
    'bc=${context.supportsTextureCompression(gpu.TextureCompressionFamily.bc)} '
    'etc2=${context.supportsTextureCompression(gpu.TextureCompressionFamily.etc2)} '
    'astc=${context.supportsTextureCompression(gpu.TextureCompressionFamily.astc)} '
    '(bc -> BC1 upload; otherwise rgba8 fallback)',
  );
}
