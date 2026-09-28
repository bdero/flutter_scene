// Checks the ETC1S conversion tables.

import 'dart:convert';

import 'package:flutter_scene/src/texture/basisu/etc1s_bc1_table_data.dart';
import 'package:flutter_scene/src/texture/basisu/etc1s_tables.dart';
import 'package:flutter_test/flutter_test.dart';

int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// basis_universal's exhaustive EAC A8 fit: the base, multiplier and table
/// with the least squared error over [values], first found wins.
(int base, int tableMultiplier) _fitEac(List<int> values) {
  var bestError = 1 << 62;
  var best = (0, 0);
  for (var base = 0; base < 256; base++) {
    for (var multiplier = 1; multiplier < 16; multiplier++) {
      for (var table = 0; table < 16; table++) {
        var error = 0;
        for (final a in values) {
          var nearest = 1 << 30;
          for (final m in eacModifierTables[table]) {
            final d = (a - _clamp255(base + m * multiplier)).abs();
            if (d < nearest) nearest = d;
          }
          error += nearest * nearest;
          if (error >= bestError) break;
        }
        if (error < bestError) {
          bestError = error;
          best = (base, (table << 4) | multiplier);
        }
      }
    }
  }
  return best;
}

List<int> _bc4Palette(int a0, int a1) => a0 > a1
    ? [a0, a1, for (var i = 1; i < 7; i++) ((7 - i) * a0 + i * a1) ~/ 7]
    : [
        a0,
        a1,
        for (var i = 1; i < 5; i++) ((5 - i) * a0 + i * a1) ~/ 5,
        0,
        255,
      ];

void main() {
  test('stored BC1 tables match the exhaustive search', () {
    expect(base64.decode(etc1sBc1Table5Data), buildEtc1sBc1Table(5));
    expect(base64.decode(etc1sBc1Table6Data), buildEtc1sBc1Table(6));
  });

  test('BC1 solutions report their own squared error', () {
    final table = Etc1sBc1Table.sixBit;
    // Intensity 3, green 20, full range, mapping 6 (the even spread).
    final i = Etc1sBc1Table.indexOf(3, 20, 0) + 6;
    final colors = etc1sChannelColors(20, 3);
    final c0 = expand6(table.lo[i]);
    final c3 = expand6(table.hi[i]);
    final palette = [c0, (c0 * 2 + c3) ~/ 3, (c3 * 2 + c0) ~/ 3, c3];
    var error = 0;
    for (var s = 0; s < 4; s++) {
      error += (colors[s] - palette[s]) * (colors[s] - palette[s]);
    }
    expect(table.error[i], error);
  });

  test('EAC entries are the exhaustive fit (sampled)', () {
    for (var entry = 0; entry < 1024; entry += 37) {
      final row = entry ~/ 4;
      final (low, high) = etc1sAlphaRanges[entry % 4];
      final colors = etc1sChannelColors(row % 32, row ~/ 32);
      final (base, tableMultiplier) = _fitEac([
        for (var s = low; s <= high; s++) colors[s],
      ]);
      expect(etc1sToEacA8[entry * 3], base, reason: 'entry $entry base');
      expect(
        etc1sToEacA8[entry * 3 + 1],
        tableMultiplier,
        reason: 'entry $entry table and multiplier',
      );
    }
  });

  test('every alpha entry reproduces its values closely', () {
    var worstEac = 0;
    var worstBc4 = 0;
    for (var entry = 0; entry < 1024; entry++) {
      final row = entry ~/ 4;
      final (low, high) = etc1sAlphaRanges[entry % 4];
      final colors = etc1sChannelColors(row % 32, row ~/ 32);
      final eacBase = etc1sToEacA8[entry * 3];
      final eacTable = etc1sToEacA8[entry * 3 + 1] >> 4;
      final eacMultiplier = etc1sToEacA8[entry * 3 + 1] & 15;
      final eacSelectors = etc1sToEacA8[entry * 3 + 2];
      final bc4 = _bc4Palette(etc1sToBc4[entry * 3], etc1sToBc4[entry * 3 + 1]);
      final bc4Selectors = etc1sToBc4[entry * 3 + 2];
      for (var s = low; s <= high; s++) {
        final eac = _clamp255(
          eacBase +
              eacModifierTables[eacTable][(eacSelectors >> (s * 3)) & 7] *
                  eacMultiplier,
        );
        final eacError = (eac - colors[s]).abs();
        if (eacError > worstEac) worstEac = eacError;
        final bc4Error = (bc4[(bc4Selectors >> (s * 3)) & 7] - colors[s]).abs();
        if (bc4Error > worstBc4) worstBc4 = bc4Error;
      }
    }
    // The tables' own worst cases; anything larger is a damaged entry.
    expect(worstEac, 3);
    expect(worstBc4, 9);
  });

  test('BC1 row translation maps selectors through the mapping', () {
    // Mapping 6 is the even spread: selector 0 -> color0 (index 0), 1 -> the
    // third nearer color0 (index 2), 2 -> index 3, 3 -> color1 (index 1).
    const row = 0 | (1 << 2) | (2 << 4) | (3 << 6);
    expect(bc1RowForward[6][row], 0 | (2 << 2) | (3 << 4) | (1 << 6));
    // With the endpoints swapped every index swaps its partner.
    expect(bc1RowInverted[6][row], 1 | (3 << 2) | (2 << 4) | (0 << 6));
  });

  test('single-color BC1 fits land on the value', () {
    for (var value = 0; value < 256; value += 17) {
      final m5 = Bc1SingleColor.match5Selector1;
      final lo = expand5(m5.lo[value]);
      final hi = expand5(m5.hi[value]);
      expect(((hi * 2 + lo) ~/ 3 - value).abs(), lessThanOrEqualTo(2));
    }
  });
}
