// Checks ETC1S transcoding against goldens from the reference transcoder
// (basisu v2.50.0, written by tool/etc1s_goldens.mjs).
// etc1s_features_rgba_64 was encoded by basisu (`-ktx2 -mipmap -q 128`) from
// a synthetic image aimed at each conversion branch.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/basis_ktx2.dart';
import 'package:flutter_scene/src/texture/basisu/etc1s_targets.dart';
import 'package:flutter_scene/src/texture/block/transcode_bc1.dart';
import 'package:flutter_scene/src/texture/block/transcode_bc3.dart';
import 'package:flutter_scene/src/texture/block/transcode_etc2.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/ktx2/$name').readAsBytesSync();

Uint8List _concat(Iterable<Uint8List> parts) {
  final builder = BytesBuilder(copy: false);
  parts.forEach(builder.add);
  return builder.toBytes();
}

const _fixtures = [
  'etc1s_srgb_mips_64',
  'etc1s_alpha_srgb_32',
  'etc1s_linear_20x14',
  'alpha_simple_basis',
  'etc1s_features_rgba_64',
  // Written by flutter_scene's own encoder (see etc1s_encoder_test.dart).
  'etc1s_encoded_features_q128',
  'etc1s_encoded_odd_q64',
  'etc1s_encoded_shapes_q255',
];

const _goldenExtension = {
  Etc1sTarget.etc1: 'etc1',
  Etc1sTarget.etc2Rgba: 'etc2_rgba',
  Etc1sTarget.bc1: 'bc1',
  Etc1sTarget.bc3: 'bc3',
};

List<BlockLevel> _transcode(String name, Etc1sTarget target) =>
    transcodeStandardKtx2Etc1s(readKtx2(_fixture('$name.ktx2')), target, 99)!;

/// The byte offset and length of each level in a concatenated golden.
Iterable<(int, int)> _levelSpans(List<BlockLevel> levels) sync* {
  var offset = 0;
  for (final level in levels) {
    yield (offset, level.blocks.length);
    offset += level.blocks.length;
  }
}

/// PSNR over the channels in [channels] of two same-size RGBA8 images.
double _psnr(Uint8List a, Uint8List b, List<int> channels) {
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (final c in channels) {
      final d = a[i + c] - b[i + c];
      sum += d * d;
      count++;
    }
  }
  final mse = sum / count;
  return mse == 0 ? double.infinity : 10 * math.log(65025 / mse) / math.ln10;
}

void main() {
  group('ETC1S transcode matches the reference transcoder', () {
    for (final name in _fixtures) {
      for (final target in Etc1sTarget.values) {
        test('$name to ${target.name}', () {
          final levels = _transcode(name, target);
          final golden = _fixture('$name.${_goldenExtension[target]}');
          final actual = _concat([for (final l in levels) l.blocks]);
          expect(actual.length, golden.length);
          // Report the first differing level and block before the bulk
          // compare, so a failure says where to look.
          for (final (i, (offset, length)) in _levelSpans(levels).indexed) {
            for (var b = 0; b < length; b += target.bytesPerBlock) {
              final got = actual.sublist(
                offset + b,
                offset + b + target.bytesPerBlock,
              );
              final want = golden.sublist(
                offset + b,
                offset + b + target.bytesPerBlock,
              );
              expect(
                got,
                want,
                reason: 'level $i block ${b ~/ target.bytesPerBlock}',
              );
            }
          }
          expect(actual, golden);
        });
      }
    }
  });

  group('ETC1S to ETC1', () {
    test('decodes to exactly the ETC1S pixels, every level', () {
      for (final name in _fixtures) {
        final texture = readKtx2(_fixture('$name.ktx2'));
        final pixels = decodeStandardKtx2(texture).levels;
        final blocks = transcodeStandardKtx2Etc1s(
          texture,
          Etc1sTarget.etc1,
          99,
        )!;
        expect(blocks.length, pixels.length, reason: name);
        for (var level = 0; level < pixels.length; level++) {
          final expected = pixels[level].pixels;
          final decoded = decodeEtc2RgbToRgba8(
            blocks[level].blocks,
            blocks[level].width,
            blocks[level].height,
          );
          for (var i = 0; i < expected.length; i += 4) {
            expect(
              decoded.sublist(i, i + 3),
              expected.sublist(i, i + 3),
              reason: '$name level $level texel ${i ~/ 4}',
            );
          }
        }
      }
    });

    test('is 8 bytes per block, padded to whole blocks', () {
      final levels = _transcode('etc1s_linear_20x14', Etc1sTarget.etc1);
      expect(levels.single.width, 20);
      expect(levels.single.height, 14);
      expect(levels.single.blocks.length, 5 * 4 * 8);
    });
  });

  group('ETC1S to ETC2 RGBA', () {
    test('keeps the color exact and the alpha close', () {
      for (final name in ['etc1s_alpha_srgb_32', 'etc1s_features_rgba_64']) {
        final texture = readKtx2(_fixture('$name.ktx2'));
        final pixels = decodeStandardKtx2(texture).levels.first;
        final block = transcodeStandardKtx2Etc1s(
          texture,
          Etc1sTarget.etc2Rgba,
          1,
        )!.single;
        final decoded = decodeEtc2RgbaToRgba8(
          block.blocks,
          block.width,
          block.height,
        );
        expect(_psnr(decoded, pixels.pixels, [0, 1, 2]), double.infinity);
        expect(_psnr(decoded, pixels.pixels, [3]), greaterThan(40));
      }
    });

    test('gives an opaque file opaque alpha', () {
      final block = _transcode(
        'etc1s_srgb_mips_64',
        Etc1sTarget.etc2Rgba,
      ).first;
      final decoded = decodeEtc2RgbaToRgba8(
        block.blocks,
        block.width,
        block.height,
      );
      for (var i = 3; i < decoded.length; i += 4) {
        expect(decoded[i], 255);
      }
    });
  });

  group('ETC1S to BC1 and BC3', () {
    test('BC1 stays close to the ETC1S pixels', () {
      for (final name in _fixtures) {
        final texture = readKtx2(_fixture('$name.ktx2'));
        final pixels = decodeStandardKtx2(texture).levels.first;
        final block = transcodeStandardKtx2Etc1s(
          texture,
          Etc1sTarget.bc1,
          1,
        )!.single;
        final decoded = decodeBc1ToRgba8(
          block.blocks,
          block.width,
          block.height,
        );
        // BC1 re-fits each block's colors, so it loses a little against
        // the ETC1S pixels: 33.9 to 49.9 dB over these fixtures, the same
        // bytes the reference transcoder produces.
        expect(
          _psnr(decoded, pixels.pixels, [0, 1, 2]),
          greaterThan(32),
          reason: name,
        );
      }
    });

    test('BC3 color blocks never use three-color mode', () {
      for (final name in _fixtures) {
        for (final level in _transcode(name, Etc1sTarget.bc3)) {
          for (var o = 8; o < level.blocks.length; o += 16) {
            final color0 = level.blocks[o] | (level.blocks[o + 1] << 8);
            final color1 = level.blocks[o + 2] | (level.blocks[o + 3] << 8);
            expect(color0, greaterThan(color1), reason: '$name block $o');
          }
        }
      }
    });

    test('BC3 keeps the alpha close', () {
      final texture = readKtx2(_fixture('etc1s_features_rgba_64.ktx2'));
      final pixels = decodeStandardKtx2(texture).levels.first;
      final block = transcodeStandardKtx2Etc1s(
        texture,
        Etc1sTarget.bc3,
        1,
      )!.single;
      final decoded = decodeBc3ToRgba8(block.blocks, block.width, block.height);
      expect(_psnr(decoded, pixels.pixels, [3]), greaterThan(40));
    });
  });

  test('non-ETC1S files are not transcoded', () {
    final texture = readKtx2(_fixture('uastc_linear_20x14.ktx2'));
    expect(transcodeStandardKtx2Etc1s(texture, Etc1sTarget.etc1, 1), isNull);
  });

  test('maxLevels caps the chain', () {
    final texture = readKtx2(_fixture('etc1s_srgb_mips_64.ktx2'));
    final levels = transcodeStandardKtx2Etc1s(texture, Etc1sTarget.bc1, 3)!;
    expect([for (final l in levels) l.width], [64, 32, 16]);
  });
}
