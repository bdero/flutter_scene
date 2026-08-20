// A UASTC LDR 4x4 block decoder producing RGBA8, for standard KTX2 textures
// (glTF KHR_texture_basisu). Each 16-byte block is one of 19 fixed ASTC
// configurations; decoding unquantizes the endpoints, interpolates per-texel
// weights, and writes straight RGBA. Output matches the reference transcoder's
// RGBA32 target byte for byte (which interpolates without the sRGB scale).
//
// The mode layouts, quantization tables, and partition patterns are ported
// from Binomial LLC's basis_universal transcoder (Apache-2.0); see
// THIRD_PARTY_NOTICES.md.

import 'dart:typed_data';

/// Decodes [blocks] (UASTC, row-major 4x4 blocks) into an RGBA8 image of
/// [width] x [height]. Throws [FormatException] on malformed block data.
Uint8List decodeUastcRgba8(Uint8List blocks, int width, int height) {
  final blocksX = (width + 3) >> 2;
  final blocksY = (height + 3) >> 2;
  if (blocks.length < blocksX * blocksY * 16) {
    throw const FormatException('UASTC payload is too small for image size');
  }
  final out = Uint8List(width * height * 4);
  final pixels = Uint8List(64);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      _decodeBlock(blocks, (by * blocksX + bx) * 16, pixels);
      final maxY = height - by * 4 < 4 ? height - by * 4 : 4;
      final maxX = width - bx * 4 < 4 ? width - bx * 4 : 4;
      for (var y = 0; y < maxY; y++) {
        final dst = ((by * 4 + y) * width + bx * 4) * 4;
        final src = y * 16;
        out.setRange(dst, dst + maxX * 4, pixels, src);
      }
    }
  }
  return out;
}

// Mode index per 7-bit code prefix.
const List<int> _huffModes = [
  11, 0, 10, 3, 11, 15, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9, 11, 0, 10, 4, //
  11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13, 11, 0, 10, 3, 11, 17, 12, 7,
  11, 18, 10, 5, 11, 14, 12, 9, 11, 0, 10, 4, 11, 1, 12, 8, 11, 18, 10, 6,
  11, 2, 12, 13, 11, 0, 10, 3, 11, 19, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9,
  11, 0, 10, 4, 11, 16, 12, 8, 11, 18, 10, 6, 11, 2, 12, 13, 11, 0, 10, 3,
  11, 17, 12, 7, 11, 18, 10, 5, 11, 14, 12, 9, 11, 0, 10, 4, 11, 1, 12, 8,
  11, 18, 10, 6, 11, 2, 12, 13,
];

// Mode code lengths (the mode field the huff prefix encodes).
const List<int> _modeCodeLengths = [
  4, 6, 5, 5, 5, 5, 5, 5, 5, 5, 3, 2, 3, 5, 5, 7, 6, 6, 4, //
];

const List<int> _modeWeightBits = [
  4, 2, 3, 2, 2, 3, 2, 2, 0, 2, 4, 2, 3, 1, 2, 4, 2, 2, 5, //
];
const List<int> _modeEndpointRanges = [
  19, 20, 8, 7, 12, 20, 18, 12, 0, 8, 13, 13, 19, 20, 20, 20, 20, 20, 11, //
];
const List<int> _modeSubsets = [
  1, 1, 2, 3, 2, 1, 1, 2, 0, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, //
];
const List<int> _modePlanes = [
  1, 1, 1, 1, 1, 1, 2, 1, 0, 1, 1, 2, 1, 2, 1, 1, 1, 2, 1, //
];
const List<int> _modeComps = [
  3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 2, 2, 2, 3, //
];
const List<int> _modeHintBits = [
  15, 15, 15, 15, 15, 15, 15, 15, 0, 23, 17, 17, 17, 23, 23, 23, 23, 23, 15, //
];

// BISE ranges: bits, trits, quints.
const List<List<int>> _biseRanges = [
  [1, 0, 0], [0, 1, 0], [2, 0, 0], [0, 0, 1], [1, 1, 0], [3, 0, 0], //
  [1, 0, 1], [2, 1, 0], [4, 0, 0], [2, 0, 1], [3, 1, 0], [5, 0, 0],
  [3, 0, 1], [4, 1, 0], [6, 0, 0], [4, 0, 1], [5, 1, 0], [7, 0, 0],
  [5, 0, 1], [6, 1, 0], [8, 0, 0],
];

// ASTC endpoint unquantization parameters per range: the B bit-selection
// string and the C multiplier (ASTC spec 18.13).
const Map<int, (String, int)> _unquantParams = {
  4: ('000000000', 204),
  6: ('000000000', 113),
  7: ('b000b0bb0', 93),
  9: ('b0000bb00', 54),
  10: ('cb000cbcb', 44),
  12: ('cb0000cbc', 26),
  13: ('dcb000dcb', 22),
  15: ('dcb0000dc', 13),
  16: ('edcb000ed', 11),
  18: ('edcb0000e', 6),
  19: ('fedcb000f', 5),
};

// Weight interpolation factors indexed by weight bit count.
const List<List<int>> _weightTables = [
  [],
  [0, 64],
  [0, 21, 43, 64],
  [0, 9, 18, 27, 37, 46, 55, 64],
  [0, 4, 8, 12, 17, 21, 25, 29, 35, 39, 43, 47, 52, 56, 60, 64],
  [
    0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, //
    34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64,
  ],
];

// Two-subset partition patterns shared between ASTC and BC7 (30 entries).
const List<List<int>> _patterns2 = [
  [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1],
  [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
  [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
  [0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 0],
  [0, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
  [1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1],
  [1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0],
  [1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0],
  [1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 1],
  [0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0],
  [0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0],
  [1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1],
  [1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0],
  [0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0],
  [1, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1],
  [0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0],
  [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1],
  [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
  [1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0],
  [1, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0],
];

// Three-subset partition patterns (11 entries).
const List<List<int>> _patterns3 = [
  [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2],
  [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 2, 2, 2, 2],
  [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2],
  [1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0],
  [1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0],
  [0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2],
  [0, 2, 1, 1, 0, 2, 1, 1, 0, 2, 1, 1, 0, 2, 1, 1],
  [2, 0, 0, 0, 2, 0, 0, 0, 2, 1, 1, 1, 2, 1, 1, 1],
  [2, 0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2],
  [1, 1, 1, 1, 0, 0, 0, 0, 2, 2, 2, 2, 1, 1, 1, 1],
  [0, 0, 2, 2, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 2, 2],
];

// Mode 7's two-subset patterns drawn from BC7's three-subset set (19 entries).
const List<List<int>> _patterns2Mode7 = [
  [0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0],
  [1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1],
  [0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0],
  [0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1],
  [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0],
  [0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0],
  [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0],
  [0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0],
  [1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0],
  [0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0],
  [1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
];

// Anchor weight indices per subset for each pattern set.
const List<List<int>> _anchors2 = [
  [0, 2], [0, 3], [1, 0], [0, 3], [7, 0], [0, 2], [3, 0], [7, 0], //
  [0, 11], [2, 0], [0, 7], [11, 0], [3, 0], [8, 0], [0, 4], [12, 0],
  [1, 0], [8, 0], [0, 1], [0, 2], [0, 4], [8, 0], [1, 0], [0, 2],
  [4, 0], [0, 1], [4, 0], [1, 0], [4, 0], [1, 0],
];
const List<List<int>> _anchors3 = [
  [0, 8, 10], [8, 0, 12], [4, 0, 12], [8, 0, 4], [3, 0, 2], [0, 1, 3], //
  [0, 2, 1], [1, 9, 0], [1, 2, 0], [4, 0, 8], [0, 6, 2],
];
const List<List<int>> _anchors2Mode7 = [
  [0, 4], [0, 2], [2, 0], [0, 7], [8, 0], [0, 1], [0, 3], [0, 1], //
  [2, 0], [0, 1], [0, 8], [2, 0], [0, 1], [0, 7], [12, 0], [2, 0],
  [9, 0], [0, 2], [4, 0],
];

const List<int> _zeroPattern = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
];

/// Endpoint unquantization lookup per range, built on first use and shared by
/// every texture decoded in the isolate.
final Map<int, Uint8List> _unquantCache = {};

Uint8List _unquantTable(int range) => _unquantCache.putIfAbsent(range, () {
  final bits = _biseRanges[range][0];
  final trits = _biseRanges[range][1];
  final quints = _biseRanges[range][2];
  final levels = ((1 + 2 * trits + 4 * quints) << bits);
  final table = Uint8List(levels);
  for (var packed = 0; packed < levels; packed++) {
    final bitsValue = packed & ((1 << bits) - 1);
    final tq = packed >> bits;
    table[packed] = _unquantEndpoint(bitsValue, tq, range);
  }
  return table;
});

int _unquantEndpoint(int packedBits, int packedTq, int range) {
  final bits = _biseRanges[range][0];
  final trits = _biseRanges[range][1];
  final quints = _biseRanges[range][2];
  if (trits == 0 && quints == 0) {
    // Plain bits replicate to fill 8 bits.
    var value = 0;
    var bitsLeft = 8;
    while (bitsLeft > 0) {
      var v = packedBits;
      final n = bitsLeft < bits ? bitsLeft : bits;
      if (n < bits) v >>= bits - n;
      value |= v << (bitsLeft - n);
      bitsLeft -= n;
    }
    return value;
  }
  final params = _unquantParams[range]!;
  final a = (packedBits & 1) != 0 ? 511 : 0;
  final c = params.$2;
  var b = 0;
  for (var i = 0; i < 9; i++) {
    b <<= 1;
    final ch = params.$1.codeUnitAt(i);
    if (ch != 0x30) {
      b |= (packedBits >> (ch - 0x61)) & 1;
    }
  }
  var value = packedTq * c + b;
  value ^= a;
  return (a & 0x80) | (value >> 2);
}

int _readBits(Uint8List data, int base, int bitOffset, int count) {
  if (count == 0) return 0;
  final byteIndex = base + (bitOffset >> 3);
  final shift = bitOffset & 7;
  // Three bytes cover any read of up to 9 bits at any alignment.
  var acc = data[byteIndex];
  if (byteIndex + 1 < data.length) acc |= data[byteIndex + 1] << 8;
  if (count + shift > 16 && byteIndex + 2 < data.length) {
    acc |= data[byteIndex + 2] << 16;
  }
  return (acc >> shift) & ((1 << count) - 1);
}

int _interpolate(int low, int high, int weight) {
  final l = (low << 8) | low;
  final h = (high << 8) | high;
  return ((l * (64 - weight) + h * weight + 32) >> 6) >> 8;
}

/// Decodes one 16-byte block at [offset] into 16 RGBA texels (64 bytes).
void _decodeBlock(Uint8List data, int offset, Uint8List out) {
  final mode = _huffModes[data[offset] & 127];
  if (mode >= 19) {
    throw const FormatException('Invalid UASTC block mode');
  }
  var bitPos = _modeCodeLengths[mode];

  if (mode == 8) {
    // Solid color block.
    final r = _readBits(data, offset, bitPos, 8);
    final g = _readBits(data, offset, bitPos + 8, 8);
    final b = _readBits(data, offset, bitPos + 16, 8);
    final a = _readBits(data, offset, bitPos + 24, 8);
    for (var i = 0; i < 16; i++) {
      out[i * 4] = r;
      out[i * 4 + 1] = g;
      out[i * 4 + 2] = b;
      out[i * 4 + 3] = a;
    }
    return;
  }

  // Skip the BC1/ETC translation hint bits; RGBA decode does not use them.
  bitPos += _modeHintBits[mode];

  final subsets = _modeSubsets[mode];
  var commonPattern = 0;
  switch (mode) {
    case 2 || 4 || 7 || 9 || 16:
      commonPattern = _readBits(data, offset, bitPos, 5);
      bitPos += 5;
    case 3:
      commonPattern = _readBits(data, offset, bitPos, 4);
      bitPos += 4;
  }
  List<int> pattern = _zeroPattern;
  List<int> anchors = _zeroPattern;
  if (subsets == 3) {
    if (commonPattern >= _patterns3.length) {
      throw const FormatException('Invalid UASTC partition pattern');
    }
    pattern = _patterns3[commonPattern];
    anchors = _anchors3[commonPattern];
  } else if (subsets == 2) {
    if (mode == 7) {
      if (commonPattern >= _patterns2Mode7.length) {
        throw const FormatException('Invalid UASTC partition pattern');
      }
      pattern = _patterns2Mode7[commonPattern];
      anchors = _anchors2Mode7[commonPattern];
    } else {
      if (commonPattern >= _patterns2.length) {
        throw const FormatException('Invalid UASTC partition pattern');
      }
      pattern = _patterns2[commonPattern];
      anchors = _anchors2[commonPattern];
    }
  }

  final planes = _modePlanes[mode];
  var ccs = 0;
  if (planes == 2) {
    if (mode == 17) {
      ccs = 3;
    } else {
      ccs = _readBits(data, offset, bitPos, 2);
      bitPos += 2;
    }
  }

  final comps = _modeComps[mode];
  final endpointRange = _modeEndpointRanges[mode];
  final totalValues = comps * 2 * subsets;
  final epBits = _biseRanges[endpointRange][0];
  final epTrits = _biseRanges[endpointRange][1];
  final epQuints = _biseRanges[endpointRange][2];

  // Trit/quint values ride in packed bundles ahead of the plain bits.
  var totalTqs = 0;
  var bundleSize = 0;
  var mul = 0;
  if (epTrits != 0) {
    totalTqs = (totalValues + 4) ~/ 5;
    bundleSize = 5;
    mul = 3;
  } else if (epQuints != 0) {
    totalTqs = (totalValues + 2) ~/ 3;
    bundleSize = 3;
    mul = 5;
  }
  final tqValues = List<int>.filled(8, 0);
  for (var i = 0; i < totalTqs; i++) {
    var numBits = epTrits != 0 ? 8 : 7;
    if (i == totalTqs - 1) {
      final remaining = totalValues - (totalTqs - 1) * bundleSize;
      if (epTrits != 0) {
        numBits = switch (remaining) {
          1 => 2,
          2 => 4,
          3 => 5,
          4 => 7,
          _ => numBits,
        };
      } else {
        numBits = switch (remaining) {
          1 => 3,
          2 => 5,
          _ => numBits,
        };
      }
    }
    tqValues[i] = _readBits(data, offset, bitPos, numBits);
    bitPos += numBits;
  }

  final unquant = _unquantTable(endpointRange);
  final endpoints = Uint8List(18);
  var accum = 0;
  var accumRemaining = 0;
  var nextTq = 0;
  for (var i = 0; i < totalValues; i++) {
    var value = _readBits(data, offset, bitPos, epBits);
    bitPos += epBits;
    if (totalTqs != 0) {
      if (accumRemaining == 0) {
        accum = tqValues[nextTq++];
        accumRemaining = bundleSize;
      }
      value |= (accum % mul) << epBits;
      accum ~/= mul;
      accumRemaining--;
    }
    endpoints[i] = unquant[value];
  }

  final weightBits = _modeWeightBits[mode];
  final weights = Uint8List(32);
  if (planes == 2) {
    // Dual plane: single subset, first two weights are anchors.
    weights[0] = _readBits(data, offset, bitPos, weightBits - 1);
    bitPos += weightBits - 1;
    weights[1] = _readBits(data, offset, bitPos, weightBits - 1);
    bitPos += weightBits - 1;
    for (var i = 2; i < 32; i++) {
      weights[i] = _readBits(data, offset, bitPos, weightBits);
      bitPos += weightBits;
    }
  } else if (subsets == 1) {
    weights[0] = _readBits(data, offset, bitPos, weightBits - 1);
    bitPos += weightBits - 1;
    for (var i = 1; i < 16; i++) {
      weights[i] = _readBits(data, offset, bitPos, weightBits);
      bitPos += weightBits;
    }
  } else {
    for (var i = 0; i < 16; i++) {
      var isAnchor = false;
      for (var s = 0; s < subsets; s++) {
        if (anchors[s] == i) {
          isAnchor = true;
          break;
        }
      }
      final n = isAnchor ? weightBits - 1 : weightBits;
      weights[i] = _readBits(data, offset, bitPos, n);
      bitPos += n;
    }
  }

  // Unquantized endpoint pairs per subset, RGBA.
  final lowColors = Uint8List(12);
  final highColors = Uint8List(12);
  for (var s = 0; s < subsets; s++) {
    if (comps == 2) {
      // Luminance+alpha: L rides in RGB, A in the second pair.
      final ll = endpoints[s * 4];
      final lh = endpoints[s * 4 + 1];
      final al = endpoints[s * 4 + 2];
      final ah = endpoints[s * 4 + 3];
      lowColors[s * 4] = ll;
      lowColors[s * 4 + 1] = ll;
      lowColors[s * 4 + 2] = ll;
      lowColors[s * 4 + 3] = al;
      highColors[s * 4] = lh;
      highColors[s * 4 + 1] = lh;
      highColors[s * 4 + 2] = lh;
      highColors[s * 4 + 3] = ah;
    } else {
      for (var c = 0; c < 4; c++) {
        if (c < comps) {
          lowColors[s * 4 + c] = endpoints[s * comps * 2 + c * 2];
          highColors[s * 4 + c] = endpoints[s * comps * 2 + c * 2 + 1];
        } else {
          lowColors[s * 4 + c] = 255;
          highColors[s * 4 + c] = 255;
        }
      }
    }
  }

  final weightTable = _weightTables[weightBits];
  if (planes == 1) {
    for (var i = 0; i < 16; i++) {
      final s = pattern[i];
      final w = weightTable[weights[i]];
      for (var c = 0; c < 4; c++) {
        out[i * 4 + c] = _interpolate(
          lowColors[s * 4 + c],
          highColors[s * 4 + c],
          w,
        );
      }
    }
  } else {
    for (var i = 0; i < 16; i++) {
      final w0 = weightTable[weights[i * 2]];
      final w1 = weightTable[weights[i * 2 + 1]];
      for (var c = 0; c < 4; c++) {
        out[i * 4 + c] = _interpolate(
          lowColors[c],
          highColors[c],
          c == ccs ? w1 : w0,
        );
      }
    }
  }
}
