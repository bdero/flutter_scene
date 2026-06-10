// Transcodes our 4x4 block format to BC3 (DXT5), the desktop BC-family block
// format for textures with alpha, plus a CPU decoder used for testing.
//
// BC3 is 16 bytes per 4x4 block: an 8-byte alpha block (two 8-bit alpha
// endpoints then sixteen 3-bit indices, LSB-first) followed by the 8-byte BC1
// color block (whose 3-color-plus-transparent mode is disabled in BC3, so any
// endpoint order decodes as 4-color). The alpha endpoints come straight from
// the universal block's alpha line; alpha shares the color weights, matching
// how the universal block stores them.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/transcode_bc1.dart';
import 'package:flutter_scene/src/texture/block/universal_block.dart';

/// Bytes per BC3 block.
const int kBc3BlockBytes = 16;

/// Transcodes packed universal blocks to packed BC3 blocks. [blockCount] is
/// the number of 4x4 blocks in [blocks].
Uint8List transcodeUniversalToBc3(Uint8List blocks, int blockCount) {
  final out = Uint8List(blockCount * kBc3BlockBytes);
  for (var b = 0; b < blockCount; b++) {
    final si = b * kBlockBytes;
    final oi = b * kBc3BlockBytes;
    _transcodeAlphaBlock(blocks, si, out, oi);
    transcodeUniversalBlockToBc1(blocks, si, out, oi + 8);
  }
  return out;
}

void _transcodeAlphaBlock(Uint8List src, int si, Uint8List out, int oi) {
  var a0 = src[si + 3];
  var a1 = src[si + 7];
  // The 8-interpolant mode requires alpha0 > alpha1; equal endpoints encode
  // as-is (every index decodes to the same value through index 0/1).
  final swapped = a0 < a1;
  if (swapped) {
    final t = a0;
    a0 = a1;
    a1 = t;
  }
  out[oi] = a0;
  out[oi + 1] = a1;

  // BC3 8-interpolant reconstruction points, in index order: a0, a1, then six
  // evenly spaced lerps from a0 to a1.
  final points = List<int>.generate(8, (index) {
    if (index == 0) return a0;
    if (index == 1) return a1;
    return ((8 - index) * a0 + (index - 1) * a1) ~/ 7;
  });

  // Map each texel's 4-bit weight along the alpha line to the nearest
  // reconstruction point, then pack 16 x 3-bit indices LSB-first. Bits are
  // written byte-wise (no wide shifts) so the math stays exact on the web.
  for (var i = 0; i < 16; i++) {
    final byte = src[si + 8 + (i >> 1)];
    final w = i.isEven ? byte & 0x0F : (byte >> 4) & 0x0F;
    var t = w / 15.0;
    if (swapped) t = 1.0 - t;
    final target = (a0 + (a1 - a0) * t).round();
    var best = 0;
    var bestError = 1 << 30;
    for (var p = 0; p < 8; p++) {
      final error = (points[p] - target).abs();
      if (error < bestError) {
        bestError = error;
        best = p;
      }
    }
    for (var b = 0; b < 3; b++) {
      if ((best >> b) & 1 != 0) {
        final pos = i * 3 + b;
        out[oi + 2 + (pos >> 3)] |= 1 << (pos & 7);
      }
    }
  }
}

/// Decodes packed BC3 blocks to rgba8, the CPU reference for tests.
Uint8List decodeBc3ToRgba8(Uint8List bc3, int width, int height) {
  final blocksX = (width + 3) ~/ 4;
  final blocksY = (height + 3) ~/ 4;
  final out = Uint8List(width * height * 4);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final base = (by * blocksX + bx) * kBc3BlockBytes;

      // Alpha half.
      final a0 = bc3[base];
      final a1 = bc3[base + 1];
      final points = List<int>.generate(8, (index) {
        if (index == 0) return a0;
        if (index == 1) return a1;
        if (a0 > a1) {
          return ((8 - index) * a0 + (index - 1) * a1) ~/ 7;
        }
        // 6-interpolant mode (a0 <= a1): four lerps then 0 and 255.
        if (index < 6) return ((6 - index) * a0 + (index - 1) * a1) ~/ 5;
        return index == 6 ? 0 : 255;
      });
      int alphaIndex(int i) {
        var index = 0;
        for (var b = 0; b < 3; b++) {
          final pos = i * 3 + b;
          if ((bc3[base + 2 + (pos >> 3)] >> (pos & 7)) & 1 != 0) {
            index |= 1 << b;
          }
        }
        return index;
      }

      // Color half decodes through the BC1 reference (BC3's color block is
      // always 4-color, which the BC1 path emits).
      final colorRgba = decodeBc1ToRgba8(
        Uint8List.sublistView(bc3, base + 8, base + 16),
        4,
        4,
      );

      for (var ty = 0; ty < 4; ty++) {
        final y = by * 4 + ty;
        if (y >= height) break;
        for (var tx = 0; tx < 4; tx++) {
          final x = bx * 4 + tx;
          if (x >= width) continue;
          final i = ty * 4 + tx;
          final dst = (y * width + x) * 4;
          out[dst] = colorRgba[i * 4];
          out[dst + 1] = colorRgba[i * 4 + 1];
          out[dst + 2] = colorRgba[i * 4 + 2];
          out[dst + 3] = points[alphaIndex(i)];
        }
      }
    }
  }
  return out;
}
