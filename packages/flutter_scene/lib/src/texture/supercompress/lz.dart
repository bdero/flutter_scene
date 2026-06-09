// A small pure-Dart LZ77 codec used to supercompress KTX2 block payloads.
//
// We compress and decompress our own files, so this is a private byte format
// rather than zstd/zlib (which would need a native library or a much larger
// pure-Dart decoder). The compressor is build-time only; the decompressor is
// the hot path and runs on every backend including web, so it avoids 64-bit
// math and any platform library.
//
// Stream format: a sequence of [literalLength][literal bytes] runs, each
// optionally followed by a back-reference [matchLength - kMinMatch][distance].
// All lengths and the distance are unsigned LEB128 varints. Decoding stops when
// the output reaches its known uncompressed size, so no end marker is stored.

import 'dart:typed_data';

const int _minMatch = 4;
const int _maxChain = 32; // candidates examined per position (ratio vs speed)
const int _hashBits = 16;
const int _hashSize = 1 << _hashBits;

/// Compresses [input] with LZ77. Build-time only.
Uint8List lzCompress(Uint8List input) {
  final n = input.length;
  final out = BytesBuilder(copy: false);
  if (n == 0) return out.toBytes();

  final head = Int32List(_hashSize)..fillRange(0, _hashSize, -1);
  final prev = Int32List(n);

  var i = 0;
  var literalStart = 0;
  while (i < n) {
    var matchLen = 0;
    var matchDist = 0;
    if (i + _minMatch <= n) {
      final h = _hash(input, i);
      var candidate = head[h];
      prev[i] = candidate;
      head[h] = i;
      var tries = 0;
      while (candidate >= 0 && tries < _maxChain) {
        final len = _matchLength(input, candidate, i, n);
        if (len > matchLen) {
          matchLen = len;
          matchDist = i - candidate;
          if (i + len >= n) break; // can't do better than reaching the end
        }
        candidate = prev[candidate];
        tries++;
      }
    }

    if (matchLen >= _minMatch) {
      _emitLiterals(out, input, literalStart, i);
      _writeVarint(out, matchLen - _minMatch);
      _writeVarint(out, matchDist);
      // Insert the covered positions so later matches can reference them.
      final end = i + matchLen;
      for (var k = i + 1; k < end; k++) {
        if (k + _minMatch <= n) {
          final h = _hash(input, k);
          prev[k] = head[h];
          head[h] = k;
        }
      }
      i = end;
      literalStart = i;
    } else {
      i++;
    }
  }
  _emitLiterals(out, input, literalStart, n);
  return out.toBytes();
}

/// Decompresses [compressed] to exactly [uncompressedSize] bytes.
Uint8List lzDecompress(Uint8List compressed, int uncompressedSize) {
  final out = Uint8List(uncompressedSize);
  var produced = 0;
  var p = 0;

  int readVarint() {
    var shift = 0;
    var result = 0;
    while (true) {
      final b = compressed[p++];
      result |= (b & 0x7F) << shift;
      if (b < 0x80) return result;
      shift += 7;
    }
  }

  while (produced < uncompressedSize) {
    final literalLength = readVarint();
    for (var k = 0; k < literalLength; k++) {
      out[produced++] = compressed[p++];
    }
    if (produced >= uncompressedSize) break;
    final matchLength = readVarint() + _minMatch;
    final distance = readVarint();
    var src = produced - distance;
    if (src < 0) {
      throw const FormatException('LZ back-reference before start of output');
    }
    for (var k = 0; k < matchLength; k++) {
      out[produced++] = out[src++];
    }
  }
  return out;
}

void _emitLiterals(BytesBuilder out, Uint8List input, int start, int end) {
  _writeVarint(out, end - start);
  if (end > start) out.add(Uint8List.sublistView(input, start, end));
}

void _writeVarint(BytesBuilder out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.addByte(v);
}

/// A web-safe polynomial hash of the four bytes at [i] (stays well under 2^53).
int _hash(Uint8List input, int i) {
  final h =
      ((input[i] * 131 + input[i + 1]) * 131 + input[i + 2]) * 131 +
      input[i + 3];
  return (h ^ (h >> 13)) & (_hashSize - 1);
}

int _matchLength(Uint8List input, int a, int b, int n) {
  var len = 0;
  while (b + len < n && input[a + len] == input[b + len]) {
    len++;
  }
  return len;
}
