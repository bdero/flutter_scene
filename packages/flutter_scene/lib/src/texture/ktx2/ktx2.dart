// A pure-Dart reader and writer for the KTX2 container (Khronos KTX 2.0).
//
// This is container plumbing only: it moves level payloads, the data format
// descriptor, key/value data, and supercompression global data in and out of
// the byte layout. It does not encode, decode, or transcode pixels; the codec
// layers sit on top and treat a level's bytes as opaque.
//
// Offsets in KTX2 are 64-bit. dart2js has no 64-bit integers, so every 64-bit
// field is read and written as two 32-bit words here. Files larger than 4 GiB
// (a non-zero high word) are rejected rather than silently truncated.

import 'dart:convert';
import 'dart:typed_data';

/// Supercompression schemes defined by the KTX2 specification. A level's stored
/// bytes are compressed with this scheme; [Ktx2Supercompression.none] stores
/// them verbatim.
enum Ktx2Supercompression {
  none(0),
  basisLz(1),
  zstandard(2),
  zlib(3);

  const Ktx2Supercompression(this.value);

  /// The on-disk integer for the `supercompressionScheme` header field.
  final int value;

  static Ktx2Supercompression fromValue(int value) {
    for (final scheme in Ktx2Supercompression.values) {
      if (scheme.value == value) return scheme;
    }
    throw Ktx2FormatException('Unknown supercompression scheme: $value');
  }
}

/// One mip level's payload. [data] is the bytes as stored (supercompressed when
/// the texture's scheme is not [Ktx2Supercompression.none]);
/// [uncompressedByteLength] is the size after decompression, equal to
/// `data.length` when the scheme is none.
class Ktx2Level {
  Ktx2Level({required this.data, int? uncompressedByteLength})
    : uncompressedByteLength = uncompressedByteLength ?? data.length;

  final Uint8List data;
  final int uncompressedByteLength;
}

/// An in-memory KTX2 texture: the header fields plus the four byte sections
/// (level payloads, data format descriptor, key/value data, supercompression
/// global data). Levels are ordered with index 0 as the base (largest) level,
/// matching the KTX2 level index order.
class Ktx2Texture {
  Ktx2Texture({
    required this.vkFormat,
    this.typeSize = 1,
    required this.pixelWidth,
    this.pixelHeight = 0,
    this.pixelDepth = 0,
    this.layerCount = 0,
    this.faceCount = 1,
    required this.levels,
    this.supercompression = Ktx2Supercompression.none,
    Uint8List? dataFormatDescriptor,
    this.keyValues = const {},
    Uint8List? supercompressionGlobalData,
    this.levelAlignment = 16,
  }) : assert(levels.isNotEmpty, 'A KTX2 texture needs at least one level'),
       assert(faceCount == 1 || faceCount == 6, 'faceCount must be 1 or 6'),
       assert(levelAlignment > 0, 'levelAlignment must be positive'),
       dataFormatDescriptor =
           dataFormatDescriptor ?? _nullDataFormatDescriptor(),
       supercompressionGlobalData = supercompressionGlobalData ?? Uint8List(0);

  /// Vulkan format enum (`VK_FORMAT_*`). UASTC and other Basis payloads use
  /// `VK_FORMAT_UNDEFINED` (0) and rely on the data format descriptor.
  final int vkFormat;

  /// Size in bytes of the format's underlying type (1 for byte-typed and
  /// block-compressed formats).
  final int typeSize;

  final int pixelWidth;

  /// 0 for a 1D texture, otherwise the height.
  final int pixelHeight;

  /// 0 for a non-3D texture, otherwise the depth.
  final int pixelDepth;

  /// 0 for a non-array texture, otherwise the layer count.
  final int layerCount;

  /// 1 for a normal texture, 6 for a cube map.
  final int faceCount;

  /// Mip levels, index 0 = base (largest).
  final List<Ktx2Level> levels;

  final Ktx2Supercompression supercompression;

  /// The data format descriptor block, stored opaquely. Defaults to a minimal
  /// "null" descriptor (just a total-size word); a format-accurate descriptor
  /// is the codec layer's responsibility.
  // TODO(ktx2): build a real basic DFD (Khronos basic descriptor block) for the
  // formats we emit (UASTC, rgba8, the BC/ETC2/ASTC families) once the codec
  // lands, so the files validate against KTX-Software.
  final Uint8List dataFormatDescriptor;

  /// Key/value metadata. Keys are UTF-8; values are arbitrary bytes. Written in
  /// codepoint-sorted key order per the specification.
  final Map<String, Uint8List> keyValues;

  /// Supercompression global data (used by BasisLZ); empty for none/zstd/zlib.
  final Uint8List supercompressionGlobalData;

  /// Required alignment for mip level data when not supercompressed
  /// (`lcm(texelBlockSize, 4)`). 16 covers UASTC and the 4x4 block formats; a
  /// caller emitting rgba8 (texel block size 4) can pass 4.
  final int levelAlignment;
}

/// Thrown when bytes are not a valid KTX2 file or exceed what this reader
/// supports (e.g. a 64-bit offset that does not fit in a web-safe integer).
class Ktx2FormatException implements Exception {
  Ktx2FormatException(this.message);
  final String message;
  @override
  String toString() => 'Ktx2FormatException: $message';
}

/// The 12-byte KTX2 file identifier: `«KTX 20»\r\n\x1A\n`.
const List<int> ktx2Identifier = <int>[
  0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A, //
];

const int _headerEnd = 80; // identifier(12) + header(36) + index(32)
const int _levelIndexEntrySize = 24; // three 64-bit fields

Uint8List _nullDataFormatDescriptor() {
  // A descriptor consisting only of its own total-size field (4 bytes).
  final dfd = Uint8List(4);
  ByteData.sublistView(dfd).setUint32(0, 4, Endian.little);
  return dfd;
}

int _align(int value, int alignment) =>
    (value + alignment - 1) ~/ alignment * alignment;

/// Reads a 64-bit little-endian field as two 32-bit words. Rejects values that
/// do not fit in a web-safe integer (high word non-zero).
int _readU64(ByteData data, int offset) {
  final low = data.getUint32(offset, Endian.little);
  final high = data.getUint32(offset + 4, Endian.little);
  if (high != 0) {
    throw Ktx2FormatException(
      'Offset/length at byte $offset exceeds the 4 GiB supported range',
    );
  }
  return low;
}

/// Writes a web-safe integer as a 64-bit little-endian field (high word zero).
void _writeU64(ByteData data, int offset, int value) {
  data.setUint32(offset, value, Endian.little);
  data.setUint32(offset + 4, 0, Endian.little);
}

/// Parses [bytes] as a KTX2 file. Throws [Ktx2FormatException] on malformed
/// input.
Ktx2Texture readKtx2(Uint8List bytes) {
  if (bytes.length < _headerEnd) {
    throw Ktx2FormatException('Too short to be a KTX2 file');
  }
  for (var i = 0; i < ktx2Identifier.length; i++) {
    if (bytes[i] != ktx2Identifier[i]) {
      throw Ktx2FormatException('Bad KTX2 identifier');
    }
  }
  final data = ByteData.sublistView(bytes);
  final vkFormat = data.getUint32(12, Endian.little);
  final typeSize = data.getUint32(16, Endian.little);
  final pixelWidth = data.getUint32(20, Endian.little);
  final pixelHeight = data.getUint32(24, Endian.little);
  final pixelDepth = data.getUint32(28, Endian.little);
  final layerCount = data.getUint32(32, Endian.little);
  final faceCount = data.getUint32(36, Endian.little);
  final levelCount = data.getUint32(40, Endian.little);
  final supercompression = Ktx2Supercompression.fromValue(
    data.getUint32(44, Endian.little),
  );

  final dfdByteOffset = data.getUint32(48, Endian.little);
  final dfdByteLength = data.getUint32(52, Endian.little);
  final kvdByteOffset = data.getUint32(56, Endian.little);
  final kvdByteLength = data.getUint32(60, Endian.little);
  final sgdByteOffset = _readU64(data, 64);
  final sgdByteLength = _readU64(data, 72);

  final storedLevelCount = levelCount == 0 ? 1 : levelCount;
  final levelIndexEnd = _headerEnd + _levelIndexEntrySize * storedLevelCount;
  if (bytes.length < levelIndexEnd) {
    throw Ktx2FormatException('Truncated level index');
  }
  final levels = <Ktx2Level>[];
  for (var i = 0; i < storedLevelCount; i++) {
    final entry = _headerEnd + _levelIndexEntrySize * i;
    final byteOffset = _readU64(data, entry);
    final byteLength = _readU64(data, entry + 8);
    final uncompressedByteLength = _readU64(data, entry + 16);
    levels.add(
      Ktx2Level(
        data: _slice(bytes, byteOffset, byteLength),
        uncompressedByteLength: uncompressedByteLength,
      ),
    );
  }

  final dfd = dfdByteLength == 0
      ? _nullDataFormatDescriptor()
      : _slice(bytes, dfdByteOffset, dfdByteLength);
  final keyValues = kvdByteLength == 0
      ? <String, Uint8List>{}
      : _decodeKeyValues(_slice(bytes, kvdByteOffset, kvdByteLength));
  final sgd = sgdByteLength == 0
      ? Uint8List(0)
      : _slice(bytes, sgdByteOffset, sgdByteLength);

  return Ktx2Texture(
    vkFormat: vkFormat,
    typeSize: typeSize,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    pixelDepth: pixelDepth,
    layerCount: layerCount,
    faceCount: faceCount,
    levels: levels,
    supercompression: supercompression,
    dataFormatDescriptor: dfd,
    keyValues: keyValues,
    supercompressionGlobalData: sgd,
  );
}

/// Serializes [texture] to KTX2 bytes.
Uint8List writeKtx2(Ktx2Texture texture) {
  final levels = texture.levels;
  final dfd = texture.dataFormatDescriptor;
  final kvd = _encodeKeyValues(texture.keyValues);
  final sgd = texture.supercompressionGlobalData;
  final levelAlignment = texture.supercompression == Ktx2Supercompression.none
      ? texture.levelAlignment
      : 1;

  // Lay the file out, computing every offset before writing.
  var cursor = _headerEnd + _levelIndexEntrySize * levels.length;

  final dfdOffset = dfd.isEmpty ? 0 : _align(cursor, 4);
  cursor = dfd.isEmpty ? cursor : dfdOffset + dfd.length;

  final kvdOffset = kvd.isEmpty ? 0 : _align(cursor, 4);
  cursor = kvd.isEmpty ? cursor : kvdOffset + kvd.length;

  final sgdOffset = sgd.isEmpty ? 0 : _align(cursor, 8);
  cursor = sgd.isEmpty ? cursor : sgdOffset + sgd.length;

  // Level payloads are stored smallest-first; the level index keeps base-first
  // order with explicit offsets.
  final levelOffsets = List<int>.filled(levels.length, 0);
  for (var i = levels.length - 1; i >= 0; i--) {
    cursor = _align(cursor, levelAlignment);
    levelOffsets[i] = cursor;
    cursor += levels[i].data.length;
  }

  final out = Uint8List(cursor);
  final data = ByteData.sublistView(out);
  out.setRange(0, ktx2Identifier.length, ktx2Identifier);
  data.setUint32(12, texture.vkFormat, Endian.little);
  data.setUint32(16, texture.typeSize, Endian.little);
  data.setUint32(20, texture.pixelWidth, Endian.little);
  data.setUint32(24, texture.pixelHeight, Endian.little);
  data.setUint32(28, texture.pixelDepth, Endian.little);
  data.setUint32(32, texture.layerCount, Endian.little);
  data.setUint32(36, texture.faceCount, Endian.little);
  data.setUint32(40, levels.length, Endian.little);
  data.setUint32(44, texture.supercompression.value, Endian.little);

  data.setUint32(48, dfdOffset, Endian.little);
  data.setUint32(52, dfd.length, Endian.little);
  data.setUint32(56, kvdOffset, Endian.little);
  data.setUint32(60, kvd.length, Endian.little);
  _writeU64(data, 64, sgdOffset);
  _writeU64(data, 72, sgd.length);

  for (var i = 0; i < levels.length; i++) {
    final entry = _headerEnd + _levelIndexEntrySize * i;
    _writeU64(data, entry, levelOffsets[i]);
    _writeU64(data, entry + 8, levels[i].data.length);
    _writeU64(data, entry + 16, levels[i].uncompressedByteLength);
  }

  if (dfd.isNotEmpty) out.setRange(dfdOffset, dfdOffset + dfd.length, dfd);
  if (kvd.isNotEmpty) out.setRange(kvdOffset, kvdOffset + kvd.length, kvd);
  if (sgd.isNotEmpty) out.setRange(sgdOffset, sgdOffset + sgd.length, sgd);
  for (var i = 0; i < levels.length; i++) {
    final payload = levels[i].data;
    out.setRange(levelOffsets[i], levelOffsets[i] + payload.length, payload);
  }
  return out;
}

Uint8List _slice(Uint8List bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw Ktx2FormatException(
      'Section at offset $offset length $length is out of range',
    );
  }
  return Uint8List.sublistView(bytes, offset, offset + length);
}

/// Encodes key/value data: per entry a 32-bit length, the UTF-8 key, a NUL, the
/// value bytes, then zero padding to a 4-byte boundary. Keys are sorted by
/// codepoint as the specification requires.
Uint8List _encodeKeyValues(Map<String, Uint8List> keyValues) {
  if (keyValues.isEmpty) return Uint8List(0);
  final keys = keyValues.keys.toList()..sort();
  final builder = BytesBuilder(copy: false);
  for (final key in keys) {
    final keyBytes = utf8.encode(key);
    final value = keyValues[key]!;
    final length = keyBytes.length + 1 + value.length;
    final header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, length, Endian.little);
    builder.add(header);
    builder.add(keyBytes);
    builder.addByte(0);
    builder.add(value);
    final pad = _align(length, 4) - length;
    if (pad > 0) builder.add(Uint8List(pad));
  }
  return builder.toBytes();
}

Map<String, Uint8List> _decodeKeyValues(Uint8List kvd) {
  final result = <String, Uint8List>{};
  final data = ByteData.sublistView(kvd);
  var offset = 0;
  while (offset + 4 <= kvd.length) {
    final length = data.getUint32(offset, Endian.little);
    offset += 4;
    if (length == 0 || offset + length > kvd.length) break;
    final entry = Uint8List.sublistView(kvd, offset, offset + length);
    final nul = entry.indexOf(0);
    if (nul >= 0) {
      final key = utf8.decode(Uint8List.sublistView(entry, 0, nul));
      result[key] = Uint8List.sublistView(entry, nul + 1);
    }
    offset = _align(offset + length, 4);
  }
  return result;
}
