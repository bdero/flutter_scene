import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_test/flutter_test.dart';

double _psnr(Uint8List a, Uint8List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  final mse = sum / a.length;
  return mse == 0 ? double.infinity : 10 * (math.log(65025 / mse) / math.ln10);
}

Uint8List _gradient(int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      out[i] = x * 255 ~/ (w - 1);
      out[i + 1] = y * 255 ~/ (h - 1);
      out[i + 2] = 128;
      out[i + 3] = 255;
    }
  }
  return out;
}

void main() {
  group('rgba8 <-> KTX2 image', () {
    test('round-trips an image through KTX2 bytes', () {
      const w = 64, h = 64;
      final rgba = _gradient(w, h);
      final bytes = encodeImageToKtx2Bytes(rgba, w, h);

      final decoded = decodeKtx2Level(readKtx2(bytes));
      expect(decoded.width, w);
      expect(decoded.height, h);
      expect(_psnr(rgba, decoded.rgba), greaterThan(36));
    });

    test('writes the block-format marker', () {
      final texture = encodeImageToKtx2(_gradient(8, 8), 8, 8);
      expect(texture.keyValues.containsKey(kFsBlockFormatKey), isTrue);
      expect(
        String.fromCharCodes(texture.keyValues[kFsBlockFormatKey]!),
        kFsBlockFormatUniversal,
      );
    });

    test('rejects an unknown block format', () {
      final texture = Ktx2Texture(
        vkFormat: 0,
        pixelWidth: 4,
        pixelHeight: 4,
        levels: [Ktx2Level(data: Uint8List(16))],
        keyValues: {kFsBlockFormatKey: Uint8List.fromList('other/9'.codeUnits)},
      );
      expect(
        () => decodeKtx2Level(texture),
        throwsA(isA<Ktx2FormatException>()),
      );
    });

    test('builds a full mip chain', () {
      const w = 16, h = 16;
      final texture = encodeImageToKtx2(
        _gradient(w, h),
        w,
        h,
        generateMips: true,
      );
      // 16 -> 8 -> 4 -> 2 -> 1 is five levels.
      expect(texture.levels, hasLength(5));

      for (var level = 0; level < texture.levels.length; level++) {
        final size = mipSize(w, h, level);
        final decoded = decodeKtx2Level(texture, level: level);
        expect(decoded.width, size.width);
        expect(decoded.height, size.height);
      }
    });

    test('reports a smaller payload than rgba8', () {
      const w = 64, h = 64;
      final bytes = encodeImageToKtx2Bytes(_gradient(w, h), w, h);
      // Block payload is 1 byte/texel; the file (plus a small header) is well
      // under the 4 bytes/texel of raw rgba8.
      expect(bytes.length, lessThan(w * h * 4));
    });
  });
}
