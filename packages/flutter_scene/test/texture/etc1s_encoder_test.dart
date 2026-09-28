// Checks the ETC1S encoder. The .rgba goldens for its fixtures are basisu's
// decodes of them (tool/etc1s_goldens.mjs).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/basis_ktx2.dart';
import 'package:flutter_scene/src/texture/basisu/encode/bit_writer.dart';
import 'package:flutter_scene/src/texture/basisu/encode/codebook_order.dart';
import 'package:flutter_scene/src/texture/basisu/encode/etc1s_encoder.dart';
import 'package:flutter_scene/src/texture/basisu/encode/vector_quantizer.dart';
import 'package:flutter_scene/src/texture/basisu/etc1s.dart';
import 'package:flutter_scene/src/texture/ktx2/dfd.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/encode_etc1s_fixtures.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/ktx2/$name').readAsBytesSync();

/// A committed source image's RGBA8 pixels and size.
({Uint8List rgba, int width, int height}) _source(String name) {
  final image = img
      .decodePng(_fixture(name))!
      .convert(numChannels: 4, format: img.Format.uint8);
  return (
    rgba: image.getBytes(order: img.ChannelOrder.rgba),
    width: image.width,
    height: image.height,
  );
}

Uint8List _image(int w, int h, List<int> Function(int x, int y) pixel) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setRange((y * w + x) * 4, (y * w + x) * 4 + 4, pixel(x, y));
    }
  }
  return out;
}

/// PSNR of Rec. 709 luma, which ETC1S keeps best.
double _lumaPsnr(Uint8List a, Uint8List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i += 4) {
    final d =
        0.2126 * (a[i] - b[i]) +
        0.7152 * (a[i + 1] - b[i + 1]) +
        0.0722 * (a[i + 2] - b[i + 2]);
    sum += d * d;
  }
  return 10 * math.log(65025 / (sum / (a.length ~/ 4))) / math.ln10;
}

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

Uint8List _concat(Iterable<Uint8List> parts) {
  final builder = BytesBuilder(copy: false);
  parts.forEach(builder.add);
  return builder.toBytes();
}

void main() {
  group('reference compatibility', () {
    for (final (source, name, options) in etc1sEncoderFixtures) {
      test('$name: the encoder writes the committed bytes', () {
        final (:rgba, :width, :height) = _source(source);
        final bytes = encodeEtc1sKtx2(rgba, width, height, options: options);
        expect(bytes, _fixture('$name.ktx2'));
      });

      test('$name: basisu decodes it exactly as flutter_scene does', () {
        final image = decodeStandardKtx2(readKtx2(_fixture('$name.ktx2')));
        expect(
          _concat([for (final level in image.levels) level.pixels]),
          _fixture('$name.rgba'),
        );
      });
    }
  });

  group('encoded files', () {
    test('an opaque color image is sRGB ETC1S with one slice per level', () {
      final (:rgba, :width, :height) = _source('etc1s_source_shapes_96x80.png');
      final texture = readKtx2(encodeEtc1sKtx2(rgba, width, height));
      expect(texture.vkFormat, 0);
      expect(texture.supercompression, Ktx2Supercompression.basisLz);
      expect(texture.pixelWidth, 96);
      expect(texture.pixelHeight, 80);
      // Every level down to 1x1, as the standard tools write.
      expect(texture.levels, hasLength(7));
      final format = readDataFormat(texture);
      expect(format.colorModel, kDfModelEtc1s);
      expect(format.isSrgb, isTrue);
      expect(format.hasAlpha, isFalse);
      expect(texture.dataFormatDescriptor, hasLength(44));
      for (final level in texture.levels) {
        expect(level.uncompressedByteLength, 0);
      }
    });

    test('an image with alpha gets an alpha slice and sample', () {
      final (:rgba, :width, :height) = _source('etc1s_features_rgba_64.png');
      final texture = readKtx2(encodeEtc1sKtx2(rgba, width, height));
      expect(readDataFormat(texture).hasAlpha, isTrue);
      expect(texture.dataFormatDescriptor, hasLength(60));
      final decoded = decodeStandardKtx2(texture).levels.first.pixels;
      expect(_psnr(decoded, rgba, [3]), greaterThan(40));
    });

    test('data and normal maps are tagged linear', () {
      final rgba = _image(8, 8, (x, y) => [x * 32, y * 32, 128, 255]);
      for (final content in [TextureContent.data, TextureContent.normal]) {
        final texture = readKtx2(
          encodeEtc1sKtx2(
            rgba,
            8,
            8,
            options: Etc1sEncodeOptions(content: content),
          ),
        );
        expect(readDataFormat(texture).isSrgb, isFalse, reason: '$content');
      }
    });

    test('every size decodes to its own dimensions, every level', () {
      final random = math.Random(3);
      for (final (w, h) in [
        (1, 1),
        (2, 3),
        (3, 2),
        (4, 4),
        (5, 7),
        (8, 4),
        (17, 9),
        (33, 1),
      ]) {
        for (final alpha in [false, true]) {
          for (final mipmaps in [false, true]) {
            final rgba = _image(
              w,
              h,
              (x, y) => [
                random.nextInt(256),
                random.nextInt(256),
                random.nextInt(256),
                alpha ? random.nextInt(256) : 255,
              ],
            );
            final label = '${w}x$h alpha=$alpha mips=$mipmaps';
            final image = decodeStandardKtx2(
              readKtx2(
                encodeEtc1sKtx2(
                  rgba,
                  w,
                  h,
                  options: Etc1sEncodeOptions(mipmaps: mipmaps),
                ),
              ),
            );
            expect(image.hasAlpha, alpha, reason: label);
            final expected = mipmaps
                ? generateMipChain(rgba, w, h, TextureContent.color)
                : [MipLevel(w, h, rgba)];
            expect(image.levels, hasLength(expected.length), reason: label);
            for (var l = 0; l < expected.length; l++) {
              expect(image.levels[l].width, expected[l].width, reason: label);
              expect(image.levels[l].height, expected[l].height, reason: label);
            }
          }
        }
      }
    });

    test('encoding is deterministic', () {
      final (:rgba, :width, :height) = _source('etc1s_features_rgba_64.png');
      final first = encodeEtc1sKtx2(rgba, width, height);
      final second = encodeEtc1sKtx2(rgba, width, height);
      expect(second, first);
    });

    test('flat colors come back within a few steps', () {
      const colors = [
        [0, 0, 0],
        [255, 255, 255],
        [70, 160, 210],
        [250, 3, 128],
        [128, 128, 128],
      ];
      for (final c in colors) {
        final rgba = _image(16, 16, (x, y) => [...c, 255]);
        final decoded = decodeStandardKtx2(
          readKtx2(encodeEtc1sKtx2(rgba, 16, 16)),
        ).levels.first.pixels;
        for (var i = 0; i < decoded.length; i += 4) {
          for (var k = 0; k < 3; k++) {
            // The best ETC1S can do for these is 1 step off.
            expect((decoded[i + k] - c[k]).abs(), lessThanOrEqualTo(1));
          }
        }
      }
    });

    test('higher quality is larger and closer to the source', () {
      final (:rgba, :width, :height) = _source('etc1s_source_shapes_96x80.png');
      (int, double) encode(int quality) {
        final bytes = encodeEtc1sKtx2(
          rgba,
          width,
          height,
          options: Etc1sEncodeOptions(quality: quality, mipmaps: false),
        );
        final decoded = decodeStandardKtx2(readKtx2(bytes)).levels.first;
        return (bytes.length, _lumaPsnr(decoded.pixels, rgba));
      }

      final (smallSize, smallPsnr) = encode(1);
      final (midSize, midPsnr) = encode(128);
      final (bestSize, bestPsnr) = encode(255);
      expect(smallSize, lessThan(midSize));
      expect(midSize, lessThan(bestSize));
      expect(smallPsnr, lessThan(midPsnr));
      expect(midPsnr, lessThan(bestPsnr));
      // Hue changes inside blocks cap RGB PSNR near 25 dB (basisu's too);
      // basisu's luma PSNR here is 38.8 dB.
      expect(midPsnr, greaterThan(36));
    });

    test('rejects impossible input', () {
      expect(() => encodeEtc1sKtx2(Uint8List(0), 0, 4), throwsArgumentError);
      expect(() => encodeEtc1sKtx2(Uint8List(16), 4, 4), throwsArgumentError);
    });
  });

  group('bitstream', () {
    List<int> randomFrequencies(math.Random random, int count) => [
      for (var i = 0; i < count; i++)
        random.nextInt(4) == 0 ? 0 : random.nextInt(1000),
    ];

    test('Huffman codes are complete and at most 16 bits long', () {
      final random = math.Random(5);
      final cases = <List<int>>[
        // Fibonacci frequencies force the length limit.
        [for (var i = 0, a = 1, b = 1; i < 40; i++, b = a + (a = b)) a],
        [0, 0, 7, 0],
        [1],
        [0, 0, 0],
        for (var i = 0; i < 20; i++) randomFrequencies(random, 2 + i * 13),
      ];
      for (final frequencies in cases) {
        final code = HuffmanCode.fromFrequencies(frequencies);
        final used = [
          for (var s = 0; s < frequencies.length; s++)
            if (code.sizes[s] > 0) s,
        ];
        final anyUsed = frequencies.any((f) => f > 0);
        for (var s = 0; s < frequencies.length; s++) {
          // Used symbols get codes; with none used, symbol 0 gets one.
          expect(
            code.sizes[s] > 0,
            frequencies[s] > 0 || (!anyUsed && s == 0),
            reason: 'symbol $s of $frequencies',
          );
          expect(code.sizes[s], lessThanOrEqualTo(maxHuffmanCodeSize));
        }
        if (used.length > 1) {
          // Kraft equality: the code wastes no bit patterns.
          var kraft = 0;
          for (final s in used) {
            kraft += 1 << (maxHuffmanCodeSize - code.sizes[s]);
          }
          expect(kraft, 1 << maxHuffmanCodeSize);
        }
      }
    });

    test('Huffman tables round trip through the decoder', () {
      final random = math.Random(9);
      final cases = <List<int>>[
        [5],
        [0, 0, 0, 9],
        // Zero runs longer than one run code, then long repeats.
        [...List.filled(300, 0), 4, ...List.filled(300, 1)],
        [for (var i = 0; i < 16384; i++) i % 97 == 0 ? i % 13 + 1 : 0],
        [for (var i = 0, a = 1, b = 1; i < 30; i++, b = a + (a = b)) a],
        for (var i = 0; i < 12; i++) randomFrequencies(random, 3 + i * 37),
      ];
      for (final frequencies in cases) {
        final code = HuffmanCode.fromFrequencies(frequencies);
        final symbols = [
          for (var s = 0; s < frequencies.length; s++)
            if (code.sizes[s] > 0) s,
        ];
        final message = [
          for (var i = 0; i < 200; i++) symbols[random.nextInt(symbols.length)],
        ];
        final writer = BitWriter();
        writeHuffmanTable(writer, code);
        for (final s in message) {
          writer.writeCode(s, code);
        }
        expect(
          readHuffmanCodedSymbols(writer.takeBytes(), message.length),
          message,
        );
      }
    });

    test('variable-length values round trip through the decoder', () {
      const values = [0, 1, 15, 16, 17, 255, 256, 4095, 1 << 20];
      for (final chunk in [4, 7]) {
        final writer = BitWriter();
        for (final v in values) {
          writer.writeVlc(v, chunk);
        }
        expect(readVlcValues(writer.takeBytes(), values.length, chunk), values);
      }
    });
  });

  group('codebook order', () {
    test('selectors form the greedy nearest chain', () {
      final random = math.Random(11);
      final rows = Uint32List.fromList([
        for (var i = 0; i < 300; i++) random.nextInt(1 << 32),
        // Near duplicates, so the bucketed search has close neighbors.
        for (var i = 0; i < 300; i++) 0xA5A5A5A5 ^ (1 << random.nextInt(32)),
      ]);
      final order = orderSelectors(rows);
      final chain = List<int>.filled(rows.length, -1);
      for (var i = 0; i < rows.length; i++) {
        chain[order[i]] = i;
      }
      expect(chain.toSet(), hasLength(rows.length));
      expect(chain.first, 0);
      int distance(int a, int b) {
        var v = rows[a] ^ rows[b];
        var n = 0;
        while (v != 0) {
          n += v & 1;
          v >>= 1;
        }
        return n;
      }

      // Each step takes the closest entry left (lowest index on ties).
      final left = {for (var i = 1; i < rows.length; i++) i};
      for (var p = 1; p < rows.length; p++) {
        final from = chain[p - 1];
        var best = -1;
        for (final c in left) {
          if (best < 0 ||
              distance(from, c) < distance(from, best) ||
              (distance(from, c) == distance(from, best) && c < best)) {
            best = c;
          }
        }
        expect(chain[p], best, reason: 'position $p');
        left.remove(best);
      }
    });

    test('endpoints that neighbor each other end up adjacent', () {
      // Two entries that always sit side by side, and noise around them.
      final sequence = Int32List.fromList([
        for (var i = 0; i < 400; i++) ...[7, 3, i % 5 + 10],
      ]);
      final order = orderEndpoints(20, [sequence]);
      expect(order.toSet(), hasLength(20));
      expect((order[7] - order[3]).abs(), 1);
    });
  });

  group('vector quantizer', () {
    test('splits well separated groups apart', () {
      final vectors = Float64List.fromList([
        for (var i = 0; i < 30; i++) ...[0.0, 0.0],
        for (var i = 0; i < 30; i++) ...[1.0, 1.0],
        for (var i = 0; i < 30; i++) ...[0.0, 1.0],
      ]);
      final q = quantize(
        vectors,
        Float64List(90)..fillRange(0, 90, 1),
        90,
        2,
        3,
      );
      expect(q.clusterCount, 3);
      for (var group = 0; group < 3; group++) {
        final cluster = q.assignments[group * 30];
        for (var i = 0; i < 30; i++) {
          expect(q.assignments[group * 30 + i], cluster);
        }
      }
      expect(q.assignments.toSet(), hasLength(3));
    });

    test('never makes more clusters than distinct vectors', () {
      final vectors = Float64List.fromList([
        for (var i = 0; i < 50; i++) ...[0.5, 0.25],
      ]);
      final q = quantize(
        vectors,
        Float64List(50)..fillRange(0, 50, 1),
        50,
        2,
        8,
      );
      expect(q.clusterCount, 1);
      expect(q.relatives(0, 16), [0]);
    });
  });
}
