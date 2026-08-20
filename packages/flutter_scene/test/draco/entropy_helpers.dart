// Test-side mini encoders mirroring the reference encoder algorithms
// (varint, binary rANS, and the raw rANS symbol scheme), shared by the
// entropy and connectivity tests.

import 'dart:math';
import 'dart:typed_data';

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
