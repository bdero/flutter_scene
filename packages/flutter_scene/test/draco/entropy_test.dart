// Covers the Draco byte/bit readers and rANS entropy decoders against
// mini encoders that mirror the reference encoder algorithms, so decode
// correctness is checked without fixture files.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/src/gltf/draco/decoder_buffer.dart';
import 'package:flutter_scene/src/importer/src/gltf/draco/rans.dart';
import 'package:flutter_scene/src/importer/src/gltf/draco/symbol_decoding.dart';
import 'package:flutter_test/flutter_test.dart';

// Test-side varint encoder (MSB continuation).
void writeVarint(BytesBuilder out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.addByte(0x80 | (v & 0x7F));
    v ~/= 128;
  }
  out.addByte(v);
}

// Test-side port of the reference binary rANS encoder (rabs_desc_write).
Uint8List encodeRAnsBits(List<bool> bits) {
  var zeroCount = 0;
  for (final bit in bits) {
    if (!bit) zeroCount++;
  }
  final total = max(1, bits.length);
  var zeroProb = ((zeroCount / total) * 256.0 + 0.5).floor();
  if (zeroProb >= 255) zeroProb = 255;
  if (zeroProb == 0) zeroProb = 1;

  final buf = <int>[];
  var state = 4096; // ANS_L_BASE
  for (final bit in bits.reversed) {
    final p = 256 - zeroProb;
    final ls = bit ? p : zeroProb;
    while (state >= (4096 ~/ 256) * 256 * ls) {
      buf.add(state % 256);
      state ~/= 256;
    }
    final quotient = state ~/ ls;
    final remainder = state % ls;
    state = quotient * 256 + remainder + (bit ? 0 : p);
  }
  // ans_write_end
  state -= 4096;
  if (state < (1 << 6)) {
    buf.add(state);
  } else if (state < (1 << 14)) {
    buf.add(state & 0xFF);
    buf.add((1 << 6) | (state >> 8));
  } else {
    buf.add(state & 0xFF);
    buf.add((state >> 8) & 0xFF);
    buf.add((2 << 6) | (state >> 16));
  }

  final out = BytesBuilder();
  out.addByte(zeroProb);
  writeVarint(out, buf.length);
  out.add(buf);
  return out.toBytes();
}

// Test-side port of the reference rANS symbol encoder for the raw scheme.
// probs must sum to the rANS precision for maxBitLength.
Uint8List encodeRawSymbols(
  List<int> symbols,
  List<int> probs,
  int maxBitLength,
) {
  final precisionBits = min(20, max(12, (3 * maxBitLength) ~/ 2));
  final precision = 1 << precisionBits;
  final lBase = precision * 4;
  assert(probs.reduce((a, b) => a + b) == precision);

  final cumProbs = List<int>.filled(probs.length, 0);
  var cum = 0;
  for (var i = 0; i < probs.length; i++) {
    cumProbs[i] = cum;
    cum += probs[i];
  }

  final out = BytesBuilder();
  out.addByte(maxBitLength);
  writeVarint(out, probs.length);
  // Probability table with the token scheme.
  for (var i = 0; i < probs.length; i++) {
    final prob = probs[i];
    if (prob == 0) {
      var offset = 0;
      while (offset < 63 &&
          i + offset + 1 < probs.length &&
          probs[i + offset + 1] == 0) {
        offset++;
      }
      out.addByte((offset << 2) | 3);
      i += offset;
    } else {
      var extraBytes = 0;
      if (prob >= (1 << 6)) extraBytes++;
      if (prob >= (1 << 14)) extraBytes++;
      out.addByte(((prob << 2) | (extraBytes & 3)) & 0xFF);
      for (var b = 0; b < extraBytes; b++) {
        out.addByte((prob >> (8 * (b + 1) - 2)) & 0xFF);
      }
    }
  }

  final buf = <int>[];
  var state = lBase;
  for (final symbol in symbols.reversed) {
    final p = probs[symbol];
    while (state >= (lBase ~/ precision) * 256 * p) {
      buf.add(state % 256);
      state ~/= 256;
    }
    state = (state ~/ p) * precision + state % p + cumProbs[symbol];
  }
  state -= lBase;
  if (state < (1 << 6)) {
    buf.add(state);
  } else if (state < (1 << 14)) {
    buf.add(state & 0xFF);
    buf.add((1 << 6) | (state >> 8));
  } else if (state < (1 << 22)) {
    buf.add(state & 0xFF);
    buf.add((state >> 8) & 0xFF);
    buf.add((2 << 6) | (state >> 16));
  } else {
    buf.add(state & 0xFF);
    buf.add((state >> 8) & 0xFF);
    buf.add((state >> 16) & 0xFF);
    buf.add((3 << 6) | (state >> 24));
  }
  writeVarint(out, buf.length);
  out.add(buf);
  return out.toBytes();
}

void main() {
  group('DecoderBuffer', () {
    test('reads little-endian scalars', () {
      final data = Uint8List.fromList([
        0x01, 0xFF, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12, //
        0x00, 0x00, 0x80, 0x3F, // 1.0f
      ]);
      final buffer = DecoderBuffer(data);
      expect(buffer.decodeUint8(), 1);
      expect(buffer.decodeInt8(), -1);
      expect(buffer.decodeUint16(), 0x1234);
      expect(buffer.decodeUint32(), 0x12345678);
      expect(buffer.decodeFloat32(), 1.0);
      expect(() => buffer.decodeUint8(), throwsFormatException);
    });

    test('decodes varints', () {
      for (final value in [0, 1, 127, 128, 300, 16383, 16384, 0xFFFFFFFF]) {
        final out = BytesBuilder();
        writeVarint(out, value);
        expect(DecoderBuffer(out.toBytes()).decodeVarint(), value);
      }
      // Truncated continuation byte.
      expect(
        () => DecoderBuffer(Uint8List.fromList([0x80])).decodeVarint(),
        throwsFormatException,
      );
    });

    test('reads LSB-first bit runs across byte boundaries', () {
      // Bits (LSB first): 1,0,1 then 5 bits of 0b10110 then 16 bits.
      final bitBuilder = BytesBuilder();
      var acc = 0;
      var accBits = 0;
      void push(int value, int nbits) {
        for (var i = 0; i < nbits; i++) {
          acc |= ((value >> i) & 1) << accBits;
          accBits++;
          if (accBits == 8) {
            bitBuilder.addByte(acc);
            acc = 0;
            accBits = 0;
          }
        }
      }

      push(5, 3);
      push(22, 5);
      push(0xBEEF, 16);
      push(3, 2);
      if (accBits > 0) bitBuilder.addByte(acc);

      final buffer = DecoderBuffer(bitBuilder.toBytes());
      buffer.startBitDecoding(sizePrefixed: false);
      expect(buffer.decodeLeastSignificantBits32(3), 5);
      expect(buffer.decodeLeastSignificantBits32(5), 22);
      expect(buffer.decodeLeastSignificantBits32(16), 0xBEEF);
      expect(buffer.decodeLeastSignificantBits32(2), 3);
      buffer.endBitDecoding();
    });

    test('zigzag decode matches reference behavior', () {
      expect(symbolToSignedInt(0), 0);
      expect(symbolToSignedInt(1), -1);
      expect(symbolToSignedInt(2), 1);
      expect(symbolToSignedInt(3), -2);
      expect(symbolToSignedInt(0xFFFFFFFE), 0x7FFFFFFF);
    });

    test('toInt32 wraps like C++ int32 arithmetic', () {
      expect(toInt32(0x7FFFFFFF), 0x7FFFFFFF);
      expect(toInt32(0x80000000), -0x80000000);
      expect(toInt32(0x7FFFFFFF + 1), -0x80000000);
      expect(toInt32(-0x80000000 - 1), 0x7FFFFFFF);
    });
  });

  group('RAnsBitDecoder', () {
    test('decodes bit streams from the reference encoding', () {
      final random = Random(42);
      for (final density in [0.05, 0.5, 0.95]) {
        final bits = List<bool>.generate(
          997,
          (_) => random.nextDouble() < density,
        );
        final decoder = RAnsBitDecoder();
        decoder.startDecoding(DecoderBuffer(encodeRAnsBits(bits)));
        for (var i = 0; i < bits.length; i++) {
          expect(decoder.decodeNextBit(), bits[i], reason: 'bit $i');
        }
      }
    });

    test('rejects an empty stream', () {
      final data = Uint8List.fromList([128, 0]);
      expect(
        () => RAnsBitDecoder().startDecoding(DecoderBuffer(data)),
        throwsFormatException,
      );
    });
  });

  group('raw symbol decoding', () {
    test('round trips against the reference rANS encoding', () {
      const maxBitLength = 4;
      final precision = 1 << 12;
      // Uneven distribution over 5 symbols.
      final probs = [
        precision ~/ 2,
        precision ~/ 4,
        precision ~/ 8,
        precision ~/ 16,
        precision ~/ 16,
      ];
      final random = Random(7);
      final symbols = List<int>.generate(2000, (_) => random.nextInt(5));
      final payload = BytesBuilder();
      payload.addByte(1); // SYMBOL_CODING_RAW
      payload.add(encodeRawSymbols(symbols, probs, maxBitLength));

      final out = Uint32List(symbols.length);
      final buffer = DecoderBuffer(
        payload.toBytes(),
        dracoBitstreamVersion(2, 2),
      );
      decodeSymbols(symbols.length, 1, buffer, out);
      expect(out, symbols);
    });

    test('handles zero-probability runs in the table', () {
      const maxBitLength = 10;
      final precision = 1 << 15;
      final probs = List<int>.filled(70, 0);
      probs[0] = precision ~/ 2;
      probs[69] = precision - probs[0];
      final symbols = [0, 69, 0, 0, 69, 0, 69, 69, 0, 0];
      final payload = BytesBuilder();
      payload.addByte(1);
      payload.add(encodeRawSymbols(symbols, probs, maxBitLength));

      final out = Uint32List(symbols.length);
      final buffer = DecoderBuffer(
        payload.toBytes(),
        dracoBitstreamVersion(2, 2),
      );
      decodeSymbols(symbols.length, 1, buffer, out);
      expect(out, symbols);
    });

    test('rejects invalid probability tables', () {
      const maxBitLength = 4;
      final precision = 1 << 12;
      // Sums to more than the precision.
      final probs = [precision, 4];
      final payload = BytesBuilder();
      payload.addByte(1);
      payload.add(encodeRawSymbols([0, 1], [precision - 4, 4], maxBitLength));
      final bytes = payload.toBytes();
      // Corrupt the table by bumping a probability byte.
      bytes[3] = 0xFF;
      expect(probs.length, 2);
      expect(
        () => decodeSymbols(
          2,
          1,
          DecoderBuffer(bytes, dracoBitstreamVersion(2, 2)),
          Uint32List(2),
        ),
        throwsFormatException,
      );
    });
  });

  group('tagged symbol decoding', () {
    test('round trips tags plus raw bits', () {
      // Tag stream coded with RAnsSymbolDecoder(5) (precision 12 bits), one
      // tag per 3-component value giving the component bit length.
      final precision = 1 << 12;
      final random = Random(3);
      const numComponents = 3;
      const numValueTriples = 500;
      final tags = <int>[];
      final values = <int>[];
      for (var i = 0; i < numValueTriples; i++) {
        final bitLength = 1 + random.nextInt(10);
        tags.add(bitLength);
        for (var c = 0; c < numComponents; c++) {
          values.add(random.nextInt(1 << bitLength));
        }
      }
      final tagProbs = List<int>.filled(11, 0);
      for (final t in tags) {
        tagProbs[t] += 1;
      }
      // Normalize to the precision, keeping used tags nonzero.
      var sum = 0;
      for (var i = 0; i < tagProbs.length; i++) {
        if (tagProbs[i] > 0) {
          tagProbs[i] = max(1, (tagProbs[i] * precision) ~/ tags.length);
        }
        sum += tagProbs[i];
      }
      // Pin the remainder on the first used tag.
      tagProbs[tags[0]] += precision - sum;

      final tagPayload = encodeRawSymbols(tags, tagProbs, 4);
      final out = BytesBuilder();
      out.addByte(0); // SYMBOL_CODING_TAGGED
      // The tagged scheme has no leading max-bit-length byte; strip the one
      // the raw encoder helper emits.
      out.add(tagPayload.sublist(1));
      // Append the value bits, LSB first.
      var acc = 0;
      var accBits = 0;
      var vi = 0;
      for (var i = 0; i < numValueTriples; i++) {
        final bitLength = tags[i];
        for (var c = 0; c < numComponents; c++) {
          final v = values[vi++];
          for (var b = 0; b < bitLength; b++) {
            acc |= ((v >> b) & 1) << accBits;
            accBits++;
            if (accBits == 8) {
              out.addByte(acc);
              acc = 0;
              accBits = 0;
            }
          }
        }
      }
      if (accBits > 0) out.addByte(acc);

      final decoded = Uint32List(values.length);
      final buffer = DecoderBuffer(out.toBytes(), dracoBitstreamVersion(2, 2));
      decodeSymbols(values.length, numComponents, buffer, decoded);
      expect(decoded, values);
    });
  });
}
