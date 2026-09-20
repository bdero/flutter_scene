import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_test/flutter_test.dart';

/// `_downsample` is hand-optimized (the content switch hoisted out of the
/// per-texel loop, the normal path unrolled, the sRGB decode tabulated), so it
/// is checked here against a direct transcription of the filters it implements,
/// byte for byte, on sizes that exercise the odd-extent clamping.
void main() {
  final random = math.Random(20260919);

  Uint8List noise(int width, int height) => Uint8List.fromList([
    for (var i = 0; i < width * height * 4; i++) random.nextInt(256),
  ]);

  for (final (width, height) in [(16, 16), (13, 7), (5, 1), (1, 9), (64, 32)]) {
    for (final content in TextureContent.values) {
      test('${content.name} mips of ${width}x$height match the reference', () {
        final pixels = noise(width, height);
        final chain = generateMipChain(pixels, width, height, content);
        expect(chain.first.pixels, same(pixels));
        var sw = width;
        var sh = height;
        var src = pixels;
        for (var level = 1; level < chain.length; level++) {
          final dw = math.max(1, sw >> 1);
          final dh = math.max(1, sh >> 1);
          expect(chain[level].width, dw);
          expect(chain[level].height, dh);
          expect(
            chain[level].pixels,
            _reference(src, sw, sh, dw, dh, content),
            reason: 'level $level',
          );
          src = chain[level].pixels;
          sw = dw;
          sh = dh;
        }
        expect(sw, 1);
        expect(sh, 1);
      });
    }
  }
}

/// The filters as written in prose: a 2x2 edge-clamped box, averaged in linear
/// light for color, directly for data, and as renormalized vectors for normals.
Uint8List _reference(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
  TextureContent content,
) {
  final dst = Uint8List(dw * dh * 4);
  for (var y = 0; y < dh; y++) {
    final y0 = math.min(y * 2, sh - 1);
    final y1 = math.min(y0 + 1, sh - 1);
    for (var x = 0; x < dw; x++) {
      final x0 = math.min(x * 2, sw - 1);
      final x1 = math.min(x0 + 1, sw - 1);
      final taps = [
        (y0 * sw + x0) * 4,
        (y0 * sw + x1) * 4,
        (y1 * sw + x0) * 4,
        (y1 * sw + x1) * 4,
      ];
      final o = (y * dw + x) * 4;
      switch (content) {
        case TextureContent.color:
          for (var ch = 0; ch < 3; ch++) {
            var sum = 0.0;
            for (final p in taps) {
              sum += _srgbToLinear(src[p + ch]);
            }
            dst[o + ch] = _linearToSrgb(sum * 0.25);
          }
          dst[o + 3] = _average(src, taps, 3);
        case TextureContent.data:
          for (var ch = 0; ch < 4; ch++) {
            dst[o + ch] = _average(src, taps, ch);
          }
        case TextureContent.normal:
          var nx = 0.0, ny = 0.0, nz = 0.0;
          for (final p in taps) {
            nx += src[p] / 127.5 - 1.0;
            ny += src[p + 1] / 127.5 - 1.0;
            nz += src[p + 2] / 127.5 - 1.0;
          }
          final len = math.sqrt(nx * nx + ny * ny + nz * nz);
          if (len > 1e-6) {
            nx /= len;
            ny /= len;
            nz /= len;
          } else {
            nx = 0.0;
            ny = 0.0;
            nz = 1.0;
          }
          dst[o] = _encodeUnit(nx);
          dst[o + 1] = _encodeUnit(ny);
          dst[o + 2] = _encodeUnit(nz);
          dst[o + 3] = 255;
      }
    }
  }
  return dst;
}

int _average(Uint8List src, List<int> taps, int channel) {
  var sum = 2;
  for (final p in taps) {
    sum += src[p + channel];
  }
  return sum ~/ 4;
}

double _srgbToLinear(int byte) {
  final c = byte / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int _linearToSrgb(double linear) {
  final c = linear <= 0.0031308
      ? linear * 12.92
      : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;
  return (c * 255.0).round().clamp(0, 255);
}

int _encodeUnit(double v) => ((v + 1.0) * 127.5).round().clamp(0, 255);
