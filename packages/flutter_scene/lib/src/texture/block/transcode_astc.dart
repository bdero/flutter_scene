// Transcodes our 4x4 block format to ASTC 4x4 LDR (the Apple / modern-mobile
// family), plus a CPU decoder for testing.
//
// We emit ONE fixed ASTC configuration so the encoder stays tractable:
//   - 4x4 block footprint, 4x4 weight grid (16 weights, one per texel)
//   - single plane, single partition
//   - color endpoint mode 8 (LDR RGB direct), 6 endpoint integers
//   - 8-bit (QUANT_256) endpoints, 3-bit (range 7) weights, both pure-bit ISE
//
// Block layout (128 bits, byte 0 = bits 0..7):
//   bits [10:0]   block mode 0x53 (4x4 grid, range 7, single plane)
//   bits [12:11]  partition count - 1 = 0
//   bits [16:13]  CEM = 8
//   bits [64:17]  endpoints v0..v5, 8 bits each, LSB-first
//   bits [79:65]  unused
//   bits [127:80] weights, 16 x 3 bits, written reversed from bit 127 down
//
// The exact A/B size-field bit positions, the weight bit-reversal, and the
// endpoint ordering are reconstructed from the ASTC spec and reference
// decoders; GPU acceptance of these bytes is confirmed by on-device rendering.
// TODO(texture-compression): widen beyond this single config (other ranges,
// dual plane, RGBA via CEM 12 for alpha) once the base config is GPU-confirmed.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/universal_block.dart';

/// Bytes per ASTC 4x4 block.
const int kAstcBlockBytes = 16;

const int _astcBlockMode = 0x53; // 4x4 grid, weight range 7, single plane
const int _astcCem = 8; // LDR RGB direct
const int _weightLevels = 8; // range 7 -> 0..7
const int _weightBits = 3;
const int _numWeights = 16;
const int _weightDataBits = _numWeights * _weightBits; // 48 (weights at 127:80)
const int _endpointStartBit = 17;

/// Transcodes packed universal blocks to packed ASTC 4x4 LDR blocks.
/// [blockCount] is the number of 4x4 blocks.
Uint8List transcodeUniversalToAstc4x4(Uint8List blocks, int blockCount) {
  final out = Uint8List(blockCount * kAstcBlockBytes);
  for (var b = 0; b < blockCount; b++) {
    _transcodeBlock(blocks, b * kBlockBytes, out, b * kAstcBlockBytes);
  }
  return out;
}

void _setBit(Uint8List blk, int base, int bit, int value) {
  if (value != 0) blk[base + (bit >> 3)] |= 1 << (bit & 7);
}

void _setBits(Uint8List blk, int base, int start, int count, int value) {
  for (var j = 0; j < count; j++) {
    _setBit(blk, base, start + j, (value >> j) & 1);
  }
}

int _round(double v) => (v + 0.5).floor();

void _transcodeBlock(Uint8List src, int si, Uint8List out, int oi) {
  final e0 = [src[si], src[si + 1], src[si + 2]];
  final e1 = [src[si + 4], src[si + 5], src[si + 6]];

  // Order endpoints so the higher-luma one is the odd (v1,v3,v5) endpoint; with
  // sum(odd) >= sum(even) the decoder takes the direct path (no blue contract).
  final sum0 = e0[0] + e0[1] + e0[2];
  final sum1 = e1[0] + e1[1] + e1[2];
  final low = sum1 >= sum0 ? e0 : e1;
  final high = sum1 >= sum0 ? e1 : e0;
  final flip = sum1 < sum0;

  // Config.
  _setBits(out, oi, 0, 11, _astcBlockMode);
  _setBits(out, oi, 11, 2, 0); // 1 partition
  _setBits(out, oi, 13, 4, _astcCem);

  // Endpoints v0..v5 = (low.r, high.r, low.g, high.g, low.b, high.b), 8 bits.
  final v = [low[0], high[0], low[1], high[1], low[2], high[2]];
  var pos = _endpointStartBit;
  for (final value in v) {
    _setBits(out, oi, pos, 8, value);
    pos += 8;
  }

  // Weights: build the ISE bitstream (LSB-first per weight, weights in raster
  // order), then place it reversed into the top of the block.
  final ws = Uint8List(_weightDataBits);
  for (var i = 0; i < _numWeights; i++) {
    final byte = src[si + 8 + (i >> 1)];
    final w16 = i.isEven ? byte & 0x0F : (byte >> 4) & 0x0F;
    final t = (flip ? (15 - w16) : w16) / 15.0;
    final w = _round(t * (_weightLevels - 1)).clamp(0, _weightLevels - 1);
    for (var b = 0; b < _weightBits; b++) {
      ws[i * _weightBits + b] = (w >> b) & 1;
    }
  }
  for (var k = 0; k < _weightDataBits; k++) {
    _setBit(out, oi, 127 - k, ws[k]);
  }
}

int _getBit(Uint8List blk, int base, int bit) =>
    (blk[base + (bit >> 3)] >> (bit & 7)) & 1;

int _getBits(Uint8List blk, int base, int start, int count) {
  var value = 0;
  for (var j = 0; j < count; j++) {
    value |= _getBit(blk, base, start + j) << j;
  }
  return value;
}

/// Decodes packed ASTC 4x4 blocks (our fixed config only) to rgba8, for tests.
Uint8List decodeAstc4x4ToRgba8(Uint8List astc, int width, int height) {
  final blocksX = (width + kBlockDim - 1) ~/ kBlockDim;
  final blocksY = (height + kBlockDim - 1) ~/ kBlockDim;
  final out = Uint8List(width * height * 4);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final base = (by * blocksX + bx) * kAstcBlockBytes;

      // Endpoints.
      final v = List<int>.filled(6, 0);
      var pos = _endpointStartBit;
      for (var k = 0; k < 6; k++) {
        v[k] = _getBits(astc, base, pos, 8);
        pos += 8;
      }
      final low = [v[0], v[2], v[4]];
      final high = [v[1], v[3], v[5]];

      // Weights (reverse the placement).
      final ws = Uint8List(_weightDataBits);
      for (var k = 0; k < _weightDataBits; k++) {
        ws[k] = _getBit(astc, base, 127 - k);
      }

      for (var i = 0; i < _numWeights; i++) {
        var w = 0;
        for (var b = 0; b < _weightBits; b++) {
          w |= ws[i * _weightBits + b] << b;
        }
        final y = i ~/ 4;
        final x = i % 4;
        final dy = by * 4 + y;
        final dx = bx * 4 + x;
        if (dy >= height || dx >= width) continue;
        final dst = (dy * width + dx) * 4;
        for (var c = 0; c < 3; c++) {
          out[dst + c] = low[c] + (high[c] - low[c]) * w ~/ (_weightLevels - 1);
        }
        out[dst + 3] = 255;
      }
    }
  }
  return out;
}
