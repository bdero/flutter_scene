import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/transcode_bc1.dart';
import 'package:flutter_scene/src/texture/block/universal_block.dart';
import 'package:flutter_test/flutter_test.dart';

double _psnrRgb(Uint8List a, Uint8List b) {
  // Compare RGB only; BC1 carries no alpha.
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

void main() {
  group('BC1 transcode', () {
    test('produces 8 bytes per block', () {
      final blocks = encodeUniversalBlocks(Uint8List(16 * 16 * 4), 16, 16);
      final bc1 = transcodeUniversalToBc1(blocks, _blockCount(16, 16));
      expect(bc1.length, _blockCount(16, 16) * 8);
      // Half the size of our 16-byte blocks.
      expect(bc1.length, blocks.length ~/ 2);
    });

    test('keeps a solid color through transcode', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = 180;
        rgba[i * 4 + 1] = 90;
        rgba[i * 4 + 2] = 40;
        rgba[i * 4 + 3] = 255;
      }
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final bc1 = transcodeUniversalToBc1(blocks, _blockCount(w, h));
      final decoded = decodeBc1ToRgba8(bc1, w, h);
      // Only the RGB565 endpoint quantization error remains.
      expect(_psnrRgb(rgba, decoded), greaterThan(33));
    });

    test('approximates a gradient via the BC1 path', () {
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
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final bc1 = transcodeUniversalToBc1(blocks, _blockCount(w, h));
      final viaBc1 = decodeBc1ToRgba8(bc1, w, h);

      // BC1 has 2-bit weights and RGB565 endpoints, so it is lossier than the
      // source but should still track the gradient.
      expect(_psnrRgb(rgba, viaBc1), greaterThan(28));
    });

    test('keeps blocks with 565-equal endpoints opaque', () {
      // Endpoints that differ in rgba8 but quantize to the same RGB565 value.
      // Before the equal-endpoint guard, such a block was emitted in BC1's
      // 3-color mode, where weights in the index-3 band decode as transparent
      // black (white speckles on opaque textures).
      final block = Uint8List(kBlockBytes);
      block.setRange(0, 4, [100, 100, 100, 255]);
      block.setRange(4, 8, [103, 101, 102, 255]);
      for (var i = 0; i < 8; i++) {
        // Weights sweep 0..15, covering every index band.
        block[8 + i] = (i * 2) | ((i * 2 + 1) << 4);
      }
      final bc1 = transcodeUniversalToBc1(block, 1);
      final decoded = decodeBc1ToRgba8(bc1, 4, 4);
      for (var i = 0; i < decoded.length; i += 4) {
        expect(decoded[i + 3], 255);
        // Every texel is the shared endpoint color, (100,100,100) through
        // RGB565 quantization and bit-replicated expansion.
        expect(decoded[i], 99);
        expect(decoded[i + 1], 101);
        expect(decoded[i + 2], 99);
      }
    });

    test('never produces transparent texels from opaque input', () {
      const w = 32, h = 32;
      final rng = math.Random(7);
      final rgba = Uint8List(w * h * 4);
      // Near-flat noise, the case that collapses endpoints to equal 565
      // values while keeping nonzero weights.
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 100 + rng.nextInt(4);
        rgba[i + 1] = 100 + rng.nextInt(4);
        rgba[i + 2] = 100 + rng.nextInt(4);
        rgba[i + 3] = 255;
      }
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final bc1 = transcodeUniversalToBc1(blocks, _blockCount(w, h));
      final decoded = decodeBc1ToRgba8(bc1, w, h);
      for (var i = 3; i < decoded.length; i += 4) {
        expect(decoded[i], 255);
      }
    });

    test('stays close to the universal-block decode it transcodes from', () {
      const w = 32, h = 32;
      final rng = math.Random(5);
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = rng.nextInt(256);
        rgba[i + 1] = rng.nextInt(256);
        rgba[i + 2] = rng.nextInt(256);
        rgba[i + 3] = 255;
      }
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final viaBlocks = decodeUniversalBlocksToRgba8(blocks, w, h);
      final viaBc1 = decodeBc1ToRgba8(
        transcodeUniversalToBc1(blocks, _blockCount(w, h)),
        w,
        h,
      );
      // The transcode should not diverge wildly from the block decode.
      expect(_psnrRgb(viaBlocks, viaBc1), greaterThan(24));
    });
  });
}
