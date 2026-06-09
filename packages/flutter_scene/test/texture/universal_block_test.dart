import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/universal_block.dart';
import 'package:flutter_test/flutter_test.dart';

double _psnr(Uint8List a, Uint8List b) {
  assert(a.length == b.length);
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  final mse = sum / a.length;
  if (mse == 0) return double.infinity;
  return 10 * (math.log(255 * 255 / mse) / math.ln10);
}

Uint8List _solid(int w, int h, int r, int g, int b, int a) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  }
  return out;
}

Uint8List _roundTrip(Uint8List rgba, int w, int h) =>
    decodeUniversalBlocksToRgba8(encodeUniversalBlocks(rgba, w, h), w, h);

void main() {
  group('universal block codec', () {
    test('compresses to one byte per texel', () {
      final blocks = encodeUniversalBlocks(_solid(8, 8, 10, 20, 30, 255), 8, 8);
      // 8x8 = 4 blocks of 16 bytes = 64 bytes for 64 texels.
      expect(blocks.length, 64);
      expect(blocks.length, (8 * 8 * 4) ~/ 4);
    });

    test('reproduces a solid block exactly', () {
      final rgba = _solid(4, 4, 200, 100, 50, 255);
      expect(_roundTrip(rgba, 4, 4), rgba);
    });

    test('reproduces a solid translucent block exactly', () {
      final rgba = _solid(4, 4, 12, 240, 7, 128);
      expect(_roundTrip(rgba, 4, 4), rgba);
    });

    test('keeps a two-color split within tight error', () {
      // A block split between two colors lies on one line, so the two-endpoint
      // fit should be near-exact.
      final rgba = Uint8List(4 * 4 * 4);
      for (var i = 0; i < 16; i++) {
        final c = i < 8 ? 30 : 220;
        rgba[i * 4] = c;
        rgba[i * 4 + 1] = c;
        rgba[i * 4 + 2] = c;
        rgba[i * 4 + 3] = 255;
      }
      expect(_psnr(rgba, _roundTrip(rgba, 4, 4)), greaterThan(45));
    });

    test('keeps a smooth gradient at high quality', () {
      const w = 64, h = 64;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          rgba[i] = (x * 255 ~/ (w - 1));
          rgba[i + 1] = (y * 255 ~/ (h - 1));
          rgba[i + 2] = ((x + y) * 255 ~/ (w + h - 2));
          rgba[i + 3] = 255;
        }
      }
      expect(_psnr(rgba, _roundTrip(rgba, w, h)), greaterThan(38));
    });

    test('stays reasonable on pseudo-random content', () {
      const w = 32, h = 32;
      final rng = math.Random(7);
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i++) {
        rgba[i] = rng.nextInt(256);
      }
      // Pure noise has no color line, so a single-line fit is the worst case;
      // quality is low but bounded (real textures are locally coherent and do
      // far better, see the gradient test).
      expect(_psnr(rgba, _roundTrip(rgba, w, h)), greaterThan(12));
    });

    test('handles dimensions that are not multiples of four', () {
      const w = 13, h = 7;
      final rng = math.Random(3);
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i++) {
        rgba[i] = rng.nextInt(256);
      }
      final decoded = _roundTrip(rgba, w, h);
      expect(decoded.length, w * h * 4);
      // 4x2 blocks cover 13x7.
      expect(encodeUniversalBlocks(rgba, w, h).length, 4 * 2 * 16);
    });
  });
}
