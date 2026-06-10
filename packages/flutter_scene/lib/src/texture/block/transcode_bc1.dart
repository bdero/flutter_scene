// Transcodes our 4x4 block format to BC1 (DXT1), the desktop BC-family block
// format, plus a CPU decoder used for testing.
//
// BC1 is 8 bytes per 4x4 block: two RGB565 endpoints then sixteen 2-bit
// indices. When color0 > color1 (as unsigned 16-bit) the block is opaque
// 4-color; otherwise it is 3-color-plus-transparent. We always emit the
// 4-color form so output stays opaque (BC1 carries no real alpha; textures
// with alpha transcode to BC3, which reuses this color block).
// TODO(texture-compression): add BC7 for higher quality on desktop.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/universal_block.dart';

/// Bytes per BC1 block.
const int kBc1BlockBytes = 8;

/// Transcodes packed universal blocks to packed BC1 blocks. [blockCount] is the
/// number of 4x4 blocks in [blocks].
Uint8List transcodeUniversalToBc1(Uint8List blocks, int blockCount) {
  final out = Uint8List(blockCount * kBc1BlockBytes);
  for (var b = 0; b < blockCount; b++) {
    transcodeUniversalBlockToBc1(
      blocks,
      b * kBlockBytes,
      out,
      b * kBc1BlockBytes,
    );
  }
  return out;
}

/// Writes one universal block's color line as an 8-byte BC1 block at
/// [out]+[oi]. Also used as the color half of a BC3 block.
void transcodeUniversalBlockToBc1(
  Uint8List src,
  int si,
  Uint8List out,
  int oi,
) {
  // Endpoints, as RGB565.
  var c0 = _pack565(src[si], src[si + 1], src[si + 2]);
  var c1 = _pack565(src[si + 4], src[si + 5], src[si + 6]);
  // 4-color (opaque) mode requires color0 > color1. If swapped, flip the
  // weight direction below.
  final swapped = c0 < c1;
  if (swapped) {
    final t = c0;
    c0 = c1;
    c1 = t;
  }
  out[oi] = c0 & 0xFF;
  out[oi + 1] = (c0 >> 8) & 0xFF;
  out[oi + 2] = c1 & 0xFF;
  out[oi + 3] = (c1 >> 8) & 0xFF;

  // Map each texel's 4-bit weight along the endpoint line to a 2-bit BC1 index.
  // BC1 reconstruction points sit at t = 0 (index 0), 1/3 (index 2), 2/3
  // (index 3), 1 (index 1), measured from color0 to color1.
  var bits = 0;
  for (var i = 0; i < 16; i++) {
    final byte = src[si + 8 + (i >> 1)];
    final w = i.isEven ? byte & 0x0F : (byte >> 4) & 0x0F;
    var t = w / 15.0; // 0 at endpoint 0, 1 at endpoint 1
    if (swapped) t = 1.0 - t;
    final int index;
    if (t < 1 / 6) {
      index = 0;
    } else if (t < 3 / 6) {
      index = 2;
    } else if (t < 5 / 6) {
      index = 3;
    } else {
      index = 1;
    }
    bits |= index << (i * 2);
  }
  out[oi + 4] = bits & 0xFF;
  out[oi + 5] = (bits >> 8) & 0xFF;
  out[oi + 6] = (bits >> 16) & 0xFF;
  out[oi + 7] = (bits >> 24) & 0xFF;
}

int _pack565(int r, int g, int b) =>
    ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);

({int r, int g, int b}) _unpack565(int c) {
  final r5 = (c >> 11) & 0x1F;
  final g6 = (c >> 5) & 0x3F;
  final b5 = c & 0x1F;
  // Expand to 8 bits with bit replication, matching standard BC1 decoders.
  return (
    r: (r5 << 3) | (r5 >> 2),
    g: (g6 << 2) | (g6 >> 4),
    b: (b5 << 3) | (b5 >> 2),
  );
}

/// Decodes packed BC1 blocks to rgba8, dropping the replicated edge texels of
/// partial blocks. For tests and the no-GPU reference path.
Uint8List decodeBc1ToRgba8(Uint8List bc1, int width, int height) {
  final blocksX = (width + kBlockDim - 1) ~/ kBlockDim;
  final blocksY = (height + kBlockDim - 1) ~/ kBlockDim;
  final out = Uint8List(width * height * 4);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final bi = (by * blocksX + bx) * kBc1BlockBytes;
      final c0 = bc1[bi] | (bc1[bi + 1] << 8);
      final c1 = bc1[bi + 2] | (bc1[bi + 3] << 8);
      final e0 = _unpack565(c0);
      final e1 = _unpack565(c1);
      final palette = <List<int>>[
        [e0.r, e0.g, e0.b, 255],
        [e1.r, e1.g, e1.b, 255],
        if (c0 > c1) ...[
          [
            (2 * e0.r + e1.r) ~/ 3,
            (2 * e0.g + e1.g) ~/ 3,
            (2 * e0.b + e1.b) ~/ 3,
            255,
          ],
          [
            (e0.r + 2 * e1.r) ~/ 3,
            (e0.g + 2 * e1.g) ~/ 3,
            (e0.b + 2 * e1.b) ~/ 3,
            255,
          ],
        ] else ...[
          [(e0.r + e1.r) ~/ 2, (e0.g + e1.g) ~/ 2, (e0.b + e1.b) ~/ 2, 255],
          [0, 0, 0, 0],
        ],
      ];
      final bits =
          bc1[bi + 4] |
          (bc1[bi + 5] << 8) |
          (bc1[bi + 6] << 16) |
          (bc1[bi + 7] << 24);
      for (var ty = 0; ty < kBlockDim; ty++) {
        final dy = by * kBlockDim + ty;
        if (dy >= height) break;
        for (var tx = 0; tx < kBlockDim; tx++) {
          final dx = bx * kBlockDim + tx;
          if (dx >= width) continue;
          final i = ty * kBlockDim + tx;
          final color = palette[(bits >> (i * 2)) & 0x3];
          final dst = (dy * width + dx) * 4;
          out[dst] = color[0];
          out[dst + 1] = color[1];
          out[dst + 2] = color[2];
          out[dst + 3] = color[3];
        }
      }
    }
  }
  return out;
}
