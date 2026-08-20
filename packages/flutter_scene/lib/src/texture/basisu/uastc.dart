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
  final block = _Block();
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      _parseBlock(blocks, (by * blocksX + bx) * 16, block);
      _blockToRgba(block, pixels);
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

/// One parsed UASTC block: the mode configuration plus its still-quantized
/// endpoint and weight values, shared by the RGBA decode and the ASTC repack.
class _Block {
  int mode = 0;
  int commonPattern = 0;
  int ccs = 0;
  int solidR = 0, solidG = 0, solidB = 0, solidA = 0;

  /// Quantized endpoint values in read order (per subset, per component,
  /// low then high).
  final Uint8List endpoints = Uint8List(18);

  /// Quantized weights, one per texel (two per texel interleaved for
  /// dual-plane modes).
  final Uint8List weights = Uint8List(32);
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

/// The partition pattern and anchor indices for a mode/pattern pair.
(List<int>, List<int>) _patternFor(int mode, int subsets, int commonPattern) {
  if (subsets == 3) {
    if (commonPattern >= _patterns3.length) {
      throw const FormatException('Invalid UASTC partition pattern');
    }
    return (_patterns3[commonPattern], _anchors3[commonPattern]);
  }
  if (subsets == 2) {
    if (mode == 7) {
      if (commonPattern >= _patterns2Mode7.length) {
        throw const FormatException('Invalid UASTC partition pattern');
      }
      return (_patterns2Mode7[commonPattern], _anchors2Mode7[commonPattern]);
    }
    if (commonPattern >= _patterns2.length) {
      throw const FormatException('Invalid UASTC partition pattern');
    }
    return (_patterns2[commonPattern], _anchors2[commonPattern]);
  }
  return (_zeroPattern, _zeroPattern);
}

/// Parses the 16-byte block at [offset] into [b], leaving endpoint and weight
/// values quantized.
void _parseBlock(Uint8List data, int offset, _Block b) {
  final mode = _huffModes[data[offset] & 127];
  if (mode >= 19) {
    throw const FormatException('Invalid UASTC block mode');
  }
  b.mode = mode;
  b.commonPattern = 0;
  b.ccs = 0;
  var bitPos = _modeCodeLengths[mode];

  if (mode == 8) {
    // Solid color block.
    b.solidR = _readBits(data, offset, bitPos, 8);
    b.solidG = _readBits(data, offset, bitPos + 8, 8);
    b.solidB = _readBits(data, offset, bitPos + 16, 8);
    b.solidA = _readBits(data, offset, bitPos + 24, 8);
    return;
  }

  // Skip the BC1/ETC translation hint bits; neither RGBA decode nor the ASTC
  // repack uses them.
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
  b.commonPattern = commonPattern;
  final (_, anchors) = _patternFor(mode, subsets, commonPattern);

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
  b.ccs = ccs;

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

  final endpoints = b.endpoints;
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
    endpoints[i] = value;
  }

  final weightBits = _modeWeightBits[mode];
  final weights = b.weights;
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
}

/// Unquantizes and interpolates a parsed block [b] into 16 RGBA texels
/// (64 bytes).
void _blockToRgba(_Block b, Uint8List out) {
  final mode = b.mode;
  if (mode == 8) {
    for (var i = 0; i < 16; i++) {
      out[i * 4] = b.solidR;
      out[i * 4 + 1] = b.solidG;
      out[i * 4 + 2] = b.solidB;
      out[i * 4 + 3] = b.solidA;
    }
    return;
  }
  final subsets = _modeSubsets[mode];
  final planes = _modePlanes[mode];
  final comps = _modeComps[mode];
  final (pattern, _) = _patternFor(mode, subsets, b.commonPattern);
  final unquant = _unquantTable(_modeEndpointRanges[mode]);
  final endpoints = b.endpoints;
  final weights = b.weights;
  final ccs = b.ccs;

  // Unquantized endpoint pairs per subset, RGBA.
  final lowColors = Uint8List(12);
  final highColors = Uint8List(12);
  for (var s = 0; s < subsets; s++) {
    if (comps == 2) {
      // Luminance+alpha: L rides in RGB, A in the second pair.
      final ll = unquant[endpoints[s * 4]];
      final lh = unquant[endpoints[s * 4 + 1]];
      final al = unquant[endpoints[s * 4 + 2]];
      final ah = unquant[endpoints[s * 4 + 3]];
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
          lowColors[s * 4 + c] = unquant[endpoints[s * comps * 2 + c * 2]];
          highColors[s * 4 + c] = unquant[endpoints[s * comps * 2 + c * 2 + 1]];
        } else {
          lowColors[s * 4 + c] = 255;
          highColors[s * 4 + c] = 255;
        }
      }
    }
  }

  final weightTable = _weightTables[_modeWeightBits[mode]];
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

// ---------------------------------------------------------------------------
// UASTC to ASTC 4x4 LDR repack. Every UASTC configuration is a legal ASTC
// block, so this rewrites each block's fields into the real ASTC layout
// (canonical partition seeds, BISE-coded endpoints, reversed weight bits)
// without touching the pixel values.

// ASTC block mode field per UASTC mode (mode 8 is a void-extent block).
const List<int> _astcBlockModes = [
  0x242, 0x42, 0x53, 0x42, 0x42, 0x53, 0x442, 0x42, 0, 0x42, 0x242, //
  0x442, 0x53, 0x441, 0x42, 0x242, 0x42, 0x442, 0x253,
];

// ASTC color endpoint mode per UASTC mode (8 = RGB, 12 = RGBA, 4 = LA).
const List<int> _modeCems = [
  8, 8, 8, 8, 8, 8, 8, 8, 0, 12, 12, 12, 12, 12, 12, 4, 4, 4, 8, //
];

// ASTC partition seeds for each common pattern, per pattern set.
const List<int> _astcSeeds2 = [
  28, 20, 16, 29, 91, 9, 107, 72, 149, 204, 50, 114, 496, 17, 78, //
  39, 252, 828, 43, 156, 116, 210, 476, 273, 684, 359, 246, 195, 694, 524,
];
const List<int> _astcSeeds2Mode7 = [
  36, 48, 61, 137, 161, 183, 226, 281, 302, 307, 479, 495, 593, 594, //
  605, 799, 812, 988, 993,
];
const List<int> _astcSeeds3 = [
  260, 74, 32, 156, 183, 15, 745, 0, 335, 902, 254, //
];

// ASTC integer sequence encoding tables: 5 trits to 8 bits, 3 quints to
// 7 bits.
const List<int> _astcTritEncode = [
  0, 1, 2, 4, 5, 6, 8, 9, 10, 16, 17, 18, 20, 21, 22, 24, 25, 26, 3, 7, //
  11, 19, 23, 27, 12, 13, 14, 32, 33, 34, 36, 37, 38, 40, 41, 42, 48, 49,
  50, 52, 53, 54, 56, 57, 58, 35, 39, 43, 51, 55, 59, 44, 45, 46, 64, 65,
  66, 68, 69, 70, 72, 73, 74, 80, 81, 82, 84, 85, 86, 88, 89, 90, 67, 71,
  75, 83, 87, 91, 76, 77, 78, 128, 129, 130, 132, 133, 134, 136, 137, 138,
  144, 145, 146, 148, 149, 150, 152, 153, 154, 131, 135, 139, 147, 151,
  155, 140, 141, 142, 160, 161, 162, 164, 165, 166, 168, 169, 170, 176,
  177, 178, 180, 181, 182, 184, 185, 186, 163, 167, 171, 179, 183, 187,
  172, 173, 174, 192, 193, 194, 196, 197, 198, 200, 201, 202, 208, 209,
  210, 212, 213, 214, 216, 217, 218, 195, 199, 203, 211, 215, 219, 204,
  205, 206, 96, 97, 98, 100, 101, 102, 104, 105, 106, 112, 113, 114, 116,
  117, 118, 120, 121, 122, 99, 103, 107, 115, 119, 123, 108, 109, 110,
  224, 225, 226, 228, 229, 230, 232, 233, 234, 240, 241, 242, 244, 245,
  246, 248, 249, 250, 227, 231, 235, 243, 247, 251, 236, 237, 238, 28, 29,
  30, 60, 61, 62, 92, 93, 94, 156, 157, 158, 188, 189, 190, 220, 221, 222,
  31, 63, 95, 159, 191, 223, 124, 125, 126,
];
const List<int> _astcQuintEncode = [
  0, 1, 2, 3, 4, 8, 9, 10, 11, 12, 16, 17, 18, 19, 20, 24, 25, 26, 27, //
  28, 5, 13, 21, 29, 6, 32, 33, 34, 35, 36, 40, 41, 42, 43, 44, 48, 49,
  50, 51, 52, 56, 57, 58, 59, 60, 37, 45, 53, 61, 14, 64, 65, 66, 67, 68,
  72, 73, 74, 75, 76, 80, 81, 82, 83, 84, 88, 89, 90, 91, 92, 69, 77, 85,
  93, 22, 96, 97, 98, 99, 100, 104, 105, 106, 107, 108, 112, 113, 114,
  115, 116, 120, 121, 122, 123, 124, 101, 109, 117, 125, 30, 102, 103, 70,
  71, 38, 110, 111, 78, 79, 46, 118, 119, 86, 87, 54, 126, 127, 94, 95,
  62, 39, 47, 55, 63, 31,
];

// Bit-reversal tables for 2 to 5 bit weight values.
const List<int> _reverse2 = [0, 2, 1, 3];
const List<int> _reverse3 = [0, 4, 2, 6, 1, 5, 3, 7];
const List<int> _reverse4 = [
  0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15, //
];
const List<int> _reverse5 = [
  0, 16, 8, 24, 4, 20, 12, 28, 2, 18, 10, 26, 6, 22, 14, 30, //
  1, 17, 9, 25, 5, 21, 13, 29, 3, 19, 11, 27, 7, 23, 15, 31,
];

/// Repacks [blocks] (UASTC, row-major 4x4 blocks) into ASTC 4x4 LDR blocks,
/// byte-identical to the reference transcoder's ASTC target. Throws
/// [FormatException] on malformed block data.
Uint8List transcodeUastcToAstc4x4(Uint8List blocks, int blockCount) {
  if (blocks.length < blockCount * 16) {
    throw const FormatException('UASTC payload is too small for block count');
  }
  final out = Uint8List(blockCount * 16);
  final block = _Block();
  for (var i = 0; i < blockCount; i++) {
    _parseBlock(blocks, i * 16, block);
    _packAstcBlock(block, out, i * 16);
  }
  return out;
}

/// Writes [value]'s low [totalBits] bits into [out] at absolute bit position
/// [bitPos] (LSB-first within each byte), returning the next bit position.
int _setBits(Uint8List out, int o, int bitPos, int value, int totalBits) {
  while (totalBits > 0) {
    final shift = bitPos & 7;
    final bitsToWrite = totalBits < 8 - shift ? totalBits : 8 - shift;
    out[o + (bitPos >> 3)] |= ((value & 0xFF) << shift) & 0xFF;
    bitPos += bitsToWrite;
    totalBits -= bitsToWrite;
    value >>= bitsToWrite;
  }
  return bitPos;
}

int _extractBits(int bits, int low, int high) =>
    (bits >> low) & ((1 << (high - low + 1)) - 1);

/// BISE-encodes [count] values from [values] into [out] starting at [bitPos].
void _packBise(
  Uint8List out,
  int o,
  int bitPos,
  Uint8List values,
  int count,
  int range,
) {
  final n = _biseRanges[range][0];
  final trits = _biseRanges[range][1] != 0;
  final quints = _biseRanges[range][2] != 0;
  final mask = (1 << n) - 1;
  if (trits) {
    for (var g = 0; g * 5 < count; g++) {
      var t = 0;
      final bits = List<int>.filled(5, 0);
      for (var i = 0; i < 5; i++) {
        final v = g * 5 + i < count ? values[g * 5 + i] : 0;
        t += (v >> n) * const [1, 3, 9, 27, 81][i];
        bits[i] = v & mask;
      }
      final packed = _astcTritEncode[t];
      bitPos = _setBits(
        out,
        o,
        bitPos,
        bits[0] | (_extractBits(packed, 0, 1) << n) | (bits[1] << (2 + n)),
        n * 2 + 2,
      );
      bitPos = _setBits(
        out,
        o,
        bitPos,
        _extractBits(packed, 2, 3) |
            (bits[2] << 2) |
            (_extractBits(packed, 4, 4) << (2 + n)) |
            (bits[3] << (3 + n)) |
            (_extractBits(packed, 5, 6) << (3 + n * 2)) |
            (bits[4] << (5 + n * 2)) |
            (_extractBits(packed, 7, 7) << (5 + n * 3)),
        n * 3 + 6,
      );
    }
  } else if (quints) {
    for (var g = 0; g * 3 < count; g++) {
      var q = 0;
      final bits = List<int>.filled(3, 0);
      for (var i = 0; i < 3; i++) {
        final v = g * 3 + i < count ? values[g * 3 + i] : 0;
        q += (v >> n) * const [1, 5, 25][i];
        bits[i] = v & mask;
      }
      final packed = _astcQuintEncode[q];
      bitPos = _setBits(
        out,
        o,
        bitPos,
        bits[0] |
            (_extractBits(packed, 0, 2) << n) |
            (bits[1] << (3 + n)) |
            (_extractBits(packed, 3, 4) << (3 + n * 2)) |
            (bits[2] << (5 + n * 2)) |
            (_extractBits(packed, 5, 6) << (5 + n * 3)),
        7 + n * 3,
      );
    }
  } else {
    for (var i = 0; i < count; i++) {
      bitPos = _setBits(out, o, bitPos, values[i], n);
    }
  }
}

/// Packs one parsed UASTC block [b] as a 16-byte ASTC block at [o].
void _packAstcBlock(_Block b, Uint8List out, int o) {
  final mode = b.mode;
  if (mode == 8) {
    // Void-extent block with 16-bit per channel color.
    out[o] = 0xFC;
    out[o + 1] = 0xFD;
    for (var i = 2; i < 8; i++) {
      out[o + i] = 0xFF;
    }
    out[o + 8] = b.solidR;
    out[o + 9] = b.solidR;
    out[o + 10] = b.solidG;
    out[o + 11] = b.solidG;
    out[o + 12] = b.solidB;
    out[o + 13] = b.solidB;
    out[o + 14] = b.solidA;
    out[o + 15] = b.solidA;
    return;
  }

  final subsets = _modeSubsets[mode];
  final planes = _modePlanes[mode];
  final comps = _modeComps[mode];
  final weightBits = _modeWeightBits[mode];
  final endpointRange = _modeEndpointRanges[mode];
  final cem = _modeCems[mode];
  final endpoints = b.endpoints;
  final weights = b.weights;

  // ASTC always applies blue contraction when the second endpoint sum is
  // lower; UASTC data is stored without it, so swap the offending subsets'
  // endpoints and invert their weights to compensate.
  if (comps >= 3) {
    final unquant = _unquantTable(endpointRange);
    final invertSubset = List<bool>.filled(3, false);
    var anyInverted = false;
    for (var s = 0; s < subsets; s++) {
      final base = s * comps * 2;
      final s0 =
          unquant[endpoints[base]] +
          unquant[endpoints[base + 2]] +
          unquant[endpoints[base + 4]];
      final s1 =
          unquant[endpoints[base + 1]] +
          unquant[endpoints[base + 3]] +
          unquant[endpoints[base + 5]];
      if (s1 < s0) {
        for (var c = 0; c < comps; c++) {
          final t = endpoints[base + c * 2];
          endpoints[base + c * 2] = endpoints[base + c * 2 + 1];
          endpoints[base + c * 2 + 1] = t;
        }
        invertSubset[s] = true;
        anyInverted = true;
      }
    }
    if (anyInverted) {
      final (pattern, _) = _patternFor(mode, subsets, b.commonPattern);
      final weightMask = (1 << weightBits) - 1;
      for (var i = 0; i < 16; i++) {
        if (invertSubset[pattern[i]]) {
          weights[i * planes] = weightMask - weights[i * planes];
          if (planes == 2) {
            weights[i * planes + 1] = weightMask - weights[i * planes + 1];
          }
        }
      }
    }
  }

  out.fillRange(o, o + 16, 0);
  final blockMode = _astcBlockModes[mode];
  out[o] = blockMode & 0xFF;
  out[o + 1] = blockMode >> 8;
  var bitPos = 11;
  bitPos = _setBits(out, o, bitPos, subsets - 1, 2);
  if (subsets == 1) {
    bitPos = _setBits(out, o, bitPos, cem, 4);
  } else {
    final seed = switch (subsets) {
      3 => _astcSeeds3[b.commonPattern],
      _ when mode == 7 => _astcSeeds2Mode7[b.commonPattern],
      _ => _astcSeeds2[b.commonPattern],
    };
    bitPos = _setBits(out, o, bitPos, seed, 10);
    // All subsets share one CEM, so the high mode bits are zero.
    bitPos = _setBits(out, o, bitPos, (cem << 2) & 63, 6);
  }

  final totalWeights = planes == 2 ? 32 : 16;
  if (planes == 2) {
    final ccsBitPos = 128 - totalWeights * weightBits - 2;
    _setBits(out, o, ccsBitPos, b.ccs, 2);
  }

  final numCemValues = (1 + (cem >> 2)) * subsets * 2;
  _packBise(out, o, bitPos, endpoints, numCemValues, endpointRange);

  // Weights live at the top of the block in reverse bit order.
  for (var i = 0; i < totalWeights; i++) {
    final ofs = 128 - weightBits - i * weightBits;
    final rev = switch (weightBits) {
      1 => weights[i],
      2 => _reverse2[weights[i]],
      3 => _reverse3[weights[i]],
      4 => _reverse4[weights[i]],
      _ => _reverse5[weights[i]],
    };
    final shifted = rev << (ofs & 7);
    final index = o + (ofs >> 3);
    out[index] |= shifted & 0xFF;
    if (shifted > 0xFF && index + 1 < o + 16) {
      out[index + 1] |= shifted >> 8;
    }
  }
}
