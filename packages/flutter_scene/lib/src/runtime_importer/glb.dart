import 'dart:convert';
import 'dart:typed_data';

const int _kGlbMagic = 0x46546C67; // 'glTF' little-endian
const int _kChunkJson = 0x4E4F534A; // 'JSON' little-endian
const int _kChunkBin = 0x004E4942; // 'BIN\0' little-endian

class GlbContents {
  GlbContents({required this.json, required this.binaryChunk});

  final Map<String, Object?> json;
  final Uint8List binaryChunk;
}

/// Parse a GLB (binary glTF) blob into its JSON and embedded binary chunks.
///
/// Throws if [bytes] is not a valid GLB container.
GlbContents parseGlb(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const FormatException('GLB too short to contain a header');
  }
  final header = ByteData.sublistView(bytes, 0, 12);
  final magic = header.getUint32(0, Endian.little);
  if (magic != _kGlbMagic) {
    throw FormatException(
      'Not a GLB file: expected magic 0x${_kGlbMagic.toRadixString(16)}, '
      'got 0x${magic.toRadixString(16)}',
    );
  }
  final version = header.getUint32(4, Endian.little);
  if (version != 2) {
    throw FormatException(
      'Unsupported GLB version: $version (only 2 is supported)',
    );
  }
  final totalLength = header.getUint32(8, Endian.little);
  if (totalLength > bytes.length) {
    throw FormatException(
      'GLB header reports total length $totalLength but only ${bytes.length} '
      'bytes are available',
    );
  }

  Map<String, Object?>? json;
  Uint8List? binaryChunk;

  int offset = 12;
  while (offset < totalLength) {
    if (offset + 8 > totalLength) {
      throw const FormatException('Truncated GLB chunk header');
    }
    final chunkHeader = ByteData.sublistView(bytes, offset, offset + 8);
    final chunkLength = chunkHeader.getUint32(0, Endian.little);
    final chunkType = chunkHeader.getUint32(4, Endian.little);
    final chunkDataStart = offset + 8;
    final chunkDataEnd = chunkDataStart + chunkLength;
    if (chunkDataEnd > totalLength) {
      throw const FormatException('GLB chunk extends past end of file');
    }
    switch (chunkType) {
      case _kChunkJson:
        if (json != null) {
          throw const FormatException('GLB contains multiple JSON chunks');
        }
        final jsonText = utf8.decode(
          bytes.sublist(chunkDataStart, chunkDataEnd),
        );
        json = jsonDecode(jsonText) as Map<String, Object?>;
      case _kChunkBin:
        if (binaryChunk != null) {
          throw const FormatException('GLB contains multiple BIN chunks');
        }
        binaryChunk = Uint8List.sublistView(
          bytes,
          chunkDataStart,
          chunkDataEnd,
        );
      default:
        // Per spec, unknown chunks should be ignored.
        break;
    }
    offset = chunkDataEnd;
  }

  if (json == null) {
    throw const FormatException('GLB is missing the required JSON chunk');
  }
  return GlbContents(json: json, binaryChunk: binaryChunk ?? Uint8List(0));
}
