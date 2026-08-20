// A pure-Dart Zstandard (RFC 8878) decompressor, decode only.
//
// KTX2 files produced by standard encoders (toktx, ktx, basisu) supercompress
// mip level payloads with zstd, so the engine needs a decoder on every backend
// including web. Scope is what those encoders emit: single-segment frames, no
// dictionaries, no long-distance matching beyond the in-frame window. The
// output size is always known from the KTX2 level index, so decoding fills an
// exact-size buffer and needs no separate window.
//
// Section references below cite RFC 8878. dart2js ints have 32-bit bitwise
// semantics, so wide bit reads are assembled with arithmetic (multiply/divide
// stay exact below 2^53) and shifts never cross bit 31.

import 'dart:typed_data';

/// Decompresses a complete zstd frame sequence in [input] to exactly
/// [uncompressedSize] bytes. Throws [FormatException] on malformed input.
Uint8List zstdDecompress(Uint8List input, int uncompressedSize) {
  final out = Uint8List(uncompressedSize);
  var outEnd = 0;
  var p = 0;
  while (p < input.length) {
    final frame = _readFrame(input, p, out, outEnd);
    p = frame.inputEnd;
    outEnd = frame.outputEnd;
  }
  if (outEnd != uncompressedSize) {
    throw FormatException(
      'Zstandard: expected $uncompressedSize bytes, produced $outEnd',
    );
  }
  return out;
}

// Powers of two as plain ints (doubling keeps them exact past bit 31).
final List<int> _pow2 = () {
  final list = List<int>.filled(53, 0);
  var v = 1;
  for (var i = 0; i < 53; i++) {
    list[i] = v;
    v += v;
  }
  return list;
}();

const int _magic = 0xFD2FB528;
const int _skippableMagicMin = 0x184D2A50;
const int _skippableMagicMax = 0x184D2A5F;

int _u32(Uint8List b, int p) {
  if (p + 4 > b.length) {
    throw const FormatException('Zstandard: truncated input');
  }
  // Arithmetic assembly keeps the value positive on dart2js.
  return b[p] + b[p + 1] * 0x100 + b[p + 2] * 0x10000 + b[p + 3] * 0x1000000;
}

({int inputEnd, int outputEnd}) _readFrame(
  Uint8List input,
  int p,
  Uint8List out,
  int outStart,
) {
  final magic = _u32(input, p);
  p += 4;
  if (magic >= _skippableMagicMin && magic <= _skippableMagicMax) {
    // Skippable frame (3.1.2): 4-byte size then opaque payload.
    final size = _u32(input, p);
    return (inputEnd: p + 4 + size, outputEnd: outStart);
  }
  if (magic != _magic) {
    throw const FormatException('Zstandard: bad frame magic');
  }

  // Frame header (3.1.1.1).
  if (p >= input.length) {
    throw const FormatException('Zstandard: truncated frame header');
  }
  final descriptor = input[p++];
  final fcsFlag = descriptor >> 6;
  final singleSegment = (descriptor >> 5) & 1;
  final checksumFlag = (descriptor >> 2) & 1;
  final dictIdFlag = descriptor & 3;
  if ((descriptor >> 3) & 3 != 0) {
    throw const FormatException('Zstandard: reserved descriptor bits set');
  }
  if (singleSegment == 0) {
    p++; // Window descriptor; the exact-size output buffer is the window.
  }
  if (dictIdFlag != 0) {
    var dictId = 0;
    final dictBytes = dictIdFlag == 3 ? 4 : dictIdFlag;
    for (var i = 0; i < dictBytes; i++) {
      dictId += input[p + i] * _pow2[8 * i];
    }
    p += dictBytes;
    if (dictId != 0) {
      throw const FormatException('Zstandard: dictionaries are unsupported');
    }
  }
  var contentSize = -1;
  final fcsBytes = switch (fcsFlag) {
    0 => singleSegment == 1 ? 1 : 0,
    1 => 2,
    2 => 4,
    _ => 8,
  };
  if (fcsBytes > 0) {
    contentSize = 0;
    for (var i = 0; i < fcsBytes; i++) {
      final byte = input[p + i];
      if (i >= 7 || (i == 6 && byte > 0x1F)) {
        if (byte != 0) {
          throw const FormatException('Zstandard: content size exceeds 2^53');
        }
      } else {
        contentSize += byte * _pow2[8 * i];
      }
    }
    if (fcsBytes == 2) contentSize += 256;
    p += fcsBytes;
  }

  final frame = _FrameState(out, outStart);
  var last = false;
  while (!last) {
    if (p + 3 > input.length) {
      throw const FormatException('Zstandard: truncated block header');
    }
    // Block header (3.1.1.2): lastBlock(1) type(2) size(21), little-endian.
    final header = input[p] + input[p + 1] * 0x100 + input[p + 2] * 0x10000;
    p += 3;
    last = header & 1 == 1;
    final type = (header >> 1) & 3;
    final size = header >> 3;
    switch (type) {
      case 0: // Raw block.
        if (p + size > input.length) {
          throw const FormatException('Zstandard: truncated raw block');
        }
        frame.write(input, p, size);
        p += size;
      case 1: // RLE block: one byte repeated `size` times.
        if (p >= input.length) {
          throw const FormatException('Zstandard: truncated RLE block');
        }
        frame.fill(input[p], size);
        p++;
      case 2: // Compressed block.
        if (p + size > input.length) {
          throw const FormatException('Zstandard: truncated compressed block');
        }
        _decodeCompressedBlock(input, p, size, frame);
        p += size;
      default:
        throw const FormatException('Zstandard: reserved block type');
    }
  }
  if (checksumFlag == 1) {
    p += 4; // XXH64 low bits (3.1.1); not verified, level index sizes the data.
  }
  if (contentSize >= 0 && frame.cursor - outStart != contentSize) {
    throw const FormatException('Zstandard: frame content size mismatch');
  }
  return (inputEnd: p, outputEnd: frame.cursor);
}

/// Output cursor plus the entropy tables that persist across blocks in one
/// frame (treeless literals and repeat sequence tables, 3.1.1.3).
class _FrameState {
  _FrameState(this.out, this.cursor);

  final Uint8List out;
  int cursor;

  _HuffTable? huffman;
  _FseTable? llTable;
  _FseTable? ofTable;
  _FseTable? mlTable;
  // Repeat offset history, most recent first (3.1.1.5).
  final List<int> repeats = [1, 4, 8];

  void write(Uint8List src, int start, int length) {
    if (cursor + length > out.length) {
      throw const FormatException('Zstandard: output overflow');
    }
    out.setRange(cursor, cursor + length, src, start);
    cursor += length;
  }

  void fill(int byte, int length) {
    if (cursor + length > out.length) {
      throw const FormatException('Zstandard: output overflow');
    }
    out.fillRange(cursor, cursor + length, byte);
    cursor += length;
  }
}

// --- Bit readers ---------------------------------------------------------

/// Forward little-endian bit reader (FSE table descriptions, 4.1.1).
class _ForwardBits {
  _ForwardBits(this.bytes, this.byteStart, this.byteEnd);

  final Uint8List bytes;
  final int byteStart;
  final int byteEnd;
  int bitPos = 0;

  /// Bits consumed, rounded up to whole bytes.
  int get bytesConsumed => (bitPos + 7) >> 3;

  int read(int n) {
    final v = peek(n);
    bitPos += n;
    return v;
  }

  int peek(int n) {
    assert(n <= 41);
    final base = byteStart + (bitPos >> 3);
    var acc = 0;
    // Six bytes cover a 41-bit read at any offset; stays below 2^53.
    for (var i = 5; i >= 0; i--) {
      final index = base + i;
      acc = acc * 256 + (index < byteEnd ? bytes[index] : 0);
    }
    return (acc ~/ _pow2[bitPos & 7]) % _pow2[n];
  }
}

/// Backward bit reader (Huffman streams and sequences, 3.1.1.3.1.1). The
/// stream is written forward LSB-first and read from the top; the final byte
/// carries a 1-bit sentinel above zero padding.
class _BackwardBits {
  _BackwardBits(this.bytes, int byteStart, int byteEnd) : _start = byteStart {
    if (byteEnd <= byteStart) {
      throw const FormatException('Zstandard: empty bitstream');
    }
    final lastByte = bytes[byteEnd - 1];
    if (lastByte == 0) {
      throw const FormatException('Zstandard: missing bitstream sentinel');
    }
    // Position just below the sentinel bit.
    pos = (byteEnd - 1 - _start) * 8 + lastByte.bitLength - 1;
  }

  final Uint8List bytes;
  final int _start;

  /// Bits remaining (index of the next unread bit).
  int pos = 0;

  /// Reads [n] bits below the cursor. Reads past the beginning return
  /// zero-filled low bits, matching the reference decoder's stream flush; the
  /// caller detects exhaustion via [pos] going negative.
  int read(int n) {
    assert(n <= 41);
    pos -= n;
    if (n == 0) return 0;
    var from = pos;
    var take = n;
    if (from < 0) {
      take += from; // Zero-pad the missing low bits.
      from = 0;
      if (take <= 0) return 0;
    }
    final base = _start + (from >> 3);
    var acc = 0;
    for (var i = 5; i >= 0; i--) {
      final index = base + i;
      acc = acc * 256 + (index < bytes.length ? bytes[index] : 0);
    }
    final v = (acc ~/ _pow2[from & 7]) % _pow2[take];
    return from == pos ? v : v * _pow2[n - take];
  }
}

// --- FSE -----------------------------------------------------------------

/// A decoded FSE table (4.1.1): per-state symbol, bit count, and baseline.
class _FseTable {
  _FseTable(this.log, this.symbols, this.nbBits, this.baselines);

  final int log;
  final Uint8List symbols;
  final Uint8List nbBits;
  final Uint16List baselines;
}

/// Reads a normalized count distribution (4.1.1) and builds the decode table.
_FseTable _readFseTable(_ForwardBits bits, int maxLog, int maxSymbol) {
  final accuracyLog = bits.read(4) + 5;
  if (accuracyLog > maxLog) {
    throw const FormatException('Zstandard: FSE accuracy log too large');
  }
  final tableSize = 1 << accuracyLog;
  final counts = List<int>.filled(maxSymbol + 1, 0);
  var remaining = tableSize + 1;
  var threshold = tableSize;
  var nBits = accuracyLog + 1;
  var symbol = 0;
  var previousZero = false;
  while (remaining > 1 && symbol <= maxSymbol) {
    if (previousZero) {
      // Runs of zero-probability symbols use 2-bit repeat flags.
      var repeat = bits.read(2);
      symbol += repeat;
      while (repeat == 3) {
        repeat = bits.read(2);
        symbol += repeat;
      }
      previousZero = false;
      continue;
    }
    final max = 2 * threshold - 1 - remaining;
    int value;
    final small = bits.peek(nBits - 1);
    if (small < max) {
      // Small values fit in one fewer bit.
      value = small;
      bits.bitPos += nBits - 1;
    } else {
      value = bits.read(nBits);
      if (value >= threshold) value -= max;
    }
    final count = value - 1; // -1 encodes a less-than-one probability.
    if (symbol > maxSymbol) {
      throw const FormatException('Zstandard: FSE symbol out of range');
    }
    counts[symbol] = count;
    remaining -= count < 0 ? 1 : count;
    symbol++;
    previousZero = count == 0;
    while (remaining < threshold && remaining > 1) {
      nBits--;
      threshold >>= 1;
    }
  }
  if (remaining != 1) {
    throw const FormatException('Zstandard: corrupt FSE distribution');
  }
  // Each table description ends byte-aligned.
  bits.bitPos = (bits.bitPos + 7) & ~7;
  return _buildFseTable(counts, accuracyLog);
}

_FseTable _buildFseTable(List<int> counts, int log) {
  final tableSize = 1 << log;
  final symbols = Uint8List(tableSize);
  final nbBits = Uint8List(tableSize);
  final baselines = Uint16List(tableSize);

  var highThreshold = tableSize - 1;
  // Less-than-one symbols take one cell at the top of the table.
  for (var s = 0; s < counts.length; s++) {
    if (counts[s] == -1) {
      symbols[highThreshold--] = s;
    }
  }
  final step = (tableSize >> 1) + (tableSize >> 3) + 3;
  final mask = tableSize - 1;
  var position = 0;
  for (var s = 0; s < counts.length; s++) {
    for (var i = 0; i < counts[s]; i++) {
      symbols[position] = s;
      do {
        position = (position + step) & mask;
      } while (position > highThreshold);
    }
  }
  if (position != 0) {
    throw const FormatException('Zstandard: FSE table spread mismatch');
  }
  // Per-cell transition: x-th occurrence of a symbol determines bits/baseline.
  final next = List<int>.filled(counts.length, 0);
  for (var s = 0; s < counts.length; s++) {
    next[s] = counts[s] == -1 ? 1 : counts[s];
  }
  for (var cell = 0; cell < tableSize; cell++) {
    final s = symbols[cell];
    final x = next[s]++;
    final bitCount = log - (x.bitLength - 1);
    nbBits[cell] = bitCount;
    baselines[cell] = (x << bitCount) - tableSize;
  }
  return _FseTable(log, symbols, nbBits, baselines);
}

/// A table for an RLE mode: one state, zero bits, always the same symbol.
_FseTable _rleTable(int symbol) =>
    _FseTable(0, Uint8List.fromList([symbol]), Uint8List(1), Uint16List(1));

// --- Huffman -------------------------------------------------------------

class _HuffTable {
  _HuffTable(this.maxBits, this.symbols, this.lengths);

  final int maxBits;
  final Uint8List symbols;
  final Uint8List lengths;
}

/// Parses a Huffman table description (4.2.1) starting at [p]. Returns the
/// table and the number of description bytes consumed.
({_HuffTable table, int size}) _readHuffTable(Uint8List input, int p, int end) {
  if (p >= end) {
    throw const FormatException('Zstandard: truncated Huffman description');
  }
  final headerByte = input[p];
  final weights = <int>[];
  int consumed;
  if (headerByte >= 128) {
    // Direct representation: 4-bit weights, high nibble first.
    final count = headerByte - 127;
    final bytes = (count + 1) >> 1;
    if (p + 1 + bytes > end) {
      throw const FormatException('Zstandard: truncated Huffman weights');
    }
    for (var i = 0; i < count; i++) {
      final byte = input[p + 1 + (i >> 1)];
      weights.add(i.isEven ? byte >> 4 : byte & 0xF);
    }
    consumed = 1 + bytes;
  } else {
    // FSE-compressed weights: two interleaved states, accuracy log <= 6.
    final compressedSize = headerByte;
    if (p + 1 + compressedSize > end) {
      throw const FormatException('Zstandard: truncated Huffman weights');
    }
    final wStart = p + 1;
    final wEnd = wStart + compressedSize;
    final fwd = _ForwardBits(input, wStart, wEnd);
    final table = _readFseTable(fwd, 6, 255);
    final bits = _BackwardBits(input, wStart + fwd.bytesConsumed, wEnd);
    var state1 = bits.read(table.log);
    var state2 = bits.read(table.log);
    // Alternate states until the stream runs out (4.1.2); the state whose
    // update exhausts the stream emits, then the other emits and decoding
    // stops.
    while (true) {
      weights.add(table.symbols[state1]);
      if (weights.length > 255) {
        throw const FormatException('Zstandard: too many Huffman weights');
      }
      state1 = table.baselines[state1] + bits.read(table.nbBits[state1]);
      if (bits.pos < 0) {
        weights.add(table.symbols[state2]);
        break;
      }
      weights.add(table.symbols[state2]);
      if (weights.length > 255) {
        throw const FormatException('Zstandard: too many Huffman weights');
      }
      state2 = table.baselines[state2] + bits.read(table.nbBits[state2]);
      if (bits.pos < 0) {
        weights.add(table.symbols[state1]);
        break;
      }
    }
    consumed = 1 + compressedSize;
  }

  // The last weight is implicit (4.2.1.1): explicit weights must sum short of
  // a power of two by another power of two.
  var sum = 0;
  for (final w in weights) {
    if (w > 0) sum += _pow2[w - 1];
  }
  if (sum == 0) {
    throw const FormatException('Zstandard: empty Huffman table');
  }
  final maxBits = sum.bitLength;
  final leftover = _pow2[maxBits] - sum;
  if (leftover & (leftover - 1) != 0) {
    throw const FormatException('Zstandard: invalid Huffman weight sum');
  }
  weights.add(leftover.bitLength);
  if (maxBits > 11) {
    throw const FormatException('Zstandard: Huffman code longer than 11 bits');
  }

  // Canonical table: symbols sorted by weight then index fill 2^(w-1) cells.
  final tableSize = 1 << maxBits;
  final symbols = Uint8List(tableSize);
  final lengths = Uint8List(tableSize);
  var cell = 0;
  for (var w = 1; w <= maxBits; w++) {
    for (var s = 0; s < weights.length; s++) {
      if (weights[s] != w) continue;
      final span = 1 << (w - 1);
      final length = maxBits + 1 - w;
      for (var i = 0; i < span; i++) {
        symbols[cell] = s;
        lengths[cell] = length;
        cell++;
      }
    }
  }
  if (cell != tableSize) {
    throw const FormatException('Zstandard: Huffman table underfilled');
  }
  return (table: _HuffTable(maxBits, symbols, lengths), size: consumed);
}

/// Decodes one backward Huffman stream to exactly [count] bytes.
void _huffDecodeStream(
  _HuffTable table,
  Uint8List input,
  int start,
  int end,
  Uint8List out,
  int outStart,
  int count,
) {
  final bits = _BackwardBits(input, start, end);
  for (var i = 0; i < count; i++) {
    final index = bits.read(table.maxBits);
    if (bits.pos + table.maxBits < 0) {
      throw const FormatException('Zstandard: Huffman stream exhausted');
    }
    out[outStart + i] = table.symbols[index];
    // Push back the bits the entry did not use.
    bits.pos += table.maxBits - table.lengths[index];
  }
  if (bits.pos != 0) {
    throw const FormatException('Zstandard: Huffman stream not fully consumed');
  }
}

// --- Compressed block ----------------------------------------------------

// Literal length codes 16..35 (3.1.1.3.2.1.1).
const List<int> _llBase = [
  16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, //
  2048, 4096, 8192, 16384, 32768, 65536,
];
const List<int> _llBits = [
  1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, //
];

// Match length codes 32..52 (3.1.1.3.2.1.1).
const List<int> _mlBase = [
  35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, //
  2051, 4099, 8195, 16387, 32771, 65539,
];
const List<int> _mlBits = [
  1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, //
];

// Predefined distributions (3.1.1.3.2.2).
const List<int> _llDefault = [
  4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, //
  2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
];
const List<int> _mlDefault = [
  1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, -1, -1, -1, -1, -1, -1, -1,
];
const List<int> _ofDefault = [
  1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, -1, -1, -1, -1, -1,
];

final _FseTable _llPredefined = _buildFseTable(_llDefault, 6);
final _FseTable _mlPredefined = _buildFseTable(_mlDefault, 6);
final _FseTable _ofPredefined = _buildFseTable(_ofDefault, 5);

void _decodeCompressedBlock(
  Uint8List input,
  int blockStart,
  int blockSize,
  _FrameState frame,
) {
  var p = blockStart;
  final blockEnd = blockStart + blockSize;

  // Literals section (3.1.1.3.1).
  final byte0 = input[p];
  final literalsType = byte0 & 3;
  final sizeFormat = (byte0 >> 2) & 3;
  int regenSize;
  Uint8List literals;
  if (literalsType == 0 || literalsType == 1) {
    // Raw or RLE literals.
    switch (sizeFormat) {
      case 0 || 2:
        regenSize = byte0 >> 3;
        p += 1;
      case 1:
        regenSize = (byte0 >> 4) + input[p + 1] * 16;
        p += 2;
      default:
        regenSize = (byte0 >> 4) + input[p + 1] * 16 + input[p + 2] * 4096;
        p += 3;
    }
    if (literalsType == 0) {
      if (p + regenSize > blockEnd) {
        throw const FormatException('Zstandard: truncated raw literals');
      }
      literals = Uint8List.sublistView(input, p, p + regenSize);
      p += regenSize;
    } else {
      if (p >= blockEnd) {
        throw const FormatException('Zstandard: truncated RLE literals');
      }
      literals = Uint8List(regenSize)..fillRange(0, regenSize, input[p]);
      p += 1;
    }
  } else {
    // Compressed (2) or treeless (3) literals.
    int compressedSize;
    int streams = 4;
    switch (sizeFormat) {
      case 0 || 1:
        if (sizeFormat == 0) streams = 1;
        regenSize = (byte0 >> 4) + (input[p + 1] & 0x3F) * 16;
        compressedSize = (input[p + 1] >> 6) + input[p + 2] * 4;
        p += 3;
      case 2:
        regenSize =
            (byte0 >> 4) + input[p + 1] * 16 + (input[p + 2] & 3) * 4096;
        compressedSize = (input[p + 2] >> 2) + input[p + 3] * 64;
        p += 4;
      default:
        regenSize =
            (byte0 >> 4) + input[p + 1] * 16 + (input[p + 2] & 0x3F) * 4096;
        compressedSize =
            (input[p + 2] >> 6) + input[p + 3] * 4 + input[p + 4] * 1024;
        p += 5;
    }
    final litEnd = p + compressedSize;
    if (litEnd > blockEnd) {
      throw const FormatException('Zstandard: truncated literals section');
    }
    _HuffTable table;
    if (literalsType == 2) {
      final read = _readHuffTable(input, p, litEnd);
      table = read.table;
      frame.huffman = table;
      p += read.size;
    } else {
      final previous = frame.huffman;
      if (previous == null) {
        throw const FormatException(
          'Zstandard: treeless literals with no previous table',
        );
      }
      table = previous;
    }
    literals = Uint8List(regenSize);
    if (streams == 1) {
      _huffDecodeStream(table, input, p, litEnd, literals, 0, regenSize);
    } else {
      // Jump table: sizes of the first three streams (3.1.1.3.1.6).
      if (p + 6 > litEnd) {
        throw const FormatException('Zstandard: truncated jump table');
      }
      final s1 = input[p] + input[p + 1] * 256;
      final s2 = input[p + 2] + input[p + 3] * 256;
      final s3 = input[p + 4] + input[p + 5] * 256;
      p += 6;
      final s4 = litEnd - p - s1 - s2 - s3;
      if (s4 < 0) {
        throw const FormatException('Zstandard: jump table overflow');
      }
      final chunk = (regenSize + 3) >> 2;
      final starts = [p, p + s1, p + s1 + s2, p + s1 + s2 + s3];
      final sizes = [s1, s2, s3, s4];
      for (var i = 0; i < 4; i++) {
        final count = i < 3 ? chunk : regenSize - 3 * chunk;
        if (count < 0) {
          throw const FormatException('Zstandard: bad literal stream split');
        }
        _huffDecodeStream(
          table,
          input,
          starts[i],
          starts[i] + sizes[i],
          literals,
          i * chunk,
          count,
        );
      }
    }
    p = litEnd;
  }

  // Sequences section (3.1.1.3.2).
  if (p >= blockEnd) {
    throw const FormatException('Zstandard: missing sequences section');
  }
  var nbSeq = input[p];
  if (nbSeq < 128) {
    p += 1;
  } else if (nbSeq < 255) {
    nbSeq = (nbSeq - 128) * 256 + input[p + 1];
    p += 2;
  } else {
    nbSeq = input[p + 1] + input[p + 2] * 256 + 0x7F00;
    p += 3;
  }
  if (nbSeq == 0) {
    frame.write(literals, 0, literals.length);
    return;
  }

  final modes = input[p++];
  if (modes & 3 != 0) {
    throw const FormatException('Zstandard: reserved sequence mode bits');
  }
  final fwd = _ForwardBits(input, p, blockEnd);
  frame.llTable = _sequenceTable(
    (modes >> 6) & 3,
    fwd,
    input,
    _llPredefined,
    frame.llTable,
    9,
    35,
  );
  frame.ofTable = _sequenceTable(
    (modes >> 4) & 3,
    fwd,
    input,
    _ofPredefined,
    frame.ofTable,
    8,
    31,
  );
  frame.mlTable = _sequenceTable(
    (modes >> 2) & 3,
    fwd,
    input,
    _mlPredefined,
    frame.mlTable,
    9,
    52,
  );
  p += fwd.bytesConsumed;
  final llTable = frame.llTable!;
  final ofTable = frame.ofTable!;
  final mlTable = frame.mlTable!;

  final bits = _BackwardBits(input, p, blockEnd);
  var llState = bits.read(llTable.log);
  var ofState = bits.read(ofTable.log);
  var mlState = bits.read(mlTable.log);
  if (bits.pos < 0) {
    throw const FormatException('Zstandard: sequence bitstream too short');
  }

  var litCursor = 0;
  final repeats = frame.repeats;
  for (var seq = 0; seq < nbSeq; seq++) {
    // Value bits are read offset, match, literal (3.1.1.3.2.1.2).
    final ofCode = ofTable.symbols[ofState];
    final offsetValue = _pow2[ofCode] + bits.read(ofCode);
    final mlCode = mlTable.symbols[mlState];
    final matchLength = mlCode < 32
        ? mlCode + 3
        : _mlBase[mlCode - 32] + bits.read(_mlBits[mlCode - 32]);
    final llCode = llTable.symbols[llState];
    final literalLength = llCode < 16
        ? llCode
        : _llBase[llCode - 16] + bits.read(_llBits[llCode - 16]);
    if (bits.pos < 0) {
      throw const FormatException('Zstandard: sequence bitstream exhausted');
    }

    // Offset resolution with the repeat history (3.1.1.5).
    int offset;
    if (offsetValue > 3) {
      offset = offsetValue - 3;
      repeats[2] = repeats[1];
      repeats[1] = repeats[0];
      repeats[0] = offset;
    } else {
      // Literal length zero shifts the repeat index by one; index 3 means
      // "most recent minus one".
      final index = literalLength == 0 ? offsetValue : offsetValue - 1;
      if (index == 0) {
        offset = repeats[0];
      } else {
        offset = index == 3 ? repeats[0] - 1 : repeats[index];
        if (offset == 0) {
          throw const FormatException('Zstandard: zero repeat offset');
        }
        if (index >= 2) repeats[2] = repeats[1];
        repeats[1] = repeats[0];
        repeats[0] = offset;
      }
    }

    if (litCursor + literalLength > literals.length) {
      throw const FormatException('Zstandard: literal overrun');
    }
    frame.write(literals, litCursor, literalLength);
    litCursor += literalLength;

    if (offset > frame.cursor) {
      throw const FormatException('Zstandard: match offset before output');
    }
    if (frame.cursor + matchLength > frame.out.length) {
      throw const FormatException('Zstandard: output overflow');
    }
    // Byte-wise copy: overlapping matches replicate recent output.
    var src = frame.cursor - offset;
    final out = frame.out;
    for (var i = 0; i < matchLength; i++) {
      out[frame.cursor++] = out[src++];
    }

    if (seq + 1 < nbSeq) {
      // State updates read literal, match, offset (3.1.1.3.2.1.2).
      llState = llTable.baselines[llState] + bits.read(llTable.nbBits[llState]);
      mlState = mlTable.baselines[mlState] + bits.read(mlTable.nbBits[mlState]);
      ofState = ofTable.baselines[ofState] + bits.read(ofTable.nbBits[ofState]);
      if (bits.pos < 0) {
        throw const FormatException('Zstandard: sequence bitstream exhausted');
      }
    }
  }
  frame.write(literals, litCursor, literals.length - litCursor);
}

/// Resolves one sequence table from its 2-bit compression mode
/// (3.1.1.3.2.1.1): predefined, RLE, FSE-described, or repeat.
_FseTable _sequenceTable(
  int mode,
  _ForwardBits bits,
  Uint8List input,
  _FseTable predefined,
  _FseTable? previous,
  int maxLog,
  int maxSymbol,
) {
  switch (mode) {
    case 0:
      return predefined;
    case 1:
      if (bits.bitPos & 7 != 0) {
        throw const FormatException('Zstandard: misaligned RLE table byte');
      }
      final symbol = input[bits.byteStart + bits.bytesConsumed];
      bits.bitPos += 8;
      if (symbol > maxSymbol) {
        throw const FormatException('Zstandard: RLE symbol out of range');
      }
      return _rleTable(symbol);
    case 2:
      return _readFseTable(bits, maxLog, maxSymbol);
    default:
      final table = previous;
      if (table == null) {
        throw const FormatException(
          'Zstandard: repeat mode with no previous table',
        );
      }
      return table;
  }
}
