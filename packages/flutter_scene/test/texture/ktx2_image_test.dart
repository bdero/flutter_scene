import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
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

    test('builds a mip chain matching the engine mip count', () {
      const w = 16, h = 16;
      final texture = encodeImageToKtx2(
        _gradient(w, h),
        w,
        h,
        generateMips: true,
      );
      // The engine stops one short of 1x1: 16 -> 8 -> 4 -> 2 is four levels.
      expect(texture.levels, hasLength(engineMipLevelCount(w, h)));
      expect(texture.levels, hasLength(4));

      for (var level = 0; level < texture.levels.length; level++) {
        final size = mipSize(w, h, level);
        final decoded = decodeKtx2Level(texture, level: level);
        expect(decoded.width, size.width);
        expect(decoded.height, size.height);
      }
    });

    test('mip downsampling averages sRGB color in linear light', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          final v = x.isEven ? 0 : 255;
          rgba[i] = v;
          rgba[i + 1] = v;
          rgba[i + 2] = v;
          rgba[i + 3] = 255;
        }
      }
      final texture = encodeImageToKtx2(rgba, w, h, generateMips: true);
      final mip = decodeKtx2Level(texture, level: 1);
      // A black/white stripe averages to sRGB ~188 in linear light; averaging
      // the encoded bytes directly would give 128.
      expect(mip.rgba[0], greaterThan(170));
    });

    test('normal-map mips renormalize instead of averaging channels', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          rgba[i] = x.isEven ? 255 : 0; // Opposed +x/-x tangent normals.
          rgba[i + 1] = 128;
          rgba[i + 2] = 128;
          rgba[i + 3] = 255;
        }
      }
      final texture = encodeImageToKtx2(
        rgba,
        w,
        h,
        generateMips: true,
        content: TextureContent.normal,
      );
      final mip = decodeKtx2Level(texture, level: 1);
      // Opposed normals cancel; renormalization falls back to +z, where plain
      // channel averaging would leave z near 128.
      expect(mip.rgba[2], greaterThan(200));
    });

    test('engine mip count stops one level short of 1x1', () {
      expect(engineMipLevelCount(64, 64), 6); // not 7
      expect(engineMipLevelCount(2048, 2048), 11); // not 12
      expect(engineMipLevelCount(1, 1), 1);
      expect(engineMipLevelCount(64, 32), 5);
    });

    test('reports a smaller payload than rgba8', () {
      const w = 64, h = 64;
      final bytes = encodeImageToKtx2Bytes(_gradient(w, h), w, h);
      // Block payload is 1 byte/texel; the file (plus a small header) is well
      // under the 4 bytes/texel of raw rgba8.
      expect(bytes.length, lessThan(w * h * 4));
    });

    test('round-trips a supercompressed image and shrinks it further', () {
      const w = 64, h = 64;
      final rgba = _gradient(w, h);
      final plain = encodeImageToKtx2Bytes(rgba, w, h);
      final packed = encodeImageToKtx2Bytes(rgba, w, h, supercompress: true);

      // A smooth gradient compresses well, so the supercompressed file is
      // smaller than the raw-block file.
      expect(packed.length, lessThan(plain.length));

      final decoded = decodeKtx2Level(readKtx2(packed));
      expect(decoded.width, w);
      expect(decoded.height, h);
      expect(_psnr(rgba, decoded.rgba), greaterThan(36));
    });

    test('round-trips supercompressed mips', () {
      const w = 32, h = 32;
      final texture = encodeImageToKtx2(
        _gradient(w, h),
        w,
        h,
        generateMips: true,
        supercompress: true,
      );
      for (var level = 0; level < texture.levels.length; level++) {
        final size = mipSize(w, h, level);
        final decoded = decodeKtx2Level(texture, level: level);
        expect(decoded.width, size.width);
        expect(decoded.height, size.height);
      }
    });
  });
}
