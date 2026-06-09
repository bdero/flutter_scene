// Uploads a flutter_scene KTX2 texture to the GPU. This is the one layer that
// touches Flutter GPU.
//
// The device may support a block-compressed family directly, in which case the
// block payload is transcoded to that format and uploaded compressed (less
// VRAM). Otherwise the payload is decoded to rgba8 and uploaded uncompressed,
// which is always correct and the only path on web today.

import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';

/// Reads a flutter_scene KTX2 file from [bytes] and uploads it as a GPU
/// texture, choosing a compressed upload when the device supports one and
/// falling back to an uncompressed rgba8 upload otherwise.
gpu.Texture gpuTextureFromKtx2(Uint8List bytes) =>
    gpuTextureFromKtx2Texture(readKtx2(bytes));

/// As [gpuTextureFromKtx2], for an already-parsed [texture].
gpu.Texture gpuTextureFromKtx2Texture(Ktx2Texture texture) {
  // TODO(texture-compression): when a transcoder for a supported family exists,
  // pick the best of supportsTextureCompression(astc|bc|etc2), transcode each
  // level's block payload to it, createTexture(format: <compressed>,
  // enableRenderTargetUsage: false, enableShaderWriteUsage: false), and
  // overwrite each mip. Until then every device takes the rgba8 path below.
  return _uploadRgba8(texture);
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
