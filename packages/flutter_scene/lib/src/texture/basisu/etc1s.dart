// An ETC1S/BasisLZ decoder producing RGBA8, for standard KTX2 textures
// (glTF KHR_texture_basisu). The BasisLZ supercompression global data holds
// Huffman-coded endpoint/selector codebooks shared by every slice; each mip
// level is an independently coded slice of codebook references, with alpha
// shipped as a second slice whose green channel carries the values.
//
// The bitstream layout, codebook models, and slice decode are ported from
// Binomial LLC's basis_universal transcoder (Apache-2.0); see
// THIRD_PARTY_NOTICES.md. Output matches the reference transcoder's RGBA32
// target byte for byte.

import 'dart:typed_data';

// ETC1 intensity modifier table, indexed by inten5 then selector value.
const List<List<int>> _etc1IntenTables = [
  [-8, -2, 2, 8],
  [-17, -5, 5, 17],
  [-29, -9, 9, 29],
  [-42, -13, 13, 42],
  [-60, -18, 18, 60],
  [-80, -24, 24, 80],
  [-106, -33, 33, 106],
  [-183, -47, 47, 183],
];

// Huffman table serialization constants (basis_universal huffman coding).
const int _maxSymsLog2 = 14;
const int _maxSyms = 1 << _maxSymsLog2;
const int _totalCodelengthCodes = 21;
const int _smallZeroRunCode = 17;
const int _bigZeroRunCode = 18;
const int _smallRepeatCode = 19;
const List<int> _sortedCodelengthCodes = [
  _smallZeroRunCode, _bigZeroRunCode, _smallRepeatCode, 20, //
  0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15, 16,
];
const int _maxCodeSize = 16;

// Slice decode constants.
const int _endpointPredRepeatLastSymbol = 256;
const int _endpointPredMinRepeatCount = 3;
const int _endpointPredCountVlcBits = 4;
const int _selectorHistoryBufRleCountThresh = 3;
const int _selectorHistoryBufRleCountTotal = 64;

/// LSB-first bit reader over a byte buffer, reading zeros past the end
/// (matching the reference decoder). Single reads stay at or below 16 bits so
/// the bit buffer never crosses bit 31.
class _BitReader {
  _BitReader(this._data);

  final Uint8List _data;
  int _pos = 0;
  int _bitBuf = 0;
  int _bitCount = 0;

  int _peek(int numBits) {
    while (_bitCount < numBits) {
      final c = _pos < _data.length ? _data[_pos++] : 0;
      _bitBuf |= c << _bitCount;
      _bitCount += 8;
    }
    return _bitBuf & ((1 << numBits) - 1);
  }

  void _remove(int numBits) {
    _bitBuf >>= numBits;
    _bitCount -= numBits;
  }

  int getBits(int numBits) {
    final bits = _peek(numBits);
    _remove(numBits);
    return bits;
  }

  /// Variable-length code of [chunkBits]-sized chunks, low chunk first, each
  /// followed by a continuation bit.
  int decodeVlc(int chunkBits) {
    final chunkSize = 1 << chunkBits;
    final chunkMask = chunkSize - 1;
    var v = 0;
    var ofs = 0;
    for (;;) {
      final s = getBits(chunkBits + 1);
      v |= (s & chunkMask) << ofs;
      ofs += chunkBits;
      if ((s & chunkSize) == 0) break;
      if (ofs >= 24) {
        throw const FormatException('ETC1S VLC run is too long');
      }
    }
    return v;
  }

  int decodeHuffman(_HuffTable table) {
    final entry = table.lookup[_peek(table.maxCodeSize)];
    if (entry < 0) {
      throw const FormatException('Invalid ETC1S Huffman code');
    }
    _remove(entry >> 16);
    return entry & 0xFFFF;
  }

  /// Reads a serialized Huffman code-length table and builds its decoder.
  _HuffTable readHuffTable() {
    final totalUsedSyms = getBits(_maxSymsLog2);
    if (totalUsedSyms == 0) return _HuffTable.empty();
    if (totalUsedSyms > _maxSyms) {
      throw const FormatException('ETC1S Huffman table is too large');
    }
    final codeLengthCodeSizes = Uint8List(_totalCodelengthCodes);
    final numCodelengthCodes = getBits(5);
    if (numCodelengthCodes < 1 || numCodelengthCodes > _totalCodelengthCodes) {
      throw const FormatException('Invalid ETC1S code-length code count');
    }
    for (var i = 0; i < numCodelengthCodes; i++) {
      codeLengthCodeSizes[_sortedCodelengthCodes[i]] = getBits(3);
    }
    final codeLengthTable = _HuffTable.fromCodeSizes(codeLengthCodeSizes);
    final codeSizes = Uint8List(totalUsedSyms);
    var cur = 0;
    while (cur < totalUsedSyms) {
      final c = decodeHuffman(codeLengthTable);
      if (c <= 16) {
        codeSizes[cur++] = c;
      } else if (c == _smallZeroRunCode) {
        cur += getBits(3) + 3;
      } else if (c == _bigZeroRunCode) {
        cur += getBits(7) + 11;
      } else {
        if (cur == 0) {
          throw const FormatException('ETC1S repeat code with no prior size');
        }
        var l = c == _smallRepeatCode ? getBits(2) + 3 : getBits(7) + 7;
        final prev = codeSizes[cur - 1];
        if (prev == 0) {
          throw const FormatException('ETC1S repeat of a zero code size');
        }
        do {
          if (cur >= totalUsedSyms) {
            throw const FormatException('ETC1S code size run overflows');
          }
          codeSizes[cur++] = prev;
        } while (--l > 0);
      }
    }
    if (cur != totalUsedSyms) {
      throw const FormatException('ETC1S code sizes overflow the table');
    }
    return _HuffTable.fromCodeSizes(codeSizes);
  }
}

/// A canonical Huffman decoding table as a full lookup over the maximum code
/// length: entry = (codeSize << 16) | symbol, -1 for invalid prefixes.
class _HuffTable {
  _HuffTable._(this.lookup, this.maxCodeSize);

  final Int32List lookup;
  final int maxCodeSize;

  bool get isEmpty => maxCodeSize == 0;

  factory _HuffTable.empty() => _HuffTable._(Int32List(1), 0);

  factory _HuffTable.fromCodeSizes(Uint8List codeSizes) {
    var maxSize = 0;
    final symsUsingCodesize = List<int>.filled(_maxCodeSize + 1, 0);
    var usedSyms = 0;
    for (final size in codeSizes) {
      if (size > _maxCodeSize) {
        throw const FormatException('ETC1S Huffman code size out of range');
      }
      if (size > 0) {
        symsUsingCodesize[size]++;
        usedSyms++;
        if (size > maxSize) maxSize = size;
      }
    }
    if (usedSyms == 0) return _HuffTable.empty();
    // Canonical code assignment, with the reference decoder's completeness
    // check (a full code, or a single-symbol degenerate one).
    final nextCode = List<int>.filled(_maxCodeSize + 2, 0);
    var total = 0;
    for (var i = 1; i <= _maxCodeSize; i++) {
      total = (total + symsUsingCodesize[i]) << 1;
      nextCode[i + 1] = total;
    }
    if (total != (1 << (_maxCodeSize + 1)) && usedSyms != 1) {
      throw const FormatException('ETC1S Huffman code sizes are not valid');
    }
    final lookup = Int32List(1 << maxSize)..fillRange(0, 1 << maxSize, -1);
    for (var sym = 0; sym < codeSizes.length; sym++) {
      final size = codeSizes[sym];
      if (size == 0) continue;
      final code = nextCode[size]++;
      // The stream carries the code MSB-first in LSB-first bit order, so the
      // lookup key is the bit-reversed code padded to maxSize.
      var revCode = 0;
      var c = code;
      for (var l = 0; l < size; l++) {
        revCode = (revCode << 1) | (c & 1);
        c >>= 1;
      }
      final entry = (size << 16) | sym;
      for (var k = revCode; k < (1 << maxSize); k += 1 << size) {
        if (lookup[k] != -1) {
          throw const FormatException('ETC1S Huffman codes are ambiguous');
        }
        lookup[k] = entry;
      }
    }
    return _HuffTable._(lookup, maxSize);
  }
}

/// One image's slice extents inside its mip level payload.
class Etc1sImageDesc {
  Etc1sImageDesc({
    required this.flags,
    required this.rgbSliceByteOffset,
    required this.rgbSliceByteLength,
    required this.alphaSliceByteOffset,
    required this.alphaSliceByteLength,
  });

  final int flags;
  final int rgbSliceByteOffset;
  final int rgbSliceByteLength;
  final int alphaSliceByteOffset;
  final int alphaSliceByteLength;
}

/// Decodes ETC1S slices of one BasisLZ KTX2 file. Construction parses the
/// supercompression global data (codebooks and models); [decodeImageRgba8]
/// then decodes any image against them.
class Etc1sTranscoder {
  Etc1sTranscoder(Uint8List sgd, int imageCount) {
    const headerSize = 20;
    const imageDescSize = 20;
    if (sgd.length < headerSize + imageDescSize * imageCount) {
      throw const FormatException('BasisLZ global data is too short');
    }
    final data = ByteData.sublistView(sgd);
    final endpointCount = data.getUint16(0, Endian.little);
    final selectorCount = data.getUint16(2, Endian.little);
    final endpointsByteLength = data.getUint32(4, Endian.little);
    final selectorsByteLength = data.getUint32(8, Endian.little);
    final tablesByteLength = data.getUint32(12, Endian.little);
    if (endpointCount == 0 ||
        selectorCount == 0 ||
        endpointsByteLength == 0 ||
        selectorsByteLength == 0 ||
        tablesByteLength == 0) {
      throw const FormatException('BasisLZ global data is empty');
    }
    var offset = headerSize;
    for (var i = 0; i < imageCount; i++) {
      imageDescs.add(
        Etc1sImageDesc(
          flags: data.getUint32(offset, Endian.little),
          rgbSliceByteOffset: data.getUint32(offset + 4, Endian.little),
          rgbSliceByteLength: data.getUint32(offset + 8, Endian.little),
          alphaSliceByteOffset: data.getUint32(offset + 12, Endian.little),
          alphaSliceByteLength: data.getUint32(offset + 16, Endian.little),
        ),
      );
      offset += imageDescSize;
    }
    if (offset + endpointsByteLength + selectorsByteLength + tablesByteLength >
        sgd.length) {
      throw const FormatException('BasisLZ global data sections overflow');
    }
    final endpointsData = Uint8List.sublistView(
      sgd,
      offset,
      offset + endpointsByteLength,
    );
    offset += endpointsByteLength;
    final selectorsData = Uint8List.sublistView(
      sgd,
      offset,
      offset + selectorsByteLength,
    );
    offset += selectorsByteLength;
    final tablesData = Uint8List.sublistView(
      sgd,
      offset,
      offset + tablesByteLength,
    );
    _decodeEndpoints(endpointCount, endpointsData);
    _decodeSelectors(selectorCount, selectorsData);
    _decodeTables(tablesData);
  }

  final imageDescs = <Etc1sImageDesc>[];

  /// Endpoint codebook, 4 bytes per entry: r5, g5, b5, inten.
  late final Uint8List _endpoints;
  late final int _numEndpoints;

  /// Selector codebook, 4 bytes per entry, one byte per texel row (2 bits per
  /// texel, x0 in the low bits).
  late final Uint8List _selectors;
  late final int _numSelectors;

  late final _HuffTable _endpointPredModel;
  late final _HuffTable _deltaEndpointModel;
  late final _HuffTable _selectorModel;
  late final _HuffTable _selectorHistoryBufRleModel;
  late final int _selectorHistoryBufSize;

  void _decodeEndpoints(int numEndpoints, Uint8List data) {
    final reader = _BitReader(data);
    final color5DeltaModel0 = reader.readHuffTable();
    final color5DeltaModel1 = reader.readHuffTable();
    final color5DeltaModel2 = reader.readHuffTable();
    final intenDeltaModel = reader.readHuffTable();
    if (color5DeltaModel0.isEmpty ||
        color5DeltaModel1.isEmpty ||
        color5DeltaModel2.isEmpty ||
        intenDeltaModel.isEmpty) {
      throw const FormatException('BasisLZ endpoint models are empty');
    }
    final grayscale = reader.getBits(1) != 0;
    _numEndpoints = numEndpoints;
    _endpoints = Uint8List(numEndpoints * 4);
    final prevColor5 = [16, 16, 16];
    var prevInten = 0;
    for (var i = 0; i < numEndpoints; i++) {
      final intenDelta = reader.decodeHuffman(intenDeltaModel);
      prevInten = (intenDelta + prevInten) & 7;
      _endpoints[i * 4 + 3] = prevInten;
      for (var c = 0; c < (grayscale ? 1 : 3); c++) {
        final int delta;
        if (prevColor5[c] <= 9) {
          delta = reader.decodeHuffman(color5DeltaModel0);
        } else if (prevColor5[c] <= 21) {
          delta = reader.decodeHuffman(color5DeltaModel1);
        } else {
          delta = reader.decodeHuffman(color5DeltaModel2);
        }
        final v = (prevColor5[c] + delta) & 31;
        _endpoints[i * 4 + c] = v;
        prevColor5[c] = v;
      }
      if (grayscale) {
        _endpoints[i * 4 + 1] = _endpoints[i * 4];
        _endpoints[i * 4 + 2] = _endpoints[i * 4];
      }
    }
  }

  void _decodeSelectors(int numSelectors, Uint8List data) {
    final reader = _BitReader(data);
    _numSelectors = numSelectors;
    _selectors = Uint8List(numSelectors * 4);
    final usedGlobalCb = reader.getBits(1) == 1;
    if (usedGlobalCb) {
      // Removed from the format; no modern encoder emits these.
      throw const FormatException(
        'BasisLZ global selector codebooks are unsupported',
      );
    }
    final usedHybridCb = reader.getBits(1) == 1;
    if (usedHybridCb) {
      throw const FormatException(
        'BasisLZ hybrid selector codebooks are unsupported',
      );
    }
    final usedRawEncoding = reader.getBits(1) == 1;
    if (usedRawEncoding) {
      for (var i = 0; i < numSelectors * 4; i++) {
        _selectors[i] = reader.getBits(8);
      }
      return;
    }
    final deltaSelectorPalModel = reader.readHuffTable();
    if (numSelectors > 1 && deltaSelectorPalModel.isEmpty) {
      throw const FormatException('BasisLZ selector model is empty');
    }
    final prevBytes = [0, 0, 0, 0];
    for (var i = 0; i < numSelectors; i++) {
      for (var j = 0; j < 4; j++) {
        final cur = i == 0
            ? reader.getBits(8)
            : reader.decodeHuffman(deltaSelectorPalModel) ^ prevBytes[j];
        prevBytes[j] = cur;
        _selectors[i * 4 + j] = cur;
      }
    }
  }

  void _decodeTables(Uint8List data) {
    final reader = _BitReader(data);
    _endpointPredModel = reader.readHuffTable();
    _deltaEndpointModel = reader.readHuffTable();
    _selectorModel = reader.readHuffTable();
    _selectorHistoryBufRleModel = reader.readHuffTable();
    if (_endpointPredModel.isEmpty ||
        _deltaEndpointModel.isEmpty ||
        _selectorModel.isEmpty ||
        _selectorHistoryBufRleModel.isEmpty) {
      throw const FormatException('BasisLZ slice models are empty');
    }
    _selectorHistoryBufSize = reader.getBits(13);
    if (_selectorHistoryBufSize == 0) {
      throw const FormatException('BasisLZ selector history buffer is empty');
    }
  }

  /// Decodes image [imageIndex] from its mip [levelData] into a [width] x
  /// [height] RGBA8 image, combining the RGB slice with the alpha slice when
  /// one is present (otherwise alpha is opaque).
  Uint8List decodeImageRgba8(
    Uint8List levelData,
    int imageIndex,
    int width,
    int height,
  ) {
    if (imageIndex >= imageDescs.length) {
      throw const FormatException('BasisLZ image index out of range');
    }
    final desc = imageDescs[imageIndex];
    final out = Uint8List(width * height * 4);
    Uint8List slice(int offset, int length) {
      if (offset + length > levelData.length) {
        throw const FormatException('BasisLZ slice overflows its mip level');
      }
      return Uint8List.sublistView(levelData, offset, offset + length);
    }

    final hasAlphaSlice = desc.alphaSliceByteLength > 0;
    if (hasAlphaSlice) {
      _decodeSlice(
        slice(desc.alphaSliceByteOffset, desc.alphaSliceByteLength),
        out,
        width,
        height,
        _SliceTarget.alpha,
      );
    }
    _decodeSlice(
      slice(desc.rgbSliceByteOffset, desc.rgbSliceByteLength),
      out,
      width,
      height,
      hasAlphaSlice ? _SliceTarget.rgb : _SliceTarget.rgba,
    );
    return out;
  }

  void _decodeSlice(
    Uint8List sliceData,
    Uint8List out,
    int width,
    int height,
    _SliceTarget target,
  ) {
    final numBlocksX = (width + 3) >> 2;
    final numBlocksY = (height + 3) >> 2;
    final totalBlocks = numBlocksX * numBlocksY;
    final reader = _BitReader(sliceData);

    // Approximate move-to-front history of recent selector indices.
    final historyBuf = Int32List(_selectorHistoryBufSize);
    var historyRover = _selectorHistoryBufSize >> 1;
    final selectorHistoryBufRleSymbolIndex =
        _numSelectors + _selectorHistoryBufSize;
    var curSelectorRleCount = 0;

    // Endpoint predictions carry across 2x2 block quads; [0]/[1] hold the
    // even/odd block rows' pred bits and endpoint indices.
    final predBits = [Uint8List(numBlocksX), Uint8List(numBlocksX)];
    final endpointIndices = [Uint16List(numBlocksX), Uint16List(numBlocksX)];
    var curPredBits = 0;
    var prevEndpointPredSym = 0;
    var endpointPredRepeatCount = 0;
    var prevEndpointIndex = 0;

    final blockColors = Int32List(16);
    for (var blockY = 0; blockY < numBlocksY; blockY++) {
      final curRow = blockY & 1;
      for (var blockX = 0; blockX < numBlocksX; blockX++) {
        if ((blockX & 1) == 0) {
          if ((blockY & 1) == 0) {
            if (endpointPredRepeatCount > 0) {
              endpointPredRepeatCount--;
              curPredBits = prevEndpointPredSym;
            } else {
              curPredBits = reader.decodeHuffman(_endpointPredModel);
              if (curPredBits == _endpointPredRepeatLastSymbol) {
                endpointPredRepeatCount =
                    reader.decodeVlc(_endpointPredCountVlcBits) +
                    _endpointPredMinRepeatCount -
                    1;
                curPredBits = prevEndpointPredSym;
              } else {
                prevEndpointPredSym = curPredBits;
              }
            }
            predBits[curRow ^ 1][blockX] = curPredBits >> 4;
          } else {
            curPredBits = predBits[curRow][blockX];
          }
        }

        int endpointIndex;
        var selectorIndex = 0;
        final pred = curPredBits & 3;
        curPredBits >>= 2;
        if (pred == 0) {
          if (blockX == 0) {
            throw const FormatException('BasisLZ left prediction at column 0');
          }
          endpointIndex = prevEndpointIndex;
        } else if (pred == 1) {
          if (blockY == 0) {
            throw const FormatException('BasisLZ upper prediction at row 0');
          }
          endpointIndex = endpointIndices[curRow ^ 1][blockX];
        } else if (pred == 2) {
          if (blockX == 0 || blockY == 0) {
            throw const FormatException('BasisLZ diagonal prediction at edge');
          }
          endpointIndex = endpointIndices[curRow ^ 1][blockX - 1];
        } else {
          final deltaSym = reader.decodeHuffman(_deltaEndpointModel);
          endpointIndex = deltaSym + prevEndpointIndex;
          if (endpointIndex >= _numEndpoints) {
            endpointIndex -= _numEndpoints;
          }
        }
        endpointIndices[curRow][blockX] = endpointIndex;
        prevEndpointIndex = endpointIndex;

        int selectorSym;
        if (curSelectorRleCount > 0) {
          curSelectorRleCount--;
          selectorSym = _numSelectors;
        } else {
          selectorSym = reader.decodeHuffman(_selectorModel);
          if (selectorSym == selectorHistoryBufRleSymbolIndex) {
            final runSym = reader.decodeHuffman(_selectorHistoryBufRleModel);
            if (runSym == _selectorHistoryBufRleCountTotal - 1) {
              curSelectorRleCount =
                  reader.decodeVlc(7) + _selectorHistoryBufRleCountThresh;
            } else {
              curSelectorRleCount = runSym + _selectorHistoryBufRleCountThresh;
            }
            if (curSelectorRleCount > totalBlocks) {
              throw const FormatException('BasisLZ selector run is too long');
            }
            selectorSym = _numSelectors;
            curSelectorRleCount--;
          }
        }
        if (selectorSym >= _numSelectors) {
          final historyIndex = selectorSym - _numSelectors;
          if (historyIndex >= historyBuf.length) {
            throw const FormatException(
              'BasisLZ selector history index out of range',
            );
          }
          selectorIndex = historyBuf[historyIndex];
          if (historyIndex != 0) {
            // Approximate move to front: swap toward the front slot.
            final half = historyIndex >> 1;
            final x = historyBuf[half];
            historyBuf[half] = historyBuf[historyIndex];
            historyBuf[historyIndex] = x;
          }
        } else {
          selectorIndex = selectorSym;
          historyBuf[historyRover++] = selectorIndex;
          if (historyRover == historyBuf.length) {
            historyRover = historyBuf.length >> 1;
          }
        }
        if (endpointIndex >= _numEndpoints || selectorIndex >= _numSelectors) {
          throw const FormatException('BasisLZ codebook index out of range');
        }

        _writeBlock(
          out,
          width,
          height,
          blockX,
          blockY,
          endpointIndex,
          selectorIndex,
          target,
          blockColors,
        );
      }
    }
  }

  void _writeBlock(
    Uint8List out,
    int width,
    int height,
    int blockX,
    int blockY,
    int endpointIndex,
    int selectorIndex,
    _SliceTarget target,
    Int32List blockColors,
  ) {
    final inten = _etc1IntenTables[_endpoints[endpointIndex * 4 + 3]];
    // 5-bit endpoints expand to 8 bits; alpha slices use the green channel.
    if (target == _SliceTarget.alpha) {
      final g5 = _endpoints[endpointIndex * 4 + 1];
      final g = (g5 << 3) | (g5 >> 2);
      for (var s = 0; s < 4; s++) {
        blockColors[s] = _clamp255(g + inten[s]);
      }
    } else {
      for (var c = 0; c < 3; c++) {
        final v5 = _endpoints[endpointIndex * 4 + c];
        final v = (v5 << 3) | (v5 >> 2);
        for (var s = 0; s < 4; s++) {
          blockColors[s * 4 + c] = _clamp255(v + inten[s]);
        }
      }
    }
    final maxX = width - blockX * 4 < 4 ? width - blockX * 4 : 4;
    final maxY = height - blockY * 4 < 4 ? height - blockY * 4 : 4;
    for (var y = 0; y < maxY; y++) {
      final rowSelectors = _selectors[selectorIndex * 4 + y];
      var dst = ((blockY * 4 + y) * width + blockX * 4) * 4;
      for (var x = 0; x < maxX; x++) {
        final s = (rowSelectors >> (x * 2)) & 3;
        switch (target) {
          case _SliceTarget.alpha:
            out[dst + 3] = blockColors[s];
          case _SliceTarget.rgb:
            out[dst] = blockColors[s * 4];
            out[dst + 1] = blockColors[s * 4 + 1];
            out[dst + 2] = blockColors[s * 4 + 2];
          case _SliceTarget.rgba:
            out[dst] = blockColors[s * 4];
            out[dst + 1] = blockColors[s * 4 + 1];
            out[dst + 2] = blockColors[s * 4 + 2];
            out[dst + 3] = 255;
        }
        dst += 4;
      }
    }
  }
}

enum _SliceTarget { rgba, rgb, alpha }

int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
