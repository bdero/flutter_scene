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
// Blocks whose alpha endpoints are not fully opaque switch to color endpoint
// mode 12 (LDR RGBA direct). CEM 12 needs 8 endpoint integers, which no
// longer fit at 8 bits in the 63 bits below the weights, so they encode at
// the quantization the decoder derives: range 0..191 (a trit plus 6 bits)
// via the trit integer sequence encoding. The trit packing and the range-191
// unquantization follow the reference implementations (ARM astc-encoder's
// sequence tables, google/astc-codec's unquantization), verified against
// their published tables.
//
// The exact A/B size-field bit positions, the weight bit-reversal, and the
// endpoint ordering are reconstructed from the ASTC spec and reference
// decoders; GPU acceptance of these bytes is confirmed by on-device rendering.
// TODO(texture-compression): widen beyond these configs (other ranges, dual
// plane for uncorrelated channels).

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/universal_block.dart';

/// Bytes per ASTC 4x4 block.
const int kAstcBlockBytes = 16;

const int _astcBlockMode = 0x53; // 4x4 grid, weight range 7, single plane
const int _astcCem = 8; // LDR RGB direct
const int _astcCemRgba = 12; // LDR RGBA direct
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
  if (src[si + 3] != 255 || src[si + 7] != 255) {
    _transcodeBlockRgba(src, si, out, oi);
    return;
  }
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

/// Decodes packed ASTC 4x4 blocks (our fixed configs only) to rgba8, for
/// tests. Handles the CEM 8 (RGB) and CEM 12 (RGBA, range-191 endpoints)
/// blocks the transcoder emits.
Uint8List decodeAstc4x4ToRgba8(Uint8List astc, int width, int height) {
  final blocksX = (width + kBlockDim - 1) ~/ kBlockDim;
  final blocksY = (height + kBlockDim - 1) ~/ kBlockDim;
  final out = Uint8List(width * height * 4);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      final base = (by * blocksX + bx) * kAstcBlockBytes;
      final cem = _getBits(astc, base, 13, 4);

      final List<int> low, high;
      if (cem == _astcCemRgba) {
        final q = _readTritIse(astc, base, _endpointStartBit, 8);
        var e0 = [for (var k = 0; k < 8; k += 2) _unquant192(q[k])];
        var e1 = [for (var k = 1; k < 8; k += 2) _unquant192(q[k])];
        if (e1[0] + e1[1] + e1[2] < e0[0] + e0[1] + e0[2]) {
          // Swapped endpoints take the blue-contract path (the transcoder
          // always orders to avoid this; mirrored here for completeness).
          final t = e0;
          e0 = e1;
          e1 = t;
          for (final e in [e0, e1]) {
            e[0] = (e[0] + e[2]) >> 1;
            e[1] = (e[1] + e[2]) >> 1;
          }
        }
        low = e0;
        high = e1;
      } else {
        final v = List<int>.filled(6, 0);
        var pos = _endpointStartBit;
        for (var k = 0; k < 6; k++) {
          v[k] = _getBits(astc, base, pos, 8);
          pos += 8;
        }
        low = [v[0], v[2], v[4], 255];
        high = [v[1], v[3], v[5], 255];
      }

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
        for (var c = 0; c < 4; c++) {
          out[dst + c] = low[c] + (high[c] - low[c]) * w ~/ (_weightLevels - 1);
        }
      }
    }
  }
  return out;
}

// ───── CEM 12 (RGBA) blocks ─────

/// Decodes the five trits packed into one ISE byte [t], per the spec's bit
/// manipulation (verified against the ARM reference tables).
List<int> _decodeTrits(int t) {
  int c;
  int t4, t3;
  if ((t >> 2) & 0x7 == 0x7) {
    c = (((t >> 5) & 0x7) << 2) | (t & 0x3);
    t4 = 2;
    t3 = 2;
  } else {
    c = t & 0x1F;
    if ((t >> 5) & 0x3 == 0x3) {
      t4 = 2;
      t3 = (t >> 7) & 1;
    } else {
      t4 = (t >> 7) & 1;
      t3 = (t >> 5) & 0x3;
    }
  }
  int t2, t1, t0;
  if (c & 0x3 == 0x3) {
    t2 = 2;
    t1 = (c >> 4) & 1;
    final c3 = (c >> 3) & 1;
    t0 = (c3 << 1) | (((c >> 2) & 1) & (1 - c3));
  } else if ((c >> 2) & 0x3 == 0x3) {
    t2 = 2;
    t1 = 2;
    t0 = c & 0x3;
  } else {
    t2 = (c >> 4) & 1;
    t1 = (c >> 2) & 0x3;
    final c1 = (c >> 1) & 1;
    t0 = (c1 << 1) | ((c & 1) & (1 - c1));
  }
  return [t0, t1, t2, t3, t4];
}

/// trit-quintuplet key (t0 + 3 t1 + 9 t2 + 27 t3 + 81 t4) -> packed ISE byte.
final Map<int, int> _integerOfTrits = () {
  final map = <int, int>{};
  for (var t = 0; t < 256; t++) {
    final trits = _decodeTrits(t);
    final key =
        trits[0] + 3 * trits[1] + 9 * trits[2] + 27 * trits[3] + 81 * trits[4];
    map.putIfAbsent(key, () => t);
  }
  return map;
}();

/// Unquantizes a range-191 value (trit * 64 + 6-bit mantissa) to 8 bits.
int _unquant192(int v) {
  final trit = v ~/ 64;
  final m = v & 0x3F;
  final a = (m & 1) != 0 ? 0x1FF : 0;
  final x = (m >> 1) & 0x1F;
  final b = (x >> 4) | (x << 4);
  var t = trit * 5 + b;
  t ^= a;
  return (a & 0x80) | (t >> 2);
}

/// 8-bit target -> nearest range-191 quantized value.
final List<int> _quant192 = () {
  final lookup = List<int>.filled(256, 0);
  for (var target = 0; target < 256; target++) {
    var best = 0;
    var bestError = 1 << 30;
    for (var v = 0; v < 192; v++) {
      final error = (_unquant192(v) - target).abs();
      if (error < bestError) {
        bestError = error;
        best = v;
      }
    }
    lookup[target] = best;
  }
  return lookup;
}();

// Per-element trit-bit widths and shifts within a five-value ISE block.
const List<int> _tritBitCounts = [2, 2, 1, 2, 1];
const List<int> _tritBitShifts = [0, 2, 4, 5, 7];

/// Writes [values] (range-191 quantized) as a trit ISE stream at [startBit].
void _writeTritIse(Uint8List out, int oi, int startBit, List<int> values) {
  var pos = startBit;
  for (var blockStart = 0; blockStart < values.length; blockStart += 5) {
    final n = values.length - blockStart < 5 ? values.length - blockStart : 5;
    var key = 0;
    var scale = 1;
    for (var k = 0; k < n; k++) {
      key += (values[blockStart + k] ~/ 64) * scale;
      scale *= 3;
    }
    final t = _integerOfTrits[key]!;
    for (var k = 0; k < n; k++) {
      _setBits(out, oi, pos, 6, values[blockStart + k] & 0x3F);
      pos += 6;
      _setBits(
        out,
        oi,
        pos,
        _tritBitCounts[k],
        (t >> _tritBitShifts[k]) & ((1 << _tritBitCounts[k]) - 1),
      );
      pos += _tritBitCounts[k];
    }
  }
}

/// Reads [count] range-191 values from a trit ISE stream at [startBit].
List<int> _readTritIse(Uint8List blk, int base, int startBit, int count) {
  final values = List<int>.filled(count, 0);
  var pos = startBit;
  for (var blockStart = 0; blockStart < count; blockStart += 5) {
    final n = count - blockStart < 5 ? count - blockStart : 5;
    final mantissas = List<int>.filled(n, 0);
    var t = 0;
    for (var k = 0; k < n; k++) {
      mantissas[k] = _getBits(blk, base, pos, 6);
      pos += 6;
      t |= _getBits(blk, base, pos, _tritBitCounts[k]) << _tritBitShifts[k];
      pos += _tritBitCounts[k];
    }
    final trits = _decodeTrits(t);
    for (var k = 0; k < n; k++) {
      values[blockStart + k] = trits[k] * 64 + mantissas[k];
    }
  }
  return values;
}

void _transcodeBlockRgba(Uint8List src, int si, Uint8List out, int oi) {
  final q0 = [for (var c = 0; c < 4; c++) _quant192[src[si + c]]];
  final q1 = [for (var c = 0; c < 4; c++) _quant192[src[si + 4 + c]]];

  // The decoder takes the direct (no blue-contract) path when the unquantized
  // sum of the odd (v1, v3, v5) endpoints is >= the even sum; order the
  // higher-luma endpoint odd and flip the weights to match.
  int lumaSum(List<int> q) =>
      _unquant192(q[0]) + _unquant192(q[1]) + _unquant192(q[2]);
  final flip = lumaSum(q1) < lumaSum(q0);
  final low = flip ? q1 : q0;
  final high = flip ? q0 : q1;

  _setBits(out, oi, 0, 11, _astcBlockMode);
  _setBits(out, oi, 11, 2, 0); // 1 partition
  _setBits(out, oi, 13, 4, _astcCemRgba);
  _writeTritIse(out, oi, _endpointStartBit, [
    low[0],
    high[0],
    low[1],
    high[1],
    low[2],
    high[2],
    low[3],
    high[3],
  ]);
  _writeWeights(out, oi, src, si, flip);
}

/// Writes the 16 x 3-bit weight grid (shared by the CEM 8 and CEM 12 paths).
void _writeWeights(Uint8List out, int oi, Uint8List src, int si, bool flip) {
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
