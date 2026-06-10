// Covers the alpha-capable transcoders: universal blocks to BC3 and to ETC2
// RGBA8 (EAC alpha), via their CPU reference decoders, plus the KTX2 alpha
// marker that selects them.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/block/transcode_bc3.dart';
import 'package:flutter_scene/src/texture/block/transcode_etc2.dart';
import 'package:flutter_scene/src/texture/block/universal_block.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_test/flutter_test.dart';

int _blockCount(int w, int h) => ((w + 3) ~/ 4) * ((h + 3) ~/ 4);

double _psnrRgba(Uint8List a, Uint8List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  final mse = sum / a.length;
  return mse == 0 ? double.infinity : 10 * (math.log(65025 / mse) / math.ln10);
}

double _psnrAlpha(Uint8List a, Uint8List b) {
  var sum = 0.0;
  var count = 0;
  for (var i = 3; i < a.length; i += 4) {
    final d = a[i] - b[i];
    sum += d * d;
    count++;
  }
  final mse = sum / count;
  return mse == 0 ? double.infinity : 10 * (math.log(65025 / mse) / math.ln10);
}

/// A color gradient with an independent horizontal alpha ramp.
Uint8List _alphaGradient(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      rgba[i] = (x * 255) ~/ (w - 1);
      rgba[i + 1] = (y * 255) ~/ (h - 1);
      rgba[i + 2] = 128;
      rgba[i + 3] = (x * 255) ~/ (w - 1);
    }
  }
  return rgba;
}

void main() {
  group('BC3 transcode', () {
    test('produces 16 bytes per block', () {
      final blocks = encodeUniversalBlocks(Uint8List(16 * 16 * 4), 16, 16);
      final bc3 = transcodeUniversalToBc3(blocks, _blockCount(16, 16));
      expect(bc3.length, _blockCount(16, 16) * 16);
    });

    test('keeps a solid translucent color through transcode', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = 180;
        rgba[i * 4 + 1] = 90;
        rgba[i * 4 + 2] = 40;
        rgba[i * 4 + 3] = 100;
      }
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final bc3 = transcodeUniversalToBc3(blocks, _blockCount(w, h));
      final decoded = decodeBc3ToRgba8(bc3, w, h);
      for (var i = 0; i < w * h; i++) {
        expect((decoded[i * 4 + 3] - 100).abs(), lessThanOrEqualTo(1));
      }
      expect(_psnrRgba(rgba, decoded), greaterThan(30));
    });

    test('preserves an alpha gradient', () {
      const w = 32, h = 32;
      final rgba = _alphaGradient(w, h);
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final bc3 = transcodeUniversalToBc3(blocks, _blockCount(w, h));
      final decoded = decodeBc3ToRgba8(bc3, w, h);
      expect(_psnrAlpha(rgba, decoded), greaterThan(30));
      expect(_psnrRgba(rgba, decoded), greaterThan(25));
    });
  });

  group('ETC2 RGBA8 transcode', () {
    test('produces 16 bytes per block', () {
      final blocks = encodeUniversalBlocks(Uint8List(16 * 16 * 4), 16, 16);
      final etc2 = transcodeUniversalToEtc2Rgba(blocks, _blockCount(16, 16));
      expect(etc2.length, _blockCount(16, 16) * 16);
    });

    test('keeps a solid translucent color through transcode', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = 60;
        rgba[i * 4 + 1] = 200;
        rgba[i * 4 + 2] = 90;
        rgba[i * 4 + 3] = 64;
      }
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final etc2 = transcodeUniversalToEtc2Rgba(blocks, _blockCount(w, h));
      final decoded = decodeEtc2RgbaToRgba8(etc2, w, h);
      for (var i = 0; i < w * h; i++) {
        expect((decoded[i * 4 + 3] - 64).abs(), lessThanOrEqualTo(1));
      }
      expect(_psnrRgba(rgba, decoded), greaterThan(30));
    });

    test('preserves an alpha gradient', () {
      const w = 32, h = 32;
      final rgba = _alphaGradient(w, h);
      final blocks = encodeUniversalBlocks(rgba, w, h);
      final etc2 = transcodeUniversalToEtc2Rgba(blocks, _blockCount(w, h));
      final decoded = decodeEtc2RgbaToRgba8(etc2, w, h);
      expect(_psnrAlpha(rgba, decoded), greaterThan(30));
      expect(_psnrRgba(rgba, decoded), greaterThan(25));
    });
  });

  group('KTX2 alpha marker', () {
    test('set only when the source has non-opaque alpha', () {
      const w = 8, h = 8;
      final opaque = Uint8List(w * h * 4);
      for (var i = 3; i < opaque.length; i += 4) {
        opaque[i] = 255;
      }
      expect(ktx2HasAlpha(encodeImageToKtx2(opaque, w, h)), isFalse);

      final translucent = Uint8List.fromList(opaque);
      translucent[3] = 128;
      expect(ktx2HasAlpha(encodeImageToKtx2(translucent, w, h)), isTrue);
    });

    test('alpha survives the rgba8 decode path', () {
      const w = 8, h = 8;
      final rgba = _alphaGradient(w, h);
      final texture = encodeImageToKtx2(rgba, w, h, supercompress: true);
      final decoded = decodeKtx2Level(texture);
      expect(_psnrAlpha(rgba, decoded.rgba), greaterThan(30));
    });
  });
}
