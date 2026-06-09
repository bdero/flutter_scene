// Transcodes our 4x4 block format to ETC2 RGB8 (the GLES3 / WebGL2 / mobile
// family), plus a CPU decoder for testing.
//
// We emit ETC1-subset blocks (individual and differential modes), which every
// ETC2 RGB8 sampler decodes. Transcoding goes through rgba: each universal
// block is decoded to 16 texels, then ETC1-encoded. ETC2 RGB8 is 8 bytes per
// 4x4 block (opaque); textures with alpha need a separate path.
// TODO(texture-compression): add the ETC2 T/H/planar modes for higher quality,
// and ETC2 RGBA8 (with the EAC alpha block) for textures with alpha.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/universal_block.dart';

/// Bytes per ETC2 RGB8 block.
const int kEtc2Rgb8BlockBytes = 8;

// Intensity modifier sets, indexed [tableCodeword][pixelIndex], where the
// pixel index is (msb << 1) | lsb. Ordered {small+, large+, small-, large-}.
const List<List<int>> _modifier = [
  [2, 8, -2, -8],
  [5, 17, -5, -17],
  [9, 29, -9, -29],
  [13, 42, -13, -42],
  [18, 60, -18, -60],
  [24, 80, -24, -80],
  [33, 106, -33, -106],
  [47, 183, -47, -183],
];

/// Transcodes packed universal blocks to packed ETC2 RGB8 blocks. [blockCount]
/// is the number of 4x4 blocks.
Uint8List transcodeUniversalToEtc2Rgb(Uint8List blocks, int blockCount) {
  final out = Uint8List(blockCount * kEtc2Rgb8BlockBytes);
  final rgb = Int32List(16 * 3);
  for (var b = 0; b < blockCount; b++) {
    _decodeUniversalToRgb(blocks, b * kBlockBytes, rgb);
    _encodeEtc1Block(rgb, out, b * kEtc2Rgb8BlockBytes);
  }
  return out;
}

int _clampByte(int v) => v < 0
    ? 0
    : v > 255
    ? 255
    : v;

/// Decodes one universal block to 16 RGB texels (alpha dropped), texel
/// i = row*4 + col.
void _decodeUniversalToRgb(Uint8List blocks, int offset, Int32List rgb) {
  final e0 = [blocks[offset], blocks[offset + 1], blocks[offset + 2]];
  final e1 = [blocks[offset + 4], blocks[offset + 5], blocks[offset + 6]];
  for (var i = 0; i < 16; i++) {
    final byte = blocks[offset + 8 + (i >> 1)];
    final w = i.isEven ? byte & 0x0F : (byte >> 4) & 0x0F;
    for (var c = 0; c < 3; c++) {
      rgb[i * 3 + c] = (e0[c] * (15 - w) + e1[c] * w + 7) ~/ 15;
    }
  }
}

// Pixel layout within an ETC1 block: texel index p = x * 4 + y (x is the
// column 0..3, y the row 0..3). Our texel index i = y * 4 + x, so map between
// them when reading/writing pixels.
int _etcPixelIndex(int x, int y) => x * 4 + y;

/// Encodes 16 RGB texels (texel i = y*4 + x) to one ETC1 block at [out]/[oi].
void _encodeEtc1Block(Int32List rgb, Uint8List out, int oi) {
  var bestErr = -1;
  var bestHigh = 0, bestLow = 0;

  for (var flip = 0; flip < 2; flip++) {
    // The two subblocks' texel coordinates.
    final subA = <int>[]; // our texel indices (y*4 + x)
    final subB = <int>[];
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final inA = flip == 0 ? x < 2 : y < 2;
        (inA ? subA : subB).add(y * 4 + x);
      }
    }

    // Average color per subblock.
    final avgA = _avg(rgb, subA);
    final avgB = _avg(rgb, subB);

    // Individual mode: each base is RGB444.
    final q444a = _quant444(avgA);
    final q444b = _quant444(avgB);
    final baseAi = _expand444(q444a);
    final baseBi = _expand444(q444b);
    final fitAi = _fitSubblock(rgb, subA, baseAi);
    final fitBi = _fitSubblock(rgb, subB, baseBi);
    final errI = fitAi.error + fitBi.error;

    // Differential mode: base1 RGB555, base2 = base1 + 3-bit signed delta.
    final q1 = _quant555(avgA);
    final q2 = _quant555(avgB);
    var feasible = true;
    final delta = List<int>.filled(3, 0);
    for (var c = 0; c < 3; c++) {
      delta[c] = q2[c] - q1[c];
      if (delta[c] < -4 || delta[c] > 3) feasible = false;
    }
    var useDiff = false;
    late _Fit fitAd, fitBd;
    if (feasible) {
      final baseAd = _expand555(q1);
      final baseBd = _expand555([
        q1[0] + delta[0],
        q1[1] + delta[1],
        q1[2] + delta[2],
      ]);
      fitAd = _fitSubblock(rgb, subA, baseAd);
      fitBd = _fitSubblock(rgb, subB, baseBd);
      final errD = fitAd.error + fitBd.error;
      useDiff = errD <= errI;
    }

    final int err;
    final int high;
    if (useDiff) {
      err = fitAd.error + fitBd.error;
      high = _packHighDiff(q1, delta, fitAd.table, fitBd.table, flip);
    } else {
      err = errI;
      high = _packHighIndividual(q444a, q444b, fitAi.table, fitBi.table, flip);
    }
    final low = _packPixels(
      flip,
      subA,
      useDiff ? fitAd.indices : fitAi.indices,
      subB,
      useDiff ? fitBd.indices : fitBi.indices,
    );

    if (bestErr < 0 || err < bestErr) {
      bestErr = err;
      bestHigh = high;
      bestLow = low;
    }
  }

  out[oi] = (bestHigh >> 24) & 0xFF;
  out[oi + 1] = (bestHigh >> 16) & 0xFF;
  out[oi + 2] = (bestHigh >> 8) & 0xFF;
  out[oi + 3] = bestHigh & 0xFF;
  out[oi + 4] = (bestLow >> 24) & 0xFF;
  out[oi + 5] = (bestLow >> 16) & 0xFF;
  out[oi + 6] = (bestLow >> 8) & 0xFF;
  out[oi + 7] = bestLow & 0xFF;
}

class _Fit {
  _Fit(this.table, this.indices, this.error);
  final int table;
  final List<int> indices; // per pixel of the subblock, 0..3
  final int error;
}

List<int> _avg(Int32List rgb, List<int> texels) {
  var r = 0, g = 0, b = 0;
  for (final i in texels) {
    r += rgb[i * 3];
    g += rgb[i * 3 + 1];
    b += rgb[i * 3 + 2];
  }
  final n = texels.length;
  return [(r + n ~/ 2) ~/ n, (g + n ~/ 2) ~/ n, (b + n ~/ 2) ~/ n];
}

/// Picks the table codeword and per-pixel indices minimizing error for a fixed
/// [base] color.
_Fit _fitSubblock(Int32List rgb, List<int> texels, List<int> base) {
  var bestTable = 0;
  var bestErr = -1;
  late List<int> bestIndices;
  for (var t = 0; t < 8; t++) {
    final indices = List<int>.filled(texels.length, 0);
    var total = 0;
    for (var p = 0; p < texels.length; p++) {
      final i = texels[p];
      var pErr = -1;
      var pIdx = 0;
      for (var idx = 0; idx < 4; idx++) {
        final m = _modifier[t][idx];
        var e = 0;
        for (var c = 0; c < 3; c++) {
          final d = _clampByte(base[c] + m) - rgb[i * 3 + c];
          e += d * d;
        }
        if (pErr < 0 || e < pErr) {
          pErr = e;
          pIdx = idx;
        }
      }
      indices[p] = pIdx;
      total += pErr;
    }
    if (bestErr < 0 || total < bestErr) {
      bestErr = total;
      bestTable = t;
      bestIndices = indices;
    }
  }
  return _Fit(bestTable, bestIndices, bestErr);
}

List<int> _quant444(List<int> c) => [c[0] >> 4, c[1] >> 4, c[2] >> 4];
List<int> _quant555(List<int> c) => [c[0] >> 3, c[1] >> 3, c[2] >> 3];
List<int> _expand444(List<int> q) {
  final out = List<int>.filled(3, 0);
  for (var i = 0; i < 3; i++) {
    final v = q[i] & 0xF;
    out[i] = (v << 4) | v;
  }
  return out;
}

int _packPixels(
  int flip,
  List<int> subA,
  List<int> idxA,
  List<int> subB,
  List<int> idxB,
) {
  var low = 0;
  void place(int texel, int idx) {
    final x = texel % 4;
    final y = texel ~/ 4;
    final p = _etcPixelIndex(x, y); // 0..15
    final msb = (idx >> 1) & 1;
    final lsb = idx & 1;
    low |= msb << (16 + p);
    low |= lsb << p;
  }

  for (var k = 0; k < subA.length; k++) {
    place(subA[k], idxA[k]);
  }
  for (var k = 0; k < subB.length; k++) {
    place(subB[k], idxB[k]);
  }
  return low & 0xFFFFFFFF;
}

int _packHighIndividual(
  List<int> q444a,
  List<int> q444b,
  int table1,
  int table2,
  int flip,
) {
  var high = 0;
  high |= q444a[0] << 28;
  high |= q444b[0] << 24;
  high |= q444a[1] << 20;
  high |= q444b[1] << 16;
  high |= q444a[2] << 12;
  high |= q444b[2] << 8;
  high |= table1 << 5;
  high |= table2 << 2;
  high |= 0 << 1; // diffbit = 0
  high |= flip;
  return high & 0xFFFFFFFF;
}

int _packHighDiff(
  List<int> base555,
  List<int> delta,
  int table1,
  int table2,
  int flip,
) {
  var high = 0;
  high |= base555[0] << 27;
  high |= (delta[0] & 0x7) << 24;
  high |= base555[1] << 19;
  high |= (delta[1] & 0x7) << 16;
  high |= base555[2] << 11;
  high |= (delta[2] & 0x7) << 8;
  high |= table1 << 5;
  high |= table2 << 2;
  high |= 1 << 1; // diffbit = 1
  high |= flip;
  return high & 0xFFFFFFFF;
}

/// Decodes packed ETC2 RGB8 (ETC1-subset) blocks to rgba8, for tests.
Uint8List decodeEtc2RgbToRgba8(Uint8List etc2, int width, int height) {
  final blocksX = (width + kBlockDim - 1) ~/ kBlockDim;
  final blocksY = (height + kBlockDim - 1) ~/ kBlockDim;
  final out = Uint8List(width * height * 4);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final bi = (by * blocksX + bx) * kEtc2Rgb8BlockBytes;
      final high =
          (etc2[bi] << 24) |
          (etc2[bi + 1] << 16) |
          (etc2[bi + 2] << 8) |
          etc2[bi + 3];
      final low =
          (etc2[bi + 4] << 24) |
          (etc2[bi + 5] << 16) |
          (etc2[bi + 6] << 8) |
          etc2[bi + 7];
      final diff = (high >> 1) & 1;
      final flip = high & 1;
      final table1 = (high >> 5) & 0x7;
      final table2 = (high >> 2) & 0x7;

      final List<int> baseA, baseB;
      if (diff == 1) {
        final r = (high >> 27) & 0x1F;
        final g = (high >> 19) & 0x1F;
        final b = (high >> 11) & 0x1F;
        final dr = _signed3((high >> 24) & 0x7);
        final dg = _signed3((high >> 16) & 0x7);
        final db = _signed3((high >> 8) & 0x7);
        baseA = _expand555([r, g, b]);
        baseB = _expand555([r + dr, g + dg, b + db]);
      } else {
        baseA = _expand444([
          (high >> 28) & 0xF,
          (high >> 20) & 0xF,
          (high >> 12) & 0xF,
        ]);
        baseB = _expand444([
          (high >> 24) & 0xF,
          (high >> 16) & 0xF,
          (high >> 8) & 0xF,
        ]);
      }

      for (var y = 0; y < 4; y++) {
        final dy = by * 4 + y;
        if (dy >= height) continue;
        for (var x = 0; x < 4; x++) {
          final dx = bx * 4 + x;
          if (dx >= width) continue;
          final p = _etcPixelIndex(x, y);
          final msb = (low >> (16 + p)) & 1;
          final lsb = (low >> p) & 1;
          final idx = (msb << 1) | lsb;
          final inA = flip == 0 ? x < 2 : y < 2;
          final base = inA ? baseA : baseB;
          final m = _modifier[inA ? table1 : table2][idx];
          final dst = (dy * width + dx) * 4;
          out[dst] = _clampByte(base[0] + m);
          out[dst + 1] = _clampByte(base[1] + m);
          out[dst + 2] = _clampByte(base[2] + m);
          out[dst + 3] = 255;
        }
      }
    }
  }
  return out;
}

int _signed3(int v) => v >= 4 ? v - 8 : v;
List<int> _expand555(List<int> c) {
  final out = List<int>.filled(3, 0);
  for (var i = 0; i < 3; i++) {
    final v = c[i] & 0x1F;
    out[i] = (v << 3) | (v >> 2);
  }
  return out;
}
