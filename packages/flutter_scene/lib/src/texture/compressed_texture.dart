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

/// Transcodes each level to BC1 and uploads a compressed, mipped texture.
gpu.Texture _uploadBc1(Ktx2Texture texture) {
  final levelCount = texture.levels.length;
  final base = mipSize(
    texture.pixelWidth,
    texture.pixelHeight < 1 ? 1 : texture.pixelHeight,
    0,
  );
  final result = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    base.width,
    base.height,
    format: gpu.PixelFormat.bc1RGBAUNormInt,
    enableRenderTargetUsage: false,
    enableShaderWriteUsage: false,
    mipLevelCount: levelCount,
  );
  for (var level = 0; level < levelCount; level++) {
    final size = mipSize(
      texture.pixelWidth,
      texture.pixelHeight < 1 ? 1 : texture.pixelHeight,
      level,
    );
    final blocksX = (size.width + 3) ~/ 4;
    final blocksY = (size.height + 3) ~/ 4;
    final bc1 = transcodeUniversalToBc1(
      ktx2LevelBlocks(texture, level),
      blocksX * blocksY,
    );
    result.overwrite(ByteData.sublistView(bc1), mipLevel: level);
  }
  return result;
}

/// Decodes every level to rgba8 and uploads an uncompressed, mipped texture.
gpu.Texture _uploadRgba8(Ktx2Texture texture) {
  final base = decodeKtx2Level(texture, level: 0);
  final levelCount = texture.levels.length;
  final result = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    base.width,
    base.height,
    mipLevelCount: levelCount,
  );
  result.overwrite(ByteData.sublistView(base.rgba), mipLevel: 0);
  for (var level = 1; level < levelCount; level++) {
    final mip = decodeKtx2Level(texture, level: level);
    result.overwrite(ByteData.sublistView(mip.rgba), mipLevel: level);
  }
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
