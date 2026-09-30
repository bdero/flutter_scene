// The BasisLZ bit writer and Huffman codes (etc1s.dart reads them).

import 'dart:typed_data';

/// Writes bits least significant first.
class BitWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final Uint8List _chunk = Uint8List(4096);
  int _chunkLength = 0;
  int _buffer = 0;
  int _bufferBits = 0;

  /// Writes the low [count] bits of [value] (at most 24 at a time).
  void writeBits(int value, int count) {
    assert(count >= 0 && count <= 24);
    assert(value >= 0 && value < (1 << count));
    _buffer |= value << _bufferBits;
    _bufferBits += count;
    while (_bufferBits >= 8) {
      _putByte(_buffer & 0xFF);
      _buffer >>= 8;
      _bufferBits -= 8;
    }
  }

  /// Writes [symbol] with [code].
  void writeCode(int symbol, HuffmanCode code) {
    final size = code.sizes[symbol];
    assert(size > 0, 'symbol $symbol has no code');
    writeBits(code.codes[symbol], size);
  }

  /// Writes [value] as [chunkBits]-bit chunks, each with a continuation bit.
  void writeVlc(int value, int chunkBits) {
    final mask = (1 << chunkBits) - 1;
    for (;;) {
      final chunk = value & mask;
      value >>= chunkBits;
      if (value == 0) {
        writeBits(chunk, chunkBits + 1);
        return;
      }
      writeBits(chunk | (1 << chunkBits), chunkBits + 1);
    }
  }

  /// Pads to a whole byte with zeros and returns the bytes.
  Uint8List takeBytes() {
    if (_bufferBits > 0) {
      _putByte(_buffer & 0xFF);
      _buffer = 0;
      _bufferBits = 0;
    }
    if (_chunkLength > 0) {
      _bytes.add(Uint8List.fromList(_chunk.sublist(0, _chunkLength)));
      _chunkLength = 0;
    }
    return _bytes.takeBytes();
  }

  void _putByte(int byte) {
    _chunk[_chunkLength++] = byte;
    if (_chunkLength == _chunk.length) {
      _bytes.add(Uint8List.fromList(_chunk));
      _chunkLength = 0;
    }
  }
}

/// The longest code a BasisLZ Huffman table may hold.
const int maxHuffmanCodeSize = 16;

/// A canonical Huffman code: per symbol, a code size (0 for unused symbols)
/// and the code itself, bit-reversed for the LSB-first writer.
class HuffmanCode {
  HuffmanCode._(this.sizes, this.codes);

  /// A complete canonical code with no code longer than [maxCodeSize]. With
  /// no used symbol, symbol 0 gets one: BasisLZ needs at least one code.
  factory HuffmanCode.fromFrequencies(
    List<int> frequencies, {
    int maxCodeSize = maxHuffmanCodeSize,
  }) {
    final count = frequencies.length;
    final sizes = Uint8List(count);
    final used = <int>[
      for (var i = 0; i < count; i++)
        if (frequencies[i] > 0) i,
    ];
    if (used.isEmpty) {
      if (count == 0) throw ArgumentError('A code needs at least one symbol');
      used.add(0);
    }
    if (used.length == 1) {
      sizes[used.single] = 1;
    } else {
      _assignSizes(frequencies, used, sizes, maxCodeSize);
    }
    return HuffmanCode._(sizes, _canonicalCodes(sizes));
  }

  /// Code size per symbol (0 when the symbol has no code).
  final Uint8List sizes;

  /// Code per symbol, bit-reversed so the writer can emit it LSB first.
  final Uint32List codes;

  /// Symbols the serialized table covers: one past the last with a code.
  int get usedSymbolCount {
    var n = sizes.length;
    while (n > 0 && sizes[n - 1] == 0) {
      n--;
    }
    return n;
  }
}

/// Huffman code sizes for the [used] symbols, limited to [maxCodeSize] by
/// folding deeper codes into the limit, then lengthening the longest shorter
/// codes until the Kraft sum fits. Ties break by symbol index.
void _assignSizes(
  List<int> frequencies,
  List<int> used,
  Uint8List sizes,
  int maxCodeSize,
) {
  // Standard Huffman over a min-heap of (weight, order) nodes; leaves first.
  final n = used.length;
  final weight = <int>[for (final s in used) frequencies[s]];
  final parent = List<int>.filled(2 * n - 1, -1);
  final heap = <int>[for (var i = 0; i < n; i++) i];
  int compare(int a, int b) {
    final d = weight[a] - weight[b];
    return d != 0 ? d : a - b;
  }

  void siftDown(int i) {
    for (;;) {
      final l = i * 2 + 1;
      if (l >= heap.length) return;
      var m = l;
      if (l + 1 < heap.length && compare(heap[l + 1], heap[l]) < 0) m = l + 1;
      if (compare(heap[m], heap[i]) >= 0) return;
      final t = heap[m];
      heap[m] = heap[i];
      heap[i] = t;
      i = m;
    }
  }

  void siftUp(int i) {
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (compare(heap[i], heap[p]) >= 0) return;
      final t = heap[p];
      heap[p] = heap[i];
      heap[i] = t;
      i = p;
    }
  }

  int pop() {
    final top = heap.first;
    final last = heap.removeLast();
    if (heap.isNotEmpty) {
      heap[0] = last;
      siftDown(0);
    }
    return top;
  }

  for (var i = (heap.length >> 1) - 1; i >= 0; i--) {
    siftDown(i);
  }
  while (heap.length > 1) {
    final a = pop();
    final b = pop();
    final node = weight.length;
    weight.add(weight[a] + weight[b]);
    parent[a] = node;
    parent[b] = node;
    heap.add(node);
    siftUp(heap.length - 1);
  }
  // Depth of every leaf.
  final depth = List<int>.filled(weight.length, 0);
  for (var node = weight.length - 2; node >= 0; node--) {
    depth[node] = depth[parent[node]] + 1;
  }
  // Count codes per size, folding everything deeper than the limit into
  // it, then trade codes down until the Kraft sum is exactly one.
  final longest = depth.take(n).fold<int>(0, (m, d) => d > m ? d : m);
  final numCodes = List<int>.filled(
    (longest > maxCodeSize ? longest : maxCodeSize) + 1,
    0,
  );
  for (var i = 0; i < n; i++) {
    numCodes[depth[i]]++;
  }
  for (var i = maxCodeSize + 1; i < numCodes.length; i++) {
    numCodes[maxCodeSize] += numCodes[i];
    numCodes[i] = 0;
  }
  var total = 0;
  for (var i = maxCodeSize; i > 0; i--) {
    total += numCodes[i] << (maxCodeSize - i);
  }
  while (total != 1 << maxCodeSize) {
    numCodes[maxCodeSize]--;
    for (var i = maxCodeSize - 1; i > 0; i--) {
      if (numCodes[i] > 0) {
        numCodes[i]--;
        numCodes[i + 1] += 2;
        break;
      }
    }
    total--;
  }
  // Longest codes go to the least frequent symbols.
  final order = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) {
      final d = frequencies[used[a]] - frequencies[used[b]];
      return d != 0 ? d : used[b] - used[a];
    });
  var k = 0;
  for (var size = maxCodeSize; size > 0; size--) {
    for (var c = 0; c < numCodes[size]; c++) {
      sizes[used[order[k++]]] = size;
    }
  }
}

/// Canonical codes for [sizes], bit-reversed (the reader's lookup keys the
/// code MSB first in LSB-first bit order).
Uint32List _canonicalCodes(Uint8List sizes) {
  final counts = List<int>.filled(maxHuffmanCodeSize + 2, 0);
  for (final s in sizes) {
    counts[s]++;
  }
  counts[0] = 0;
  final next = List<int>.filled(maxHuffmanCodeSize + 2, 0);
  var code = 0;
  for (var size = 1; size <= maxHuffmanCodeSize; size++) {
    code = (code + counts[size - 1]) << 1;
    next[size] = code;
  }
  final codes = Uint32List(sizes.length);
  for (var symbol = 0; symbol < sizes.length; symbol++) {
    final size = sizes[symbol];
    if (size == 0) continue;
    var c = next[size]++;
    var reversed = 0;
    for (var i = 0; i < size; i++) {
      reversed = (reversed << 1) | (c & 1);
      c >>= 1;
    }
    codes[symbol] = reversed;
  }
  return codes;
}

// Code-length alphabet of a serialized table (etc1s.dart's readHuffTable).
const int _smallZeroRunCode = 17; // 3-10 zeros, 3 extra bits
const int _bigZeroRunCode = 18; // 11-138 zeros, 7 extra bits
const int _smallRepeatCode = 19; // 3-6 repeats of the last size, 2 bits
const int _bigRepeatCode = 20; // 7-134 repeats, 7 bits
const List<int> _sortedCodeLengthCodes = [
  _smallZeroRunCode, _bigZeroRunCode, _smallRepeatCode, _bigRepeatCode, //
  0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15, 16,
];

/// Serializes [code] as a BasisLZ Huffman table.
void writeHuffmanTable(BitWriter out, HuffmanCode code) {
  final symbolCount = code.usedSymbolCount;
  out.writeBits(symbolCount, 14);
  if (symbolCount == 0) return;

  // Run-length code the sizes: (length code, extra value) pairs.
  final ops = <(int, int)>[];
  var i = 0;
  var previous = -1;
  while (i < symbolCount) {
    final size = code.sizes[i];
    var run = 1;
    while (i + run < symbolCount && code.sizes[i + run] == size) {
      run++;
    }
    if (size == 0) {
      var left = run;
      while (left > 0) {
        if (left >= 11) {
          final take = left > 138 ? 138 : left;
          ops.add((_bigZeroRunCode, take - 11));
          left -= take;
        } else if (left >= 3) {
          ops.add((_smallZeroRunCode, left - 3));
          left = 0;
        } else {
          ops.add((0, 0));
          left--;
        }
      }
    } else {
      // The first of a run is written plainly; the rest repeat it.
      var left = run;
      if (size != previous) {
        ops.add((size, 0));
        left--;
      }
      while (left > 0) {
        if (left >= 7) {
          final take = left > 134 ? 134 : left;
          ops.add((_bigRepeatCode, take - 7));
          left -= take;
        } else if (left >= 3) {
          ops.add((_smallRepeatCode, left - 3));
          left = 0;
        } else {
          ops.add((size, 0));
          left--;
        }
      }
    }
    previous = size;
    i += run;
  }

  final frequencies = List<int>.filled(21, 0);
  for (final (op, _) in ops) {
    frequencies[op]++;
  }
  final lengthCode = HuffmanCode.fromFrequencies(frequencies, maxCodeSize: 7);
  var written = _sortedCodeLengthCodes.length;
  while (written > 1 &&
      lengthCode.sizes[_sortedCodeLengthCodes[written - 1]] == 0) {
    written--;
  }
  out.writeBits(written, 5);
  for (var k = 0; k < written; k++) {
    out.writeBits(lengthCode.sizes[_sortedCodeLengthCodes[k]], 3);
  }
  for (final (op, extra) in ops) {
    out.writeCode(op, lengthCode);
    switch (op) {
      case _smallZeroRunCode:
        out.writeBits(extra, 3);
      case _bigZeroRunCode:
        out.writeBits(extra, 7);
      case _smallRepeatCode:
        out.writeBits(extra, 2);
      case _bigRepeatCode:
        out.writeBits(extra, 7);
    }
  }
}
