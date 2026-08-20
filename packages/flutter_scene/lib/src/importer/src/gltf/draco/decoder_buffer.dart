// Byte and bit readers for the Draco bitstream (little-endian). See the Draco
// Bitstream Specification, "Conventions" and "Core Functions" sections
// (https://google.github.io/draco/spec/).
//
// All arithmetic stays within 32-bit-safe bitwise operations so the decoder
// behaves identically under dart2js (53-bit ints, 32-bit bitwise semantics).

import 'dart:typed_data';

/// Packs a bitstream major/minor version pair into a comparable value.
int dracoBitstreamVersion(int major, int minor) =>
    ((major & 0xFF) << 8) | (minor & 0xFF);

/// Wraps [x] to a signed 32-bit integer, matching C++ int32 overflow.
int toInt32(int x) {
  final m = x & 0xFFFFFFFF;
  return m >= 0x80000000 ? m - 0x100000000 : m;
}

final Float32List _f32Scratch = Float32List(1);

/// Rounds [x] to float32 precision, mirroring the reference decoder's
/// single-precision arithmetic so dequantized output is bit-identical.
double toFloat32(double x) {
  _f32Scratch[0] = x;
  return _f32Scratch[0];
}

/// Zigzag-decodes an unsigned symbol to a signed value.
int symbolToSignedInt(int val) {
  final result = val >> 1;
  return (val & 1) == 0 ? result : -result - 1;
}

/// Thrown internally and surfaced as a [FormatException] by the entry point.
FormatException dracoError(String message) =>
    FormatException('Draco decode error, $message');

/// Reader over a Draco byte stream with an optional LSB-first bit mode.
class DecoderBuffer {
  DecoderBuffer(this._data, [this.bitstreamVersion = 0])
    : _view = ByteData.sublistView(_data);

  final Uint8List _data;
  final ByteData _view;
  int _pos = 0;
  int bitstreamVersion;

  // Bit-mode state; bit offset is relative to _bitStart.
  bool _bitMode = false;
  int _bitStart = 0;
  int _bitOffset = 0;

  int get position => _pos;
  int get remainingSize => _data.length - _pos;
  bool get bitDecoderActive => _bitMode;

  /// A view of the not-yet-decoded bytes.
  Uint8List get dataHead => Uint8List.sublistView(_data, _pos);

  void _require(int bytes) {
    if (_pos + bytes > _data.length) {
      throw dracoError('stream truncated');
    }
  }

  int decodeUint8() {
    _require(1);
    return _data[_pos++];
  }

  int decodeInt8() {
    _require(1);
    return _view.getInt8(_pos++);
  }

  int decodeUint16() {
    _require(2);
    final v = _view.getUint16(_pos, Endian.little);
    _pos += 2;
    return v;
  }

  int decodeUint32() {
    _require(4);
    final v = _view.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  int decodeInt32() {
    _require(4);
    final v = _view.getInt32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  double decodeFloat32() {
    _require(4);
    final v = _view.getFloat32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  Uint8List decodeBytes(int size) {
    _require(size);
    final v = Uint8List.sublistView(_data, _pos, _pos + size);
    _pos += size;
    return v;
  }

  void advance(int bytes) {
    if (bytes < 0 || _pos + bytes > _data.length) {
      throw dracoError('stream truncated');
    }
    _pos += bytes;
  }

  /// Unsigned LEB128-style varint (MSB continuation). Values are built with
  /// arithmetic (not shifts) so results above 32 bits stay exact on dart2js.
  int decodeVarint() {
    var byte = decodeUint8();
    if ((byte & 0x80) == 0) {
      return byte;
    }
    final bytes = <int>[byte & 0x7F];
    for (var i = 1; i < 10; i++) {
      byte = decodeUint8();
      if ((byte & 0x80) != 0) {
        bytes.add(byte & 0x7F);
      } else {
        bytes.add(byte);
        var result = bytes[bytes.length - 1];
        for (var k = bytes.length - 2; k >= 0; k--) {
          result = result * 128 + bytes[k];
        }
        return result;
      }
    }
    throw dracoError('varint too long');
  }

  /// Enters bit-decoding mode. When [sizePrefixed] the encoded byte size of
  /// the bit section is read first (varint in bitstream 2.2) and returned.
  int startBitDecoding({required bool sizePrefixed}) {
    var size = 0;
    if (sizePrefixed) {
      size = decodeVarint();
    }
    _bitMode = true;
    _bitStart = _pos;
    _bitOffset = 0;
    return size;
  }

  void endBitDecoding() {
    _bitMode = false;
    _pos = _bitStart + ((_bitOffset + 7) >> 3);
    if (_pos > _data.length) {
      throw dracoError('stream truncated');
    }
  }

  /// Reads [nbits] (0..32) least-significant-bit-first bits.
  int decodeLeastSignificantBits32(int nbits) {
    assert(_bitMode);
    var value = 0;
    var bitsRead = 0;
    var offset = _bitOffset;
    while (bitsRead < nbits) {
      final byteIndex = _bitStart + (offset >> 3);
      if (byteIndex >= _data.length) {
        throw dracoError('bitstream truncated');
      }
      final bitShift = offset & 7;
      final bitsAvailable = 8 - bitShift;
      final bitsNeeded = nbits - bitsRead;
      final bitsToRead = bitsAvailable < bitsNeeded
          ? bitsAvailable
          : bitsNeeded;
      final mask = (1 << bitsToRead) - 1;
      value |= ((_data[byteIndex] >> bitShift) & mask) << bitsRead;
      bitsRead += bitsToRead;
      offset += bitsToRead;
    }
    _bitOffset = offset;
    return value;
  }
}
