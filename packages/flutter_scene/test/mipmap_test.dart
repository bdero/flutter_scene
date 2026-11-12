/// Covers CPU mip-chain generation: chain sizing, and content-aware
/// downsampling (sRGB color averaged in linear light, data averaged directly,
/// normals averaged as vectors and renormalized). The color chain converts
/// through tables and must give the bytes of the `pow` conversion.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:test/test.dart';

Uint8List _solid(int w, int h, int r, int g, int b, int a) {
  final p = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    p[i * 4] = r;
    p[i * 4 + 1] = g;
    p[i * 4 + 2] = b;
    p[i * 4 + 3] = a;
  }
  return p;
}

double _linear(int byte) {
  final c = byte / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int _srgbByte(double linear) {
  final c = linear <= 0.0031308
      ? linear * 12.92
      : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;
  return (c * 255.0).round().clamp(0, 255);
}

// One color level downsampled with `pow` per channel, sampling as the chain
// does.
Uint8List _powLevel(Uint8List src, int sw, int sh, int dw, int dh) {
  final dst = Uint8List(dw * dh * 4);
  int first(int coordinate, int extent) =>
      coordinate * 2 < extent ? coordinate * 2 : extent - 1;
  for (var y = 0; y < dh; y++) {
    final y0 = first(y, sh);
    final y1 = y0 + 1 < sh ? y0 + 1 : sh - 1;
    for (var x = 0; x < dw; x++) {
      final x0 = first(x, sw);
      final x1 = x0 + 1 < sw ? x0 + 1 : sw - 1;
      final a = (y0 * sw + x0) * 4;
      final b = (y0 * sw + x1) * 4;
      final c = (y1 * sw + x0) * 4;
      final d = (y1 * sw + x1) * 4;
      final o = (y * dw + x) * 4;
      for (var ch = 0; ch < 3; ch++) {
        dst[o + ch] = _srgbByte(
          (_linear(src[a + ch]) +
                  _linear(src[b + ch]) +
                  _linear(src[c + ch]) +
                  _linear(src[d + ch])) *
              0.25,
        );
      }
      dst[o + 3] =
          ((src[a + 3] + src[b + 3] + src[c + 3] + src[d + 3]) + 2) ~/ 4;
    }
  }
  return dst;
}

void _expectPowChain(Uint8List pixels, int width, int height, String what) {
  final chain = generateMipChain(pixels, width, height, TextureContent.color);
  for (var level = 1; level < chain.length; level++) {
    final above = chain[level - 1];
    final expected = _powLevel(
      above.pixels,
      above.width,
      above.height,
      chain[level].width,
      chain[level].height,
    );
    expect(
      chain[level].pixels,
      expected,
      reason: '$what level $level holds the pow bytes',
    );
  }
}

Uint8List _block(int a, int b, int c, int d, {int alpha = 255}) {
  final pixels = Uint8List(2 * 2 * 4);
  final bytes = [a, b, c, d];
  for (var texel = 0; texel < 4; texel++) {
    pixels.fillRange(texel * 4, texel * 4 + 3, bytes[texel]);
    pixels[texel * 4 + 3] = alpha;
  }
  return pixels;
}

Uint8List _randomPixels(int width, int height, int seed) {
  final random = math.Random(seed);
  return Uint8List.fromList([
    for (var i = 0; i < width * height * 4; i++) random.nextInt(256),
  ]);
}

void main() {
  test('mipLevelCountFor is floor(log2(max)) + 1', () {
    expect(mipLevelCountFor(256, 256), 9);
    expect(mipLevelCountFor(1, 1), 1);
    expect(mipLevelCountFor(8, 2), 4);
  });

  test('chain halves down to 1x1 with level 0 first', () {
    final chain = generateMipChain(
      _solid(4, 4, 10, 20, 30, 255),
      4,
      4,
      TextureContent.data,
    );
    expect(chain.map((l) => '${l.width}x${l.height}'), ['4x4', '2x2', '1x1']);
    // A solid image stays solid at every level.
    expect(chain.last.pixels, [10, 20, 30, 255]);
  });

  test('color content averages in linear light, not naively', () {
    // A 2x2 checker of black and white. Naive byte average = 127; correct
    // linear average is 0.5 in linear -> ~188 in sRGB.
    final pixels = Uint8List.fromList([
      0, 0, 0, 255, // black
      255, 255, 255, 255, // white
      255, 255, 255, 255, // white
      0, 0, 0, 255, // black
    ]);
    final chain = generateMipChain(pixels, 2, 2, TextureContent.color);
    final mip = chain[1].pixels; // 1x1
    expect(mip[0], greaterThan(180));
    expect(mip[0], lessThan(195));
  });

  test('data content averages bytes directly', () {
    final pixels = Uint8List.fromList([
      0, 0, 0, 0, //
      255, 255, 255, 255, //
      255, 255, 255, 255, //
      0, 0, 0, 0, //
    ]);
    final chain = generateMipChain(pixels, 2, 2, TextureContent.data);
    expect(chain[1].pixels, [128, 128, 128, 128]);
  });

  test('normal content renormalizes to a unit vector', () {
    // Flat normals (0,0,1) encoded as (128,128,255) stay flat.
    final chain = generateMipChain(
      _solid(2, 2, 128, 128, 255, 255),
      2,
      2,
      TextureContent.normal,
    );
    final mip = chain[1].pixels;
    expect(mip[0], closeTo(128, 1));
    expect(mip[1], closeTo(128, 1));
    expect(mip[2], closeTo(255, 1));
  });

  group('the color chain gives the bytes of the pow conversion', () {
    test('every ordered pair of source bytes', () {
      for (var a = 0; a < 256; a++) {
        for (var b = 0; b < 256; b++) {
          _expectPowChain(_block(a, a, b, b), 2, 2, 'pair $a and $b');
        }
      }
    });

    test('every block of the bytes below the sRGB knee', () {
      for (var a = 0; a <= 12; a++) {
        for (var b = 0; b <= 12; b++) {
          for (var c = 0; c <= 12; c++) {
            for (var d = 0; d <= 12; d++) {
              _expectPowChain(_block(a, b, c, d), 2, 2, 'knee $a $b $c $d');
            }
          }
        }
      }
    });

    test('pow gives the byte below each rounding edge under its fallback '
        'band and the byte above over it', () {
      final bands = srgbEdgeFallbackBands;
      expect(bands, hasLength(255));
      for (var byte = 1; byte < 256; byte++) {
        expect(_srgbByte(bands[byte - 1].below), byte - 1, reason: '$byte');
        expect(_srgbByte(bands[byte - 1].above), byte, reason: '$byte');
      }
    });

    test('images of odd sizes filled with random bytes', () {
      var seed = 7;
      for (final [width, height] in [
        [1, 7],
        [7, 1],
        [5, 3],
        [17, 9],
        [129, 71],
        [256, 256],
      ]) {
        _expectPowChain(
          _randomPixels(width, height, seed++),
          width,
          height,
          '$width by $height',
        );
      }
    });
  });
}
