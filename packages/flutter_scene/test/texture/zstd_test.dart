// Verifies the pure-Dart zstd decoder against streams produced by the
// reference Zstandard CLI (v1.5.5). The fixture .zst files under
// test/fixtures/zstd/ were compressed from inputs regenerated here, at the
// level the file name carries (l3, l19; `nocheck` is level 3 with --no-check).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/supercompress/zstd.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/zstd/$name').readAsBytesSync();

/// Deterministic pseudo-random bytes (incompressible, forces raw blocks).
Uint8List _lcgBytes(int length, int seed) {
  final out = Uint8List(length);
  var state = seed;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    out[i] = (state >> 16) & 0xFF;
  }
  return out;
}

/// Repeating text (Huffman literals plus matched sequences).
Uint8List _textLike(int length) {
  const words =
      'the quick brown fox jumps over a lazy dog while zstd '
      'streams literals sequences offsets and huffman tables repeatedly ';
  final unit = words.codeUnits;
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = unit[i % unit.length];
  }
  return out;
}

/// Long runs and near-repeats (RLE blocks, repeat offsets).
Uint8List _blocky(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    final phase = (i ~/ 977) % 4;
    out[i] = switch (phase) {
      0 => 0,
      1 => i % 251,
      2 => 0xAB,
      _ => (i % 17) * 15,
    };
  }
  return out;
}

void _expectRoundTrip(String fixture, Uint8List original) {
  final decoded = zstdDecompress(_fixture(fixture), original.length);
  expect(decoded, original, reason: fixture);
}

void main() {
  group('zstd decode of reference CLI streams', () {
    test(
      'text, level 3',
      () => _expectRoundTrip('text_4k.l3.zst', _textLike(4096)),
    );
    test(
      'text, level 19',
      () => _expectRoundTrip('text_4k.l19.zst', _textLike(4096)),
    );
    test(
      'text, no checksum',
      () => _expectRoundTrip('text_4k.nocheck.zst', _textLike(4096)),
    );
    test(
      'multi-block text, level 3',
      () => _expectRoundTrip('text_300k.l3.zst', _textLike(300000)),
    );
    test(
      'multi-block text, level 19',
      () => _expectRoundTrip('text_300k.l19.zst', _textLike(300000)),
    );
    test(
      'runs, level 3',
      () => _expectRoundTrip('blocky_64k.l3.zst', _blocky(65536)),
    );
    test(
      'runs, level 19',
      () => _expectRoundTrip('blocky_64k.l19.zst', _blocky(65536)),
    );
    test(
      'incompressible (raw blocks)',
      () => _expectRoundTrip('random_2k.l3.zst', _lcgBytes(2048, 7)),
    );
    test(
      'single byte',
      () => _expectRoundTrip('tiny.l3.zst', Uint8List.fromList([42])),
    );
  });

  group('zstd malformed input', () {
    test('bad magic', () {
      final bytes = Uint8List.fromList(_fixture('text_4k.l3.zst'));
      bytes[0] ^= 0xFF;
      expect(() => zstdDecompress(bytes, 4096), throwsFormatException);
    });

    test('truncated stream', () {
      final bytes = _fixture('text_4k.l3.zst');
      final cut = Uint8List.sublistView(bytes, 0, bytes.length ~/ 2);
      expect(() => zstdDecompress(cut, 4096), throwsFormatException);
    });

    test('wrong declared size', () {
      expect(
        () => zstdDecompress(_fixture('text_4k.l3.zst'), 5000),
        throwsFormatException,
      );
    });

    test('empty input', () {
      expect(() => zstdDecompress(Uint8List(0), 16), throwsFormatException);
    });

    test('flipped bytes decode cleanly or throw FormatException', () {
      // Whatever byte is corrupted, the decoder must fail with a
      // FormatException (or produce output, when the flip lands in an ignored
      // field like the checksum), never a range error or a hang.
      final reference = _fixture('blocky_64k.l3.zst');
      for (var i = 0; i < reference.length; i++) {
        final bytes = Uint8List.fromList(reference);
        bytes[i] ^= 0xA5;
        try {
          zstdDecompress(bytes, 65536);
        } on FormatException {
          continue;
        }
      }
    });
  });
}
