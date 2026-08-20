// Verifies the standard-KTX2 (Basis Universal UASTC) decode path against
// reference goldens.
//
// Fixture provenance (test/fixtures/ktx2/): uastc_srgb_mips_zstd_64.ktx2,
// uastc_linear_20x14.ktx2, and uastc_alpha_srgb_32.ktx2 were encoded with the
// KTX-Software v4.4.2 `ktx create` CLI from deterministic PNGs;
// luminance_alpha_reference_uastc.ktx2 is KhronosGroup/KTX-Software
// tests/testimages at v4.4.2. Each .rgba golden is the same tool's
// `ktx extract --transcode rgba8 --raw` output, levels concatenated base
// first; the decoder must match it byte for byte.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/basis_ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/ktx2/$name').readAsBytesSync();

Uint8List _concat(List<Uint8List> parts) {
  final builder = BytesBuilder(copy: false);
  parts.forEach(builder.add);
  return builder.toBytes();
}

List<int> _texel(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return rgba.sublist(i, i + 4);
}

void main() {
  group('standard KTX2 UASTC decode', () {
    test('sRGB mipped zstd file matches the reference, every level', () {
      final image = decodeStandardKtx2(
        readKtx2(_fixture('uastc_srgb_mips_zstd_64.ktx2')),
      );
      expect(image.levels.length, 7);
      expect(image.srgb, isTrue);
      expect(image.hasAlpha, isFalse);
      expect(image.levels.first.width, 64);
      expect(image.levels.first.height, 64);
      expect(image.levels.last.width, 1);
      expect(_texel(image.levels[0].pixels, 64, 0, 0), [244, 225, 25, 255]);
      expect(_texel(image.levels[0].pixels, 64, 33, 17), [136, 224, 237, 255]);
      expect(_texel(image.levels[2].pixels, 16, 7, 9), [223, 102, 225, 255]);
      expect(_texel(image.levels[6].pixels, 1, 0, 0), [162, 161, 162, 255]);
      expect(
        _concat([for (final level in image.levels) level.pixels]),
        _fixture('uastc_srgb_mips_zstd_64.rgba'),
      );
    });

    test('linear non-block-aligned file matches the reference', () {
      final image = decodeStandardKtx2(
        readKtx2(_fixture('uastc_linear_20x14.ktx2')),
      );
      expect(image.levels.length, 1);
      expect(image.srgb, isFalse);
      expect(image.hasAlpha, isFalse);
      expect(image.levels.first.width, 20);
      expect(image.levels.first.height, 14);
      expect(_texel(image.levels[0].pixels, 20, 0, 0), [0, 0, 6, 255]);
      expect(_texel(image.levels[0].pixels, 20, 19, 13), [255, 255, 84, 255]);
      expect(image.levels[0].pixels, _fixture('uastc_linear_20x14.rgba'));
    });

    test('alpha-bearing file matches the reference', () {
      final image = decodeStandardKtx2(
        readKtx2(_fixture('uastc_alpha_srgb_32.ktx2')),
      );
      expect(image.levels.length, 1);
      expect(image.srgb, isTrue);
      expect(image.hasAlpha, isTrue);
      expect(_texel(image.levels[0].pixels, 32, 16, 16), [16, 113, 201, 255]);
      expect(_texel(image.levels[0].pixels, 32, 0, 0), [0, 0, 201, 0]);
      expect(image.levels[0].pixels, _fixture('uastc_alpha_srgb_32.rgba'));
    });

    test('luminance-alpha channels match the reference', () {
      final image = decodeStandardKtx2(
        readKtx2(_fixture('luminance_alpha_reference_uastc.ktx2')),
      );
      expect(image.levels.length, 1);
      expect(image.srgb, isFalse);
      expect(image.hasAlpha, isTrue);
      expect(_texel(image.levels[0].pixels, 32, 5, 5), [214, 214, 214, 40]);
      expect(_texel(image.levels[0].pixels, 32, 31, 31), [0, 0, 0, 255]);
      expect(
        image.levels[0].pixels,
        _fixture('luminance_alpha_reference_uastc.rgba'),
      );
    });
  });

  group('standard KTX2 detection', () {
    test('recognizes the file identifier', () {
      expect(looksLikeKtx2(_fixture('uastc_linear_20x14.ktx2')), isTrue);
      expect(looksLikeKtx2(Uint8List.fromList([1, 2, 3])), isFalse);
      final wrong = Uint8List.fromList(_fixture('uastc_linear_20x14.ktx2'));
      wrong[0] ^= 0xFF;
      expect(looksLikeKtx2(wrong), isFalse);
    });

    test('standard files are not the engine internal format', () {
      final texture = readKtx2(_fixture('uastc_linear_20x14.ktx2'));
      expect(isInternalKtx2(texture), isFalse);
    });
  });

  group('standard KTX2 malformed input', () {
    test('truncated file throws cleanly', () {
      final bytes = _fixture('uastc_linear_20x14.ktx2');
      expect(
        () => readKtx2(Uint8List.sublistView(bytes, 0, 40)),
        throwsA(isA<Ktx2FormatException>()),
      );
    });

    test('truncated UASTC payload throws cleanly', () {
      final texture = readKtx2(_fixture('uastc_linear_20x14.ktx2'));
      final base = texture.levels.first;
      final short = Ktx2Texture(
        vkFormat: texture.vkFormat,
        pixelWidth: texture.pixelWidth,
        pixelHeight: texture.pixelHeight,
        levels: [Ktx2Level(data: Uint8List.sublistView(base.data, 0, 16))],
        dataFormatDescriptor: texture.dataFormatDescriptor,
      );
      expect(() => decodeStandardKtx2(short), throwsFormatException);
    });

    test('corrupted zstd level throws cleanly', () {
      final bytes = Uint8List.fromList(
        _fixture('uastc_srgb_mips_zstd_64.ktx2'),
      );
      // Flip a byte in the middle of the base level payload.
      bytes[bytes.length - 200] ^= 0xFF;
      Object? error;
      try {
        decodeStandardKtx2(readKtx2(bytes));
      } catch (e) {
        error = e;
      }
      // Damage either trips the decoder or survives to decoded output; it
      // must never escape as a RangeError or other unexpected type.
      expect(
        error,
        anyOf(isNull, isA<FormatException>(), isA<Ktx2FormatException>()),
      );
    });

    test('missing data format descriptor throws cleanly', () {
      final texture = readKtx2(_fixture('uastc_linear_20x14.ktx2'));
      final bare = Ktx2Texture(
        vkFormat: 0,
        pixelWidth: texture.pixelWidth,
        pixelHeight: texture.pixelHeight,
        levels: texture.levels,
      );
      expect(
        () => decodeStandardKtx2(bare),
        throwsA(isA<Ktx2FormatException>()),
      );
    });
  });
}
