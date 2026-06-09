import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/transcode_etc2.dart';
import 'package:flutter_scene/src/texture/block/universal_block.dart';
import 'package:flutter_test/flutter_test.dart';

double _psnrRgb(Uint8List a, Uint8List b) {
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final d = a[i + c] - b[i + c];
      sum += d * d;
      count++;
    }
  }
  final mse = sum / count;
  return mse == 0 ? double.infinity : 10 * (math.log(65025 / mse) / math.ln10);
}

int _blockCount(int w, int h) => ((w + 3) ~/ 4) * ((h + 3) ~/ 4);

Uint8List _viaEtc2(Uint8List rgba, int w, int h) => decodeEtc2RgbToRgba8(
  transcodeUniversalToEtc2Rgb(
    encodeUniversalBlocks(rgba, w, h),
    _blockCount(w, h),
  ),
  w,
  h,
);

void main() {
  group('ETC2 RGB transcode', () {
    test('produces 8 bytes per block', () {
      final blocks = encodeUniversalBlocks(Uint8List(16 * 16 * 4), 16, 16);
      final etc2 = transcodeUniversalToEtc2Rgb(blocks, _blockCount(16, 16));
      expect(etc2.length, _blockCount(16, 16) * 8);
      expect(etc2.length, blocks.length ~/ 2);
    });

    test('keeps a solid color through transcode', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = 70;
        rgba[i * 4 + 1] = 160;
        rgba[i * 4 + 2] = 210;
        rgba[i * 4 + 3] = 255;
      }
      // A solid color needs only the base color; quantization is the only loss.
      expect(_psnrRgb(rgba, _viaEtc2(rgba, w, h)), greaterThan(30));
    });

    test('tracks a luminance ramp (ETC2 strength)', () {
      // ETC1/ETC2 modulate luminance per subblock, so a brightness ramp is its
      // best case.
      const w = 16, h = 16;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          final v = x * 255 ~/ (w - 1);
          rgba[i] = v;
          rgba[i + 1] = v;
          rgba[i + 2] = v;
          rgba[i + 3] = 255;
        }
      }
      expect(_psnrRgb(rgba, _viaEtc2(rgba, w, h)), greaterThan(30));
    });

    test('approximates a color gradient', () {
      const w = 64, h = 64;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          rgba[i] = x * 255 ~/ (w - 1);
          rgba[i + 1] = y * 255 ~/ (h - 1);
          rgba[i + 2] = 128;
          rgba[i + 3] = 255;
        }
      }
      // Color (not just luminance) variation within a block is ETC's weak spot,
      // but it should still track the gradient.
      expect(_psnrRgb(rgba, _viaEtc2(rgba, w, h)), greaterThan(26));
    });
  });
}
