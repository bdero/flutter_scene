// rANS entropy decoders for the Draco bitstream. See the Draco Bitstream
// Specification, "Rans Decoding" (https://google.github.io/draco/spec/).
//
// All state arithmetic stays below 2^31 for bitwise steps (multiplication
// results stay below 2^53) so the decoders run identically under dart2js.

import 'dart:typed_data';

import 'decoder_buffer.dart';

const int _ansP8Precision = 256;
const int _ansLBase = 4096;
const int _ansIOBase = 256;

/// Binary rANS decoder (`RAnsBitDecoder` in the reference implementation).
/// Decodes bits encoded with an adaptive zero-probability byte.
class RAnsBitDecoder {
  Uint8List _buf = Uint8List(0);
  int _bufOffset = 0;
  int _state = 0;
  int _probZero = 0;
  int _p = 0;

  void startDecoding(DecoderBuffer buffer) {
    _probZero = buffer.decodeUint8();
    _p = _ansP8Precision - _probZero;
    final sizeInBytes = buffer.decodeVarint();
    if (sizeInBytes > buffer.remainingSize) {
      throw dracoError('rANS bit stream truncated');
    }
    final data = buffer.dataHead;
    buffer.advance(sizeInBytes);
    _readInit(data, sizeInBytes);
  }

  void _readInit(Uint8List buf, int offset) {
    if (offset < 1) {
      throw dracoError('empty rANS bit stream');
    }
    _buf = buf;
    final x = buf[offset - 1] >> 6;
    if (x == 0) {
      _bufOffset = offset - 1;
      _state = buf[offset - 1] & 0x3F;
    } else if (x == 1) {
      if (offset < 2) throw dracoError('rANS bit stream truncated');
      _bufOffset = offset - 2;
      _state = (buf[offset - 2] | (buf[offset - 1] << 8)) & 0x3FFF;
    } else if (x == 2) {
      if (offset < 3) throw dracoError('rANS bit stream truncated');
      _bufOffset = offset - 3;
      _state =
          (buf[offset - 3] | (buf[offset - 2] << 8) | (buf[offset - 1] << 16)) &
          0x3FFFFF;
    } else {
      throw dracoError('invalid rANS bit stream state');
    }
    _state += _ansLBase;
    if (_state >= _ansLBase * _ansIOBase) {
      throw dracoError('invalid rANS bit stream state');
    }
  }

  bool decodeNextBit() {
    if (_state < _ansLBase && _bufOffset > 0) {
      _state = (_state << 8) | _buf[--_bufOffset];
    }
    final x = _state;
    final quotient = x >> 8;
    final remainder = x & 0xFF;
    final xn = quotient * _p;
    if (remainder < _p) {
      _state = xn + remainder;
      return true;
    }
    _state = x - xn - _p;
    return false;
  }
}

int _computeRAnsPrecisionBits(int symbolsBitLength) {
  final unclamped = (3 * symbolsBitLength) ~/ 2;
  if (unclamped < 12) return 12;
  if (unclamped > 20) return 20;
  return unclamped;
}

/// Multi-symbol rANS decoder with an explicit probability table
/// (`RAnsSymbolDecoder` in the reference implementation).
class RAnsSymbolDecoder {
  RAnsSymbolDecoder(int uniqueSymbolsBitLength)
    : _precisionBits = _computeRAnsPrecisionBits(uniqueSymbolsBitLength),
      _precision = 1 << _computeRAnsPrecisionBits(uniqueSymbolsBitLength);

  final int _precisionBits;
  final int _precision;
  int numSymbols = 0;

  late Uint32List _probTable;
  late Uint32List _cumProbTable;
  late Uint32List _lutTable;

  Uint8List _buf = Uint8List(0);
  int _bufOffset = 0;
  int _state = 0;
  late final int _lBase = _precision * 4;

  /// Reads the probability table.
  void create(DecoderBuffer buffer) {
    if (buffer.bitstreamVersion == 0) {
      throw dracoError('missing bitstream version');
    }
    numSymbols = buffer.decodeVarint();
    if (numSymbols ~/ 64 > buffer.remainingSize) {
      throw dracoError('unreasonable symbol count');
    }
    final probs = Uint32List(numSymbols);
    for (var i = 0; i < numSymbols; i++) {
      final probData = buffer.decodeUint8();
      final token = probData & 3;
      if (token == 3) {
        // Run of zero-probability symbols.
        final offset = probData >> 2;
        if (i + offset >= numSymbols) {
          throw dracoError('invalid probability table');
        }
        i += offset;
      } else {
        var prob = probData >> 2;
        for (var b = 0; b < token; b++) {
          final extra = buffer.decodeUint8();
          prob |= extra << (8 * (b + 1) - 2);
        }
        probs[i] = prob;
      }
    }
    _buildLookupTable(probs);
  }

  void _buildLookupTable(Uint32List probs) {
    _probTable = probs;
    _cumProbTable = Uint32List(numSymbols);
    _lutTable = Uint32List(_precision);
    var cumProb = 0;
    for (var i = 0; i < numSymbols; i++) {
      final prob = probs[i];
      _cumProbTable[i] = cumProb;
      cumProb += prob;
      if (cumProb > _precision) {
        throw dracoError('invalid probability table');
      }
      _lutTable.fillRange(cumProb - prob, cumProb, i);
    }
    if (cumProb != _precision) {
      throw dracoError('invalid probability table');
    }
  }

  void startDecoding(DecoderBuffer buffer) {
    final bytesEncoded = buffer.decodeVarint();
    if (bytesEncoded > buffer.remainingSize) {
      throw dracoError('rANS stream truncated');
    }
    final data = buffer.dataHead;
    buffer.advance(bytesEncoded);
    _readInit(data, bytesEncoded);
  }

  void _readInit(Uint8List buf, int offset) {
    if (offset < 1) {
      throw dracoError('empty rANS stream');
    }
    _buf = buf;
    final x = buf[offset - 1] >> 6;
    if (x == 0) {
      _bufOffset = offset - 1;
      _state = buf[offset - 1] & 0x3F;
    } else if (x == 1) {
      if (offset < 2) throw dracoError('rANS stream truncated');
      _bufOffset = offset - 2;
      _state = (buf[offset - 2] | (buf[offset - 1] << 8)) & 0x3FFF;
    } else if (x == 2) {
      if (offset < 3) throw dracoError('rANS stream truncated');
      _bufOffset = offset - 3;
      _state =
          (buf[offset - 3] | (buf[offset - 2] << 8) | (buf[offset - 1] << 16)) &
          0x3FFFFF;
    } else {
      if (offset < 4) throw dracoError('rANS stream truncated');
      _bufOffset = offset - 4;
      _state =
          (buf[offset - 4] |
              (buf[offset - 3] << 8) |
              (buf[offset - 2] << 16) |
              (buf[offset - 1] << 24)) &
          0x3FFFFFFF;
    }
    _state += _lBase;
    if (_state >= _lBase * _ansIOBase) {
      throw dracoError('invalid rANS stream state');
    }
  }

  int decodeSymbol() {
    var state = _state;
    var bufOffset = _bufOffset;
    while (state < _lBase && bufOffset > 0) {
      state = (state << 8) | _buf[--bufOffset];
    }
    final remainder = state & (_precision - 1);
    final symbol = _lutTable[remainder];
    _state =
        (state >> _precisionBits) * _probTable[symbol] +
        remainder -
        _cumProbTable[symbol];
    _bufOffset = bufOffset;
    return symbol;
  }

  /// Batch-decodes [count] symbols into [out].
  void decodeSymbols(Uint32List out, int count) {
    final buf = _buf;
    final lBase = _lBase;
    final precisionBits = _precisionBits;
    final precisionMask = _precision - 1;
    final lut = _lutTable;
    final probs = _probTable;
    final cumProbs = _cumProbTable;
    var state = _state;
    var bufOffset = _bufOffset;
    for (var i = 0; i < count; i++) {
      while (state < lBase && bufOffset > 0) {
        state = (state << 8) | buf[--bufOffset];
      }
      final remainder = state & precisionMask;
      final symbol = lut[remainder];
      out[i] = symbol;
      state =
          (state >> precisionBits) * probs[symbol] +
          remainder -
          cumProbs[symbol];
    }
    _state = state;
    _bufOffset = bufOffset;
  }
}
