// Uploads a flutter_scene KTX2 texture to the GPU. This is the one layer that
// touches Flutter GPU.
//
// The device may support a block-compressed family directly, in which case the
// block payload is transcoded to that format and uploaded compressed (less
// VRAM). Otherwise the payload is decoded to rgba8 and uploaded uncompressed,
// which is always correct and the only path on web today.

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/block/transcode_bc1.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';

/// Reads a flutter_scene KTX2 file from [bytes] and uploads it as a GPU
/// texture, choosing a compressed upload when the device supports one and
/// falling back to an uncompressed rgba8 upload otherwise.
gpu.Texture gpuTextureFromKtx2(Uint8List bytes) =>
    gpuTextureFromKtx2Texture(readKtx2(bytes));

/// As [gpuTextureFromKtx2], for an already-parsed [texture].
gpu.Texture gpuTextureFromKtx2Texture(Ktx2Texture texture) {
  _logFamiliesOnce();
  // Prefer a compressed upload when both the device and a transcoder support
  // the family. Only BC1 is implemented today.
  // TODO(texture-compression): add ASTC and ETC2 transcoders (the Apple and
  // mobile families) and prefer ASTC > BC > ETC2 per the plan.
  if (gpu.gpuContext.supportsTextureCompression(
    gpu.TextureCompressionFamily.bc,
  )) {
    return _uploadBc1(texture);
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
