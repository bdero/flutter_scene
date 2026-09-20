import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/material/dfg_lut_data.dart';
import 'package:flutter_scene/src/texture/half_float.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shipped table must be exactly what the integration produces: the
/// runtime picks one or the other (asset, or the isolate fallback), so any
/// drift would show as a lighting difference between two builds of the same
/// app.
void main() {
  late Uint16List asset;

  setUpAll(() {
    final file = File('assets/dfg.bin');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run `dart run tool/generate_dfg_lut.dart`',
    );
    final bytes = file.readAsBytesSync();
    expect(bytes.length, kDfgLutTileBytes);
    asset = bytes.buffer.asUint16List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 2,
    );
  });

  test('assets/dfg.bin is bit-identical to the CPU integration', () {
    final computed = buildDfgLutHalfData();
    expect(computed.length, asset.length);
    var maxAbsError = 0.0;
    var differing = 0;
    for (var i = 0; i < computed.length; i++) {
      if (computed[i] != asset[i]) {
        differing++;
        final error =
            (halfBitsToDouble(computed[i]) - halfBitsToDouble(asset[i])).abs();
        if (error > maxAbsError) maxAbsError = error;
      }
    }
    expect(
      differing,
      0,
      reason:
          '$differing of ${computed.length} half floats differ, '
          'max abs error $maxAbsError',
    );
  });

  test('the table holds plausible split-sum terms', () {
    for (var y = 0; y < kDfgLutSize; y++) {
      for (var x = 0; x < kDfgLutSize; x++) {
        final o = (y * kDfgLutSize + x) * 4;
        final scale = halfBitsToDouble(asset[o]);
        final bias = halfBitsToDouble(asset[o + 1]);
        expect(scale, inInclusiveRange(0.0, 1.0));
        expect(bias, inInclusiveRange(0.0, 1.0));
        expect(scale + bias, lessThanOrEqualTo(1.01));
        expect(halfBitsToDouble(asset[o + 2]), 0.0);
        expect(halfBitsToDouble(asset[o + 3]), 1.0);
      }
    }
    // A mirror at grazing-free incidence keeps nearly all of its energy.
    final smooth = (0 * kDfgLutSize + kDfgLutSize - 1) * 4;
    expect(
      halfBitsToDouble(asset[smooth]) + halfBitsToDouble(asset[smooth + 1]),
      greaterThan(0.9),
    );
  });
}
