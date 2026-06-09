import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/transcode_astc.dart';
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

Uint8List _viaAstc(Uint8List rgba, int w, int h) => decodeAstc4x4ToRgba8(
  transcodeUniversalToAstc4x4(
    encodeUniversalBlocks(rgba, w, h),
    _blockCount(w, h),
  ),
  w,
  h,
);

void main() {
  group('ASTC 4x4 transcode', () {
    test('produces 16 bytes per block', () {
      final blocks = encodeUniversalBlocks(Uint8List(16 * 16 * 4), 16, 16);
      final astc = transcodeUniversalToAstc4x4(blocks, _blockCount(16, 16));
      expect(astc.length, _blockCount(16, 16) * 16);
    });

    test('writes the fixed block mode and CEM', () {
      final astc = transcodeUniversalToAstc4x4(
        encodeUniversalBlocks(Uint8List(4 * 4 * 4), 4, 4),
        1,
      );
      // Block mode is bits [10:0] = 0x53.
      final blockMode = astc[0] | ((astc[1] & 0x7) << 8);
      expect(blockMode, 0x53);
      // Partition bits [12:11] = 0, CEM bits [16:13] = 8.
      final lowHalf = astc[1] | (astc[2] << 8);
      final partition = (lowHalf >> 3) & 0x3; // bits 11-12
      final cem = (lowHalf >> 5) & 0xF; // bits 13-16
      expect(partition, 0);
      expect(cem, 8);
    });

    test('keeps a solid color through transcode', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = 200;
        rgba[i * 4 + 1] = 120;
        rgba[i * 4 + 2] = 60;
        rgba[i * 4 + 3] = 255;
      }
      // 8-bit endpoints reproduce a solid color exactly.
      expect(_psnrRgb(rgba, _viaAstc(rgba, w, h)), greaterThan(45));
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
      // 8-bit endpoints + 3-bit weights track the gradient well.
      expect(_psnrRgb(rgba, _viaAstc(rgba, w, h)), greaterThan(30));
    });
  });
}
