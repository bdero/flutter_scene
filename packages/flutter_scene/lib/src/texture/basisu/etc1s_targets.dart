// Transcodes ETC1S blocks straight to ETC1, ETC2 EAC alpha, BC1 and BC4
// blocks, without decoding pixels. Ported from basis_universal's transcoder
// (Apache-2.0, see THIRD_PARTY_NOTICES.md) and byte-identical to it.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/etc1s_tables.dart';

/// GPU block formats an ETC1S image transcodes to directly.
enum Etc1sTarget {
  /// ETC1 blocks (8 bytes), uploaded as ETC2 RGB8. Lossless: every ETC1S
  /// block is an ETC1 block.
  etc1(8, hasAlpha: false),

  /// ETC2 RGBA8 (16 bytes): an EAC alpha block, then the ETC1 block.
  etc2Rgba(16, hasAlpha: true),

  /// BC1 (8 bytes), with each block's colors re-fitted, so slightly lossy.
  bc1(8, hasAlpha: false),

  /// BC3 (16 bytes): a BC4 alpha block, then a four-color BC1 block.
  bc3(16, hasAlpha: true);

  const Etc1sTarget(this.bytesPerBlock, {required this.hasAlpha});

  /// Bytes one 4x4 block occupies in this format.
  final int bytesPerBlock;

  /// Whether the format carries alpha (opaque files get opaque alpha).
  final bool hasAlpha;
}

// The ETC1 hardware selector code for each ETC1S selector (ETC1S numbers
// selectors from the most negative modifier up; ETC1 does not).
const List<int> _etc1SelectorCode = [3, 2, 0, 1];

/// An EAC block that decodes to alpha 255 everywhere: base 255, multiplier 1,
/// table 13 (whose selector 4 is the zero modifier) and every selector 4.
const List<int> _opaqueEacBlock = [
  255, 0x1D, 0x92, 0x49, 0x24, 0x92, 0x49, 0x24, //
];

/// Converts blocks of one ETC1S codebook to other formats.
class Etc1sBlockConverter {
  /// [endpoints] holds 4 bytes per entry (red, green and blue as 5-bit
  /// values, then the intensity table); [selectors] holds 4 bytes per entry,
  /// one per texel row, 2 bits per texel with x0 lowest.
  Etc1sBlockConverter(this.endpoints, this.selectors)
    : _etc1Selectors = Uint8List(selectors.length),
      _low = Uint8List(selectors.length ~/ 4),
      _high = Uint8List(selectors.length ~/ 4),
      _uniqueCount = Uint8List(selectors.length ~/ 4) {
    for (var i = 0; i < _low.length; i++) {
      var used = 0;
      var msb = 0;
      var lsb = 0;
      for (var y = 0; y < 4; y++) {
        final row = selectors[i * 4 + y];
        for (var x = 0; x < 4; x++) {
          final s = (row >> (x * 2)) & 3;
          used |= 1 << s;
          // ETC1 stores the selectors as two 16-bit planes (most significant
          // bits first), texel (x, y) at bit x * 4 + y.
          final code = _etc1SelectorCode[s];
          msb |= (code >> 1) << (x * 4 + y);
          lsb |= (code & 1) << (x * 4 + y);
        }
      }
      _etc1Selectors[i * 4] = msb >> 8;
      _etc1Selectors[i * 4 + 1] = msb & 0xFF;
      _etc1Selectors[i * 4 + 2] = lsb >> 8;
      _etc1Selectors[i * 4 + 3] = lsb & 0xFF;
      var low = 0;
      while ((used & (1 << low)) == 0) {
        low++;
      }
      var high = 3;
      while ((used & (1 << high)) == 0) {
        high--;
      }
      _low[i] = low;
      _high[i] = high;
      _uniqueCount[i] =
          (used & 1) + ((used >> 1) & 1) + ((used >> 2) & 1) + (used >> 3);
    }
  }

  final Uint8List endpoints;
  final Uint8List selectors;

  /// Each selector entry's ETC1 selector bytes (block bytes 4-7).
  final Uint8List _etc1Selectors;

  /// Each selector entry's lowest and highest used selector, and how many
  /// distinct selectors it uses.
  final Uint8List _low;
  final Uint8List _high;
  final Uint8List _uniqueCount;

  /// Writes the ETC1 block for endpoint [e] and selector [s] at [out]+[o]
  /// (differential mode, zero delta, one intensity table, no flip).
  void writeEtc1(Uint8List out, int o, int e, int s) {
    final inten = endpoints[e * 4 + 3];
    out[o] = endpoints[e * 4] << 3;
    out[o + 1] = endpoints[e * 4 + 1] << 3;
    out[o + 2] = endpoints[e * 4 + 2] << 3;
    out[o + 3] = (inten << 5) | (inten << 2) | 0x02;
    out[o + 4] = _etc1Selectors[s * 4];
    out[o + 5] = _etc1Selectors[s * 4 + 1];
    out[o + 6] = _etc1Selectors[s * 4 + 2];
    out[o + 7] = _etc1Selectors[s * 4 + 3];
  }

  /// Writes a BC1 block for endpoint [e] and selector [s] at [out]+[o].
  /// [allowThreeColor] false keeps it out of three-color mode, as BC3
  /// requires.
  void writeBc1(
    Uint8List out,
    int o,
    int e,
    int s, {
    required bool allowThreeColor,
  }) {
    final r5 = endpoints[e * 4];
    final g5 = endpoints[e * 4 + 1];
    final b5 = endpoints[e * 4 + 2];
    final inten = endpoints[e * 4 + 3];
    final low = _low[s];
    final high = _high[s];
    final modifiers = etc1IntenTables[inten];

    if (low == high) {
      // One color: fit it at the 2/3 point of a 4-color block.
      final m = modifiers[low];
      final r = _clamp255(expand5(r5) + m);
      final g = _clamp255(expand5(g5) + m);
      final b = _clamp255(expand5(b5) + m);
      final m5 = Bc1SingleColor.match5Selector1;
      final m6 = Bc1SingleColor.match6Selector1;
      var max16 = (m5.hi[r] << 11) | (m6.hi[g] << 5) | m5.hi[b];
      var min16 = (m5.lo[r] << 11) | (m6.lo[g] << 5) | m5.lo[b];
      var mask = 0xAA;
      if (!allowThreeColor && min16 == max16) {
        // Equal endpoints would mean three-color mode; nudge them apart.
        mask = 0;
        if (min16 > 0) {
          min16--;
        } else {
          max16 = 1;
          min16 = 0;
          mask = 0x55;
        }
      }
      if (max16 < min16) {
        final t = max16;
        max16 = min16;
        min16 = t;
        mask ^= 0x55;
      }
      _writeBc1Colors(out, o, max16, min16);
      out[o + 4] = mask;
      out[o + 5] = mask;
      out[o + 6] = mask;
      out[o + 7] = mask;
      return;
    }

    if (inten >= 7 && _uniqueCount[s] == 2 && low == 0 && high == 3) {
      // Only the two extreme colors of the widest intensity: one per
      // endpoint.
      final c0 = [
        _clamp255(expand5(r5) + modifiers[0]),
        _clamp255(expand5(g5) + modifiers[0]),
        _clamp255(expand5(b5) + modifiers[0]),
      ];
      final c1 = [
        _clamp255(expand5(r5) + modifiers[3]),
        _clamp255(expand5(g5) + modifiers[3]),
        _clamp255(expand5(b5) + modifiers[3]),
      ];
      final m5 = Bc1SingleColor.match5Selector0;
      final m6 = Bc1SingleColor.match6Selector0;
      var max16 = (m5.hi[c0[0]] << 11) | (m6.hi[c0[1]] << 5) | m5.hi[c0[2]];
      var min16 = (m5.hi[c1[0]] << 11) | (m6.hi[c1[1]] << 5) | m5.hi[c1[2]];
      var l = 0;
      var h = 1;
      if (min16 == max16) {
        if (min16 > 0) {
          min16--;
          l = 0;
          h = 0;
        } else {
          max16 = 1;
          min16 = 0;
          l = 1;
          h = 1;
        }
      }
      if (max16 < min16) {
        final t = max16;
        max16 = min16;
        min16 = t;
        l = 1;
        h = 0;
      }
      _writeBc1Colors(out, o, max16, min16);
      for (var y = 0; y < 4; y++) {
        final row = selectors[s * 4 + y];
        var bits = 0;
        for (var x = 0; x < 4; x++) {
          bits |= (((row >> (x * 2)) & 3) == 3 ? h : l) << (x * 2);
        }
        out[o + 4 + y] = bits;
      }
      return;
    }

    // Keep the selector mapping with the least error over all channels.
    final range = etc1sBc1RangeIndex[low * 4 + high];
    final t5 = Etc1sBc1Table.fiveBit;
    final t6 = Etc1sBc1Table.sixBit;
    final ri = Etc1sBc1Table.indexOf(inten, r5, range);
    final gi = Etc1sBc1Table.indexOf(inten, g5, range);
    final bi = Etc1sBc1Table.indexOf(inten, b5, range);
    // Not 1 << 62: the web's 32-bit shifts would make that 0.
    var bestError = 0x7FFFFFFF;
    var best = 0;
    for (var m = 0; m < etc1sBc1Mappings.length; m++) {
      final error = t5.error[ri + m] + t6.error[gi + m] + t5.error[bi + m];
      if (error < bestError) {
        bestError = error;
        best = m;
      }
    }
    var l =
        (t5.lo[ri + best] << 11) | (t6.lo[gi + best] << 5) | t5.lo[bi + best];
    var h =
        (t5.hi[ri + best] << 11) | (t6.hi[gi + best] << 5) | t5.hi[bi + best];
    var rows = bc1RowForward[best];
    if (l < h) {
      final t = l;
      l = h;
      h = t;
      rows = bc1RowInverted[best];
    }
    if (l == h) {
      var mask = 0;
      if (!allowThreeColor) {
        if (h > 0) {
          h--;
        } else {
          h = 0;
          l = 1;
          mask = 0x55;
        }
      }
      _writeBc1Colors(out, o, l, h);
      out[o + 4] = mask;
      out[o + 5] = mask;
      out[o + 6] = mask;
      out[o + 7] = mask;
      return;
    }
    _writeBc1Colors(out, o, l, h);
    out[o + 4] = rows[selectors[s * 4]];
    out[o + 5] = rows[selectors[s * 4 + 1]];
    out[o + 6] = rows[selectors[s * 4 + 2]];
    out[o + 7] = rows[selectors[s * 4 + 3]];
  }

  /// Writes an EAC A8 block at [out]+[o] for alpha-slice endpoint [e] and
  /// selector [s] (alpha is the endpoint's red channel).
  void writeEacA8(Uint8List out, int o, int e, int s) {
    final value = endpoints[e * 4];
    final inten = endpoints[e * 4 + 3];
    final low = _low[s];
    final high = _high[s];
    if (low == high) {
      // Constant alpha: table 13's selector 4 is the zero modifier.
      out[o] = _clamp255(expand5(value) + etc1IntenTables[inten][low]);
      for (var i = 1; i < 8; i++) {
        out[o + i] = _opaqueEacBlock[i];
      }
      return;
    }
    final entry =
        ((inten * 32 + value) * 4 + etc1sAlphaRangeIndex(low, high)) * 3;
    final tableMultiplier = etc1sToEacA8[entry + 1];
    final translate = etc1sToEacA8[entry + 2];
    out[o] = etc1sToEacA8[entry];
    // Stored as (table << 4) | multiplier; the block wants them swapped.
    out[o + 1] = ((tableMultiplier & 15) << 4) | (tableMultiplier >> 4);
    // 48 selector bits, big-endian, texel (x, y) at bit 45 - (y + x * 4) * 3.
    var hiBits = 0; // bits 47..24
    var loBits = 0; // bits 23..0
    for (var y = 0; y < 4; y++) {
      final row = selectors[s * 4 + y];
      for (var x = 0; x < 4; x++) {
        final code = (translate >> (((row >> (x * 2)) & 3) * 3)) & 7;
        final shift = 45 - (y + x * 4) * 3;
        if (shift >= 24) {
          hiBits |= code << (shift - 24);
        } else {
          loBits |= code << shift;
        }
      }
    }
    out[o + 2] = hiBits >> 16;
    out[o + 3] = (hiBits >> 8) & 0xFF;
    out[o + 4] = hiBits & 0xFF;
    out[o + 5] = loBits >> 16;
    out[o + 6] = (loBits >> 8) & 0xFF;
    out[o + 7] = loBits & 0xFF;
  }

  /// Writes a BC4 block at [out]+[o] for alpha-slice endpoint [e] and
  /// selector [s].
  void writeBc4(Uint8List out, int o, int e, int s) {
    final value = endpoints[e * 4];
    final inten = endpoints[e * 4 + 3];
    final low = _low[s];
    final high = _high[s];
    if (low == high) {
      final a = _clamp255(expand5(value) + etc1IntenTables[inten][low]);
      out[o] = a;
      out[o + 1] = a;
      for (var i = 2; i < 8; i++) {
        out[o + i] = 0;
      }
      return;
    }
    final int a0;
    final int a1;
    final int translate;
    if (_uniqueCount[s] == 2) {
      // Two alphas: one on each endpoint.
      final base = expand5(value);
      a0 = _clamp255(base + etc1IntenTables[inten][low]);
      a1 = _clamp255(base + etc1IntenTables[inten][high]);
      translate = 1 << (high * 3);
    } else {
      final entry =
          ((inten * 32 + value) * 4 + etc1sAlphaRangeIndex(low, high)) * 3;
      a0 = etc1sToBc4[entry];
      a1 = etc1sToBc4[entry + 1];
      translate = etc1sToBc4[entry + 2];
    }
    out[o] = a0;
    out[o + 1] = a1;
    // 48 selector bits, little-endian, texel (x, y) at bit (y * 4 + x) * 3.
    var lowBits = 0; // texels 0-7
    var highBits = 0; // texels 8-15
    for (var y = 0; y < 4; y++) {
      final row = selectors[s * 4 + y];
      for (var x = 0; x < 4; x++) {
        final code = (translate >> (((row >> (x * 2)) & 3) * 3)) & 7;
        final texel = y * 4 + x;
        if (texel < 8) {
          lowBits |= code << (texel * 3);
        } else {
          highBits |= code << ((texel - 8) * 3);
        }
      }
    }
    for (var i = 0; i < 3; i++) {
      out[o + 2 + i] = (lowBits >> (i * 8)) & 0xFF;
      out[o + 5 + i] = (highBits >> (i * 8)) & 0xFF;
    }
  }

  static void _writeBc1Colors(Uint8List out, int o, int color0, int color1) {
    out[o] = color0 & 0xFF;
    out[o + 1] = color0 >> 8;
    out[o + 2] = color1 & 0xFF;
    out[o + 3] = color1 >> 8;
  }
}

/// Writes an EAC A8 block that decodes to alpha 255 at [out]+[o].
void writeOpaqueEacA8(Uint8List out, int o) {
  for (var i = 0; i < 8; i++) {
    out[o + i] = _opaqueEacBlock[i];
  }
}

/// Writes a BC4 block that decodes to alpha 255 at [out]+[o].
void writeOpaqueBc4(Uint8List out, int o) {
  out[o] = 255;
  out[o + 1] = 255;
  for (var i = 2; i < 8; i++) {
    out[o + i] = 0;
  }
}

int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
