// Bridges rgba8 pixels and the flutter_scene KTX2 representation: encode rgba8
// into a KTX2 texture carrying our 4x4 block payload, and decode a level back
// to rgba8. Pure data, no GPU; the GPU upload lives in compressed_texture.dart.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/universal_block.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/supercompress/lz.dart';

/// Key/value marker naming the block payload format inside our KTX2 files.
const String kFsBlockFormatKey = 'fsBlockFormat';

/// Current block payload identifier (the [universal_block] layout).
const String kFsBlockFormatUniversal = 'universal/1';

/// Key/value marker set when level payloads are LZ-supercompressed.
const String kFsSupercompressKey = 'fsSupercompress';

/// Key/value marker set when the source image carries non-opaque alpha. The
/// transcoder picks an alpha-capable GPU format (or the rgba8 fallback) for
/// marked textures and the smaller opaque formats otherwise.
const String kFsAlphaKey = 'fsAlpha';

/// Whether [texture] was encoded from a source with non-opaque alpha.
bool ktx2HasAlpha(Ktx2Texture texture) =>
    texture.keyValues.containsKey(kFsAlphaKey);

/// Identifier for the [lz] supercompression of the block payload.
const String kFsSupercompressLz = 'lz/1';

/// Bytes a level's block payload occupies once decompressed, derived from the
/// image dimensions (one byte per texel, padded to whole 4x4 blocks).
int _levelBlockBytes(int width, int height, int level) {
  final size = mipSize(width, math.max(1, height), level);
  final blocksX = (size.width + kBlockDim - 1) ~/ kBlockDim;
  final blocksY = (size.height + kBlockDim - 1) ~/ kBlockDim;
  return blocksX * blocksY * kBlockBytes;
}

/// Encodes [width] x [height] rgba8 pixels into a KTX2 texture holding our 4x4
/// block payload. When [generateMips] is set, a mip chain is built with the
/// downsample appropriate for [content] (sRGB color averages in linear light,
/// normals renormalize) and each level encoded.
Ktx2Texture encodeImageToKtx2(
  Uint8List rgba,
  int width,
  int height, {
  bool generateMips = false,
  TextureContent content = TextureContent.color,
  bool supercompress = false,
}) {
  if (rgba.length < width * height * 4) {
    throw ArgumentError('rgba is too small for ${width}x$height');
  }
  var hasAlpha = false;
  for (var i = 3; i < width * height * 4; i += 4) {
    if (rgba[i] != 255) {
      hasAlpha = true;
      break;
    }
  }
  final blockLevels = <Uint8List>[encodeUniversalBlocks(rgba, width, height)];
  if (generateMips) {
    final levelCount = engineMipLevelCount(width, height);
    final chain = generateMipChain(rgba, width, height, content);
    for (var level = 1; level < levelCount; level++) {
      final mip = chain[level];
      blockLevels.add(encodeUniversalBlocks(mip.pixels, mip.width, mip.height));
    }
  }
  final levels = [
    for (final blocks in blockLevels)
      Ktx2Level(
        data: supercompress ? lzCompress(blocks) : blocks,
        uncompressedByteLength: blocks.length,
      ),
  ];
  return Ktx2Texture(
    vkFormat:
        0, // VK_FORMAT_UNDEFINED; the block format is in the marker above.
    dataFormatDescriptor: buildBasicDataFormatDescriptor(
      bytesPerBlock: kBlockBytes,
    ),
    pixelWidth: width,
    pixelHeight: height,
    levels: levels,
    keyValues: {
      kFsBlockFormatKey: Uint8List.fromList(
        utf8.encode(kFsBlockFormatUniversal),
      ),
      if (supercompress)
        kFsSupercompressKey: Uint8List.fromList(
          utf8.encode(kFsSupercompressLz),
        ),
      if (hasAlpha) kFsAlphaKey: Uint8List.fromList(utf8.encode('1')),
    },
  );
}

/// Convenience: [encodeImageToKtx2] followed by [writeKtx2].
Uint8List encodeImageToKtx2Bytes(
  Uint8List rgba,
  int width,
  int height, {
  bool generateMips = false,
  TextureContent content = TextureContent.color,
  bool supercompress = false,
}) => writeKtx2(
  encodeImageToKtx2(
    rgba,
    width,
    height,
    generateMips: generateMips,
    content: content,
    supercompress: supercompress,
  ),
);

/// The pixel dimensions of mip [level] of a [width] x [height] base image.
({int width, int height}) mipSize(int width, int height, int level) =>
    (width: math.max(1, width >> level), height: math.max(1, height >> level));

/// The number of mip levels Flutter GPU expects for a [width] x [height]
/// texture. The engine stops one level short of 1x1, so a generated mip chain
/// matches what `createTexture(mipLevelCount:)` accepts (this mirrors the web
/// shim's `fullMipCount`). Returns at least 1.
int engineMipLevelCount(int width, int height) {
  final smallest = width < height ? width : height;
  if (smallest < 1) return 1;
  final count = smallest.bitLength - 1;
  return count > 0 ? count : 1;
}

/// Decodes one [level] of a flutter_scene KTX2 texture back to rgba8. Throws if
/// the file is not in our block format.
({Uint8List rgba, int width, int height}) decodeKtx2Level(
  Ktx2Texture texture, {
  int level = 0,
}) {
  final marker = texture.keyValues[kFsBlockFormatKey];
  if (marker != null && utf8.decode(marker) != kFsBlockFormatUniversal) {
    throw Ktx2FormatException(
      'Unsupported block format: ${utf8.decode(marker)}',
    );
  }
  if (level < 0 || level >= texture.levels.length) {
    throw Ktx2FormatException('No level $level in texture');
  }
  final size = mipSize(
    texture.pixelWidth,
    math.max(1, texture.pixelHeight),
    level,
  );
  final blocks = _levelPayload(texture, level);
  return (
    rgba: decodeUniversalBlocksToRgba8(blocks, size.width, size.height),
    width: size.width,
    height: size.height,
  );
}

/// The decompressed 4x4 block payload for [level], ready to decode to rgba8 or
/// transcode to a GPU block format. Undoes LZ supercompression when present.
Uint8List ktx2LevelBlocks(Ktx2Texture texture, int level) =>
    _levelPayload(texture, level);

/// Returns a level's block bytes, undoing our LZ supercompression when the
/// marker is present. The container's own supercompressionScheme stays `none`;
/// our LZ is a payload-level wrapper signaled by [kFsSupercompressKey].
Uint8List _levelPayload(Ktx2Texture texture, int level) {
  final stored = texture.levels[level].data;
  final marker = texture.keyValues[kFsSupercompressKey];
  if (marker == null) return stored;
  if (utf8.decode(marker) != kFsSupercompressLz) {
    throw Ktx2FormatException(
      'Unknown supercompression: ${utf8.decode(marker)}',
    );
  }
  return lzDecompress(
    stored,
    _levelBlockBytes(texture.pixelWidth, texture.pixelHeight, level),
  );
}
