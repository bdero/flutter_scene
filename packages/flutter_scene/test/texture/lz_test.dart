import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/supercompress/lz.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _roundTrip(Uint8List input) =>
    lzDecompress(lzCompress(input), input.length);

void main() {
  group('LZ supercompression', () {
    test('round-trips empty input', () {
      expect(_roundTrip(Uint8List(0)), isEmpty);
    });

    test('round-trips incompressible random bytes', () {
      final rng = math.Random(11);
      final input = Uint8List.fromList(
        List.generate(4096, (_) => rng.nextInt(256)),
      );
      expect(_roundTrip(input), input);
    });

    test('round-trips and shrinks highly repetitive bytes', () {
      final input = Uint8List(8192);
      for (var i = 0; i < input.length; i++) {
        input[i] = (i ~/ 64) & 0xFF; // long runs
      }
      final compressed = lzCompress(input);
      expect(lzDecompress(compressed, input.length), input);
      expect(compressed.length, lessThan(input.length ~/ 4));
    });

    test('round-trips a repeated pattern with back-references', () {
      final pattern = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final input = Uint8List(8 * 500);
      for (var i = 0; i < input.length; i++) {
        input[i] = pattern[i % pattern.length];
      }
      final compressed = lzCompress(input);
      expect(lzDecompress(compressed, input.length), input);
      expect(compressed.length, lessThan(input.length ~/ 10));
    });

    test('round-trips a single byte', () {
      expect(_roundTrip(Uint8List.fromList([42])), [42]);
    });
  });
}
