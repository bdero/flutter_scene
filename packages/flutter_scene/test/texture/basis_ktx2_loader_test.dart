// Checks the upload format per device and the levels the decode produces.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/basis_ktx2_loader.dart';
import 'package:flutter_scene/src/texture/ktx2/dfd.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/ktx2/$name').readAsBytesSync();

const CompressionSupport _none = (astc: false, etc2: false, bc: false);
const CompressionSupport _mobile = (astc: true, etc2: true, bc: false);
const CompressionSupport _desktop = (astc: false, etc2: false, bc: true);
const CompressionSupport _appleSilicon = (astc: true, etc2: true, bc: true);

StandardKtx2Upload _choose({
  int colorModel = kDfModelEtc1s,
  bool hasAlpha = false,
  int width = 64,
  int height = 64,
  int storedLevels = 7,
  bool mips = true,
  CompressionSupport support = _appleSilicon,
}) => chooseStandardKtx2Upload(
  colorModel: colorModel,
  hasAlpha: hasAlpha,
  width: width,
  height: height,
  storedLevels: storedLevels,
  mips: mips,
  support: support,
);

StandardKtx2Decoded _decode(
  String name, {
  required CompressionSupport support,
  bool mips = true,
}) {
  final decoded = decodeStandardKtx2ForUpload(
    (bytes: _fixture('$name.ktx2'), content: TextureContent.color),
    mips: mips,
    support: support,
  );
  expect(decoded.error, isNull);
  return decoded;
}

/// The start of the concatenated [golden] that covers [levels].
Uint8List _goldenPrefix(String golden, List<MipLevel> levels) {
  final bytes = _fixture(golden);
  final length = levels.fold<int>(0, (n, l) => n + l.pixels.length);
  return Uint8List.sublistView(bytes, 0, length);
}

Uint8List _concat(List<MipLevel> levels) {
  final builder = BytesBuilder(copy: false);
  for (final level in levels) {
    builder.add(level.pixels);
  }
  return builder.toBytes();
}

void main() {
  group('upload format choice', () {
    test('ETC1S prefers ETC2, then BC, then rgba8', () {
      expect(_choose(support: _appleSilicon), StandardKtx2Upload.etc2Rgb);
      expect(_choose(support: _mobile), StandardKtx2Upload.etc2Rgb);
      expect(_choose(support: _desktop), StandardKtx2Upload.bc1);
      expect(_choose(support: _none), StandardKtx2Upload.rgba8);
    });

    test('ETC1S with alpha takes the alpha formats', () {
      expect(
        _choose(hasAlpha: true, support: _mobile),
        StandardKtx2Upload.etc2Rgba,
      );
      expect(
        _choose(hasAlpha: true, support: _desktop),
        StandardKtx2Upload.bc3,
      );
      expect(_choose(hasAlpha: true, support: _none), StandardKtx2Upload.rgba8);
    });

    test('ETC1S that is not whole blocks decodes to rgba8', () {
      expect(_choose(width: 20, height: 14), StandardKtx2Upload.rgba8);
      expect(_choose(width: 64, height: 30), StandardKtx2Upload.rgba8);
    });

    test('a base-only file that needs a chain decodes to rgba8', () {
      expect(_choose(storedLevels: 1), StandardKtx2Upload.rgba8);
      expect(_choose(storedLevels: 1, mips: false), StandardKtx2Upload.etc2Rgb);
    });

    test('UASTC takes ASTC or rgba8', () {
      expect(
        _choose(colorModel: kDfModelUastc, support: _mobile),
        StandardKtx2Upload.astc4x4,
      );
      expect(
        _choose(colorModel: kDfModelUastc, support: _desktop),
        StandardKtx2Upload.rgba8,
      );
      // ASTC has its own footprint, so odd sizes still upload compressed.
      expect(
        _choose(colorModel: kDfModelUastc, width: 20, height: 14),
        StandardKtx2Upload.astc4x4,
      );
    });

    test('other color models decode to rgba8', () {
      expect(_choose(colorModel: 1), StandardKtx2Upload.rgba8);
    });
  });

  group('decode for upload', () {
    test('ETC1S on an ETC2 device uploads the ETC1 chain', () {
      final decoded = _decode('etc1s_srgb_mips_64', support: _mobile);
      expect(decoded.upload, StandardKtx2Upload.etc2Rgb);
      // The allocator's chain stops one level short of 1x1.
      expect([for (final l in decoded.levels) l.width], [64, 32, 16, 8, 4, 2]);
      expect(
        _concat(decoded.levels),
        _goldenPrefix('etc1s_srgb_mips_64.etc1', decoded.levels),
      );
    });

    test('ETC1S on a BC device uploads the BC1 chain', () {
      final decoded = _decode('etc1s_srgb_mips_64', support: _desktop);
      expect(decoded.upload, StandardKtx2Upload.bc1);
      expect(
        _concat(decoded.levels),
        _goldenPrefix('etc1s_srgb_mips_64.bc1', decoded.levels),
      );
    });

    test('ETC1S with alpha uploads ETC2 RGBA or BC3', () {
      final etc2 = _decode('etc1s_features_rgba_64', support: _mobile);
      expect(etc2.upload, StandardKtx2Upload.etc2Rgba);
      expect(
        _concat(etc2.levels),
        _goldenPrefix('etc1s_features_rgba_64.etc2_rgba', etc2.levels),
      );
      final bc = _decode('etc1s_features_rgba_64', support: _desktop);
      expect(bc.upload, StandardKtx2Upload.bc3);
      expect(
        _concat(bc.levels),
        _goldenPrefix('etc1s_features_rgba_64.bc3', bc.levels),
      );
    });

    test('without mip sampling only the base level is transcoded', () {
      final decoded = _decode(
        'etc1s_srgb_mips_64',
        support: _mobile,
        mips: false,
      );
      expect(decoded.levels.length, 1);
      expect(decoded.levels.single.pixels.length, 16 * 16 * 8);
    });

    test('a base-only ETC1S file gets a generated rgba8 chain', () {
      final decoded = _decode('etc1s_alpha_srgb_32', support: _mobile);
      expect(decoded.upload, StandardKtx2Upload.rgba8);
      expect(decoded.levels.length, greaterThan(1));
      expect(decoded.levels.first.pixels, _fixture('etc1s_alpha_srgb_32.rgba'));
    });

    test('ETC1S on a device without either family decodes to rgba8', () {
      final decoded = _decode('etc1s_srgb_mips_64', support: _none);
      expect(decoded.upload, StandardKtx2Upload.rgba8);
      expect(
        _concat(decoded.levels),
        _goldenPrefix('etc1s_srgb_mips_64.rgba', decoded.levels),
      );
    });

    test('UASTC on an ASTC device repacks to ASTC', () {
      final decoded = _decode('uastc_srgb_mips_zstd_64', support: _mobile);
      expect(decoded.upload, StandardKtx2Upload.astc4x4);
      expect(
        _concat(decoded.levels),
        _goldenPrefix('uastc_srgb_mips_zstd_64.astc', decoded.levels),
      );
    });

    test('a truncated file reports an error instead of throwing', () {
      final bytes = _fixture('etc1s_srgb_mips_64.ktx2');
      final decoded = decodeStandardKtx2ForUpload(
        (
          bytes: Uint8List.sublistView(bytes, 0, bytes.length - 100),
          content: TextureContent.color,
        ),
        mips: true,
        support: _mobile,
      );
      expect(decoded.error, isNotNull);
      expect(decoded.levels, isEmpty);
    });
  });
}
