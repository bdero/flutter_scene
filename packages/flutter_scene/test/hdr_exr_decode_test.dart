import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/equirect_image.dart'
    show boxDownsampleEquirect;
import 'package:flutter_test/flutter_test.dart';

// The fixtures encode the same known linear RGB values (row-major, incl. HDR
// values above 1) as a hand-written uncompressed FLOAT OpenEXR and a flat RGBE
// Radiance HDR, so both decoders can be checked against the same numbers.
const List<List<List<double>>> _expected = [
  [
    [2.0, 0.5, 0.25],
    [0, 0, 0],
    [1, 1, 1],
    [0.5, 0.5, 0.5],
  ],
  [
    [0, 0, 0],
    [10, 0, 0],
    [0, 10, 0],
    [0, 0, 10],
  ],
];

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

List<double> _pixel(DecodedHdr d, int x, int y) {
  final i = (y * d.width + x) * 4;
  return [d.pixels[i], d.pixels[i + 1], d.pixels[i + 2], d.pixels[i + 3]];
}

void main() {
  group('format detection', () {
    test('detects HDR, EXR, and LDR by magic bytes', () {
      expect(
        detectEquirectImageFormat(_fixture('rgb_4x2.hdr')),
        EquirectImageFormat.radianceHdr,
      );
      expect(
        detectEquirectImageFormat(_fixture('rgb_4x2.exr')),
        EquirectImageFormat.openExr,
      );
      // A PNG signature.
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
      expect(detectEquirectImageFormat(png), EquirectImageFormat.ldr);
    });
  });

  group('decodeOpenExr', () {
    test('reads linear float RGBA at full range', () {
      final d = decodeOpenExr(_fixture('rgb_4x2.exr'));
      expect(d.width, 4);
      expect(d.height, 2);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 4; x++) {
          final p = _pixel(d, x, y);
          expect(p[0], closeTo(_expected[y][x][0], 1e-5));
          expect(p[1], closeTo(_expected[y][x][1], 1e-5));
          expect(p[2], closeTo(_expected[y][x][2], 1e-5));
          expect(p[3], 1.0, reason: 'alpha forced opaque');
        }
      }
    });
  });

  group('decodeRadianceHdr', () {
    test('reads linear float RGBA within RGBE quantization', () {
      final d = decodeRadianceHdr(_fixture('rgb_4x2.hdr'));
      expect(d.width, 4);
      expect(d.height, 2);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 4; x++) {
          final p = _pixel(d, x, y);
          final e = _expected[y][x];
          // RGBE has an 8-bit mantissa, so allow a small relative slack.
          final tol = 0.02 * (e.reduce((a, b) => a > b ? a : b)) + 1e-4;
          expect(p[0], closeTo(e[0], tol));
          expect(p[1], closeTo(e[1], tol));
          expect(p[2], closeTo(e[2], tol));
        }
      }
    });
  });

  group('decodeOpenExr guards', () {
    test('rejects 32-bit float channels with a clear message', () {
      expect(
        () => decodeOpenExr(_fixture('rgb_2x1_float.exr')),
        throwsA(
          isA<ExrFormatException>().having(
            (e) => e.message,
            'message',
            contains('half'),
          ),
        ),
      );
    });
  });

  group('decodeEquirectHdrImage', () {
    test('decodes HDR and EXR, returns null for LDR', () {
      expect(decodeEquirectHdrImage(_fixture('rgb_4x2.hdr')), isNotNull);
      expect(decodeEquirectHdrImage(_fixture('rgb_4x2.exr')), isNotNull);
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
      expect(decodeEquirectHdrImage(png), isNull);
    });
  });

  group('boxDownsampleEquirect', () {
    test('averages 2x2 blocks in linear space', () {
      final d = decodeOpenExr(_fixture('rgb_4x2.exr'));
      final half = boxDownsampleEquirect(d, 2);
      expect(half.width, 2);
      expect(half.height, 1);
      // Top-left 2x2 block averages (2,.5,.25),(0,0,0),(0,0,0),(10,0,0).
      final p = _pixel(half, 0, 0);
      expect(p[0], closeTo((2.0 + 0 + 0 + 10.0) / 4, 1e-5));
      expect(p[1], closeTo((0.5 + 0 + 0 + 0) / 4, 1e-5));
      expect(p[2], closeTo((0.25 + 0 + 0 + 0) / 4, 1e-5));
    });

    test('returns the source unchanged when already narrow enough', () {
      final d = decodeOpenExr(_fixture('rgb_4x2.exr'));
      expect(identical(boxDownsampleEquirect(d, 4), d), isTrue);
    });
  });
}
