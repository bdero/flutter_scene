import 'dart:typed_data';

import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int length, {int seed = 0}) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = (i * 31 + seed * 7 + 1) & 0xFF;
  }
  return out;
}

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);

void main() {
  group('KTX2 container', () {
    test('writes the identifier and header for a single-level texture', () {
      final texture = Ktx2Texture(
        vkFormat: 37, // VK_FORMAT_R8G8B8A8_UNORM
        pixelWidth: 4,
        pixelHeight: 4,
        levels: [Ktx2Level(data: _bytes(64))],
        levelAlignment: 4,
      );
      final out = writeKtx2(texture);

      expect(out.sublist(0, 12), ktx2Identifier);
      expect(_u32(out, 12), 37); // vkFormat
      expect(_u32(out, 16), 1); // typeSize
      expect(_u32(out, 20), 4); // pixelWidth
      expect(_u32(out, 24), 4); // pixelHeight
      expect(_u32(out, 40), 1); // levelCount
      expect(_u32(out, 44), 0); // supercompressionScheme = none
    });

    test('round-trips a single level', () {
      final payload = _bytes(64, seed: 3);
      final texture = Ktx2Texture(
        vkFormat: 37,
        pixelWidth: 4,
        pixelHeight: 4,
        levels: [Ktx2Level(data: payload)],
        levelAlignment: 4,
      );
      final decoded = readKtx2(writeKtx2(texture));

      expect(decoded.vkFormat, 37);
      expect(decoded.pixelWidth, 4);
      expect(decoded.pixelHeight, 4);
      expect(decoded.levels, hasLength(1));
      expect(decoded.levels.single.data, payload);
      expect(decoded.levels.single.uncompressedByteLength, 64);
      expect(decoded.supercompression, Ktx2Supercompression.none);
    });

    test('round-trips a mip chain, base level first', () {
      final mips = [
        Ktx2Level(data: _bytes(256, seed: 0)), // base
        Ktx2Level(data: _bytes(64, seed: 1)),
        Ktx2Level(data: _bytes(16, seed: 2)),
      ];
      final texture = Ktx2Texture(
        vkFormat: 0,
        pixelWidth: 8,
        pixelHeight: 8,
        levels: mips,
      );
      final decoded = readKtx2(writeKtx2(texture));

      expect(decoded.levels, hasLength(3));
      expect(decoded.levels[0].data, mips[0].data);
      expect(decoded.levels[1].data, mips[1].data);
      expect(decoded.levels[2].data, mips[2].data);
    });

    test('stores level data smallest-first with aligned offsets', () {
      final mips = [
        Ktx2Level(data: _bytes(100, seed: 0)), // base
        Ktx2Level(data: _bytes(30, seed: 1)),
      ];
      final texture = Ktx2Texture(
        vkFormat: 0,
        pixelWidth: 8,
        pixelHeight: 8,
        levels: mips,
        levelAlignment: 16,
      );
      final out = writeKtx2(texture);

      // Level index entries are base-first (index 0 = base).
      const levelIndexStart = 80;
      final baseOffset = _u32(out, levelIndexStart);
      final smallOffset = _u32(out, levelIndexStart + 24);

      // Both offsets honor the 16-byte alignment, and the smaller level is
      // stored at the lower offset.
      expect(baseOffset % 16, 0);
      expect(smallOffset % 16, 0);
      expect(smallOffset, lessThan(baseOffset));
      expect(_u32(out, levelIndexStart + 8), 100); // base byteLength
      expect(_u32(out, levelIndexStart + 24 + 8), 30); // small byteLength
    });

    test('round-trips key/value data in sorted key order', () {
      final texture = Ktx2Texture(
        vkFormat: 37,
        pixelWidth: 1,
        pixelHeight: 1,
        levels: [Ktx2Level(data: _bytes(4))],
        levelAlignment: 4,
        keyValues: {
          'KTXorientation': Uint8List.fromList('rd'.codeUnits),
          'KTXwriter': Uint8List.fromList('flutter_scene'.codeUnits),
        },
      );
      final decoded = readKtx2(writeKtx2(texture));

      expect(decoded.keyValues.keys, ['KTXorientation', 'KTXwriter']);
      expect(String.fromCharCodes(decoded.keyValues['KTXorientation']!), 'rd');
      expect(
        String.fromCharCodes(decoded.keyValues['KTXwriter']!),
        'flutter_scene',
      );
    });

    test('passes supercompressed payloads through opaquely', () {
      final stored = _bytes(40, seed: 9); // pretend-compressed bytes
      final texture = Ktx2Texture(
        vkFormat: 0,
        pixelWidth: 8,
        pixelHeight: 8,
        levels: [Ktx2Level(data: stored, uncompressedByteLength: 256)],
        supercompression: Ktx2Supercompression.zstandard,
        supercompressionGlobalData: _bytes(8, seed: 5),
      );
      final out = writeKtx2(texture);
      final decoded = readKtx2(out);

      expect(_u32(out, 44), Ktx2Supercompression.zstandard.value);
      expect(decoded.supercompression, Ktx2Supercompression.zstandard);
      expect(decoded.levels.single.data, stored);
      expect(decoded.levels.single.uncompressedByteLength, 256);
      expect(decoded.supercompressionGlobalData, _bytes(8, seed: 5));
    });

    test('rejects a bad identifier', () {
      final out = writeKtx2(
        Ktx2Texture(
          vkFormat: 37,
          pixelWidth: 1,
          pixelHeight: 1,
          levels: [Ktx2Level(data: _bytes(4))],
          levelAlignment: 4,
        ),
      );
      out[1] = 0x00; // corrupt the identifier
      expect(() => readKtx2(out), throwsA(isA<Ktx2FormatException>()));
    });

    test('rejects truncated input', () {
      expect(
        () => readKtx2(Uint8List(20)),
        throwsA(isA<Ktx2FormatException>()),
      );
    });
  });
}
