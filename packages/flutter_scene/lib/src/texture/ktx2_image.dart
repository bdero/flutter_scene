// Bridges rgba8 pixels and the flutter_scene KTX2 representation: encode rgba8
// into a KTX2 texture carrying our 4x4 block payload, and decode a level back
// to rgba8. Pure data, no GPU; the GPU upload lives in compressed_texture.dart.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/universal_block.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/supercompress/lz.dart';

/// Key/value marker naming the block payload format inside our KTX2 files.
const String kFsBlockFormatKey = 'fsBlockFormat';

/// Current block payload identifier (the [universal_block] layout).
const String kFsBlockFormatUniversal = 'universal/1';

/// Key/value marker set when level payloads are LZ-supercompressed.
const String kFsSupercompressKey = 'fsSupercompress';

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
/// block payload. When [generateMips] is set, a full box-filtered mip chain is
/// built and each level encoded.
Ktx2Texture encodeImageToKtx2(
  Uint8List rgba,
  int width,
  int height, {
  bool generateMips = false,
  bool supercompress = false,
}) {
  if (rgba.length < width * height * 4) {
    throw ArgumentError('rgba is too small for ${width}x$height');
  }
  final blockLevels = <Uint8List>[encodeUniversalBlocks(rgba, width, height)];
  if (generateMips) {
    var w = width, h = height;
    var src = rgba;
    while (w > 1 || h > 1) {
      final nw = math.max(1, w >> 1);
      final nh = math.max(1, h >> 1);
      src = _downsampleBox(src, w, h, nw, nh);
      blockLevels.add(encodeUniversalBlocks(src, nw, nh));
      w = nw;
      h = nh;
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
    },
  );
}

/// Convenience: [encodeImageToKtx2] followed by [writeKtx2].
Uint8List encodeImageToKtx2Bytes(
  Uint8List rgba,
  int width,
  int height, {
  bool generateMips = false,
  bool supercompress = false,
}) => writeKtx2(
  encodeImageToKtx2(
    rgba,
    width,
    height,
    generateMips: generateMips,
    supercompress: supercompress,
  ),
);

/// The pixel dimensions of mip [level] of a [width] x [height] base image.
({int width, int height}) mipSize(int width, int height, int level) =>
    (width: math.max(1, width >> level), height: math.max(1, height >> level));

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

/// Box-filters [src] (rgba8, [sw] x [sh]) down to [dw] x [dh].
// TODO(texture-compression): do gamma-correct downsampling for sRGB base color
// (decode to linear, average, re-encode) instead of averaging in sRGB.
Uint8List _downsampleBox(Uint8List src, int sw, int sh, int dw, int dh) {
  final out = Uint8List(dw * dh * 4);
  for (var y = 0; y < dh; y++) {
    final y0 = y * sh ~/ dh;
    final y1 = math.max(y0 + 1, (y + 1) * sh ~/ dh);
    for (var x = 0; x < dw; x++) {
      final x0 = x * sw ~/ dw;
      final x1 = math.max(x0 + 1, (x + 1) * sw ~/ dw);
      var r = 0, g = 0, b = 0, a = 0, n = 0;
      for (var sy = y0; sy < y1; sy++) {
        for (var sx = x0; sx < x1; sx++) {
          final i = (sy * sw + sx) * 4;
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
          a += src[i + 3];
          n++;
        }
      }
      final o = (y * dw + x) * 4;
      out[o] = r ~/ n;
      out[o + 1] = g ~/ n;
      out[o + 2] = b ~/ n;
      out[o + 3] = a ~/ n;
    }
  }
  return out;
}
