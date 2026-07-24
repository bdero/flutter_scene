/// The `.fsceneb` binary container: a single self-contained file holding a
/// document's JSON manifest plus its binary payload chunks, concatenated like
/// a `.glb`.
///
/// The manifest chunk is the exact canonical JSON a bare `.fscene` text file
/// would carry (so the two forms share one codec); the payload chunks hold the
/// heavy binary the JSON references by id (vertex/index buffers, images,
/// matrices). Chunks are uncompressed and chunk-aligned so the container stays
/// cheap to read.
///
/// Layout (all integers little-endian):
///
/// ```text
/// Header (16 bytes):
///   [0..4)   magic           ASCII "FSCB"
///   [4..8)   version         uint32 (kFscenebVersion)
///   [8..12)  totalByteLength  uint32 (the whole container)
///   [12..16) reserved        uint32 (0)
/// Chunks (repeat until totalByteLength), each 8-byte aligned:
///   [0..4)   dataByteLength  uint32 (unpadded)
///   [4..8)   chunkType       4 ASCII bytes ("JSON" or "BLOB")
///   [8..)    data            dataByteLength bytes
///   padding  zero bytes to the next 8-byte boundary
/// ```
///
/// The first chunk is the sole "JSON" chunk (UTF-8 document text). Each "BLOB"
/// chunk carries one payload, its data being `[uint32 idByteLength][id token
/// UTF-8][payload bytes]`. An unrecognized chunk type is skipped, so the format
/// can grow new chunk kinds without breaking older readers.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/src/id.dart';
import 'package:scene/src/json/fscene_json.dart';
import 'package:scene/src/scene_document.dart';

/// The current `.fsceneb` container version this build reads and writes.
const int kFscenebVersion = 1;

const List<int> _magic = [0x46, 0x53, 0x43, 0x42]; // "FSCB"
const String _chunkJson = 'JSON';
const String _chunkBlob = 'BLOB';
const int _headerByteLength = 16;
const int _alignment = 8;

/// Thrown when a `.fsceneb` container is malformed.
class FscenebFormatException implements Exception {
  /// Creates a container-format exception with the given [message].
  const FscenebFormatException(this.message);

  /// What is wrong with the container.
  final String message;

  @override
  String toString() => 'FscenebFormatException: $message';
}

/// Serializes [document] to a `.fsceneb` container: the document's JSON
/// manifest followed by one chunk per payload.
///
/// Every payload in the document must carry its [PayloadSpec.bytes]; a
/// manifest-only payload (no bytes) cannot be embedded and throws a
/// [FscenebFormatException]. Payloads referenced by external `ref` rather than
/// an embedded chunk are not payloads, so they are unaffected.
Uint8List writeFsceneb(SceneDocument document) {
  final body = BytesBuilder();

  void addChunk(String type, Uint8List data) {
    final preamble = ByteData(8)..setUint32(0, data.length, Endian.little);
    final typeBytes = ascii.encode(type);
    for (var i = 0; i < 4; i++) {
      preamble.setUint8(4 + i, typeBytes[i]);
    }
    body.add(preamble.buffer.asUint8List());
    body.add(data);
    final remainder = data.length % _alignment;
    if (remainder != 0) body.add(Uint8List(_alignment - remainder));
  }

  addChunk(_chunkJson, utf8.encode(writeFscene(document)));

  // Emit payloads in a deterministic (id-sorted) order, matching the JSON
  // manifest's enumeration so two writes of the same document are identical.
  final payloads = document.payloads.entries.toList()
    ..sort((a, b) => a.key.toToken().compareTo(b.key.toToken()));
  for (final entry in payloads) {
    final bytes = entry.value.bytes;
    if (bytes == null) {
      throw FscenebFormatException(
        'Payload ${entry.key.toToken()} has no bytes to embed',
      );
    }
    addChunk(_chunkBlob, _encodeBlob(entry.key, bytes));
  }

  final bodyBytes = body.toBytes();
  final total = _headerByteLength + bodyBytes.length;
  final out = Uint8List(total);
  for (var i = 0; i < 4; i++) {
    out[i] = _magic[i];
  }
  ByteData.sublistView(out)
    ..setUint32(4, kFscenebVersion, Endian.little)
    ..setUint32(8, total, Endian.little)
    ..setUint32(12, 0, Endian.little);
  out.setRange(_headerByteLength, total, bodyBytes);
  return out;
}

/// Parses a `.fsceneb` container from [bytes] into a [SceneDocument] with each
/// embedded payload's [PayloadSpec.bytes] attached.
///
/// Tolerates the same JSONC superset and runs the same version migration as
/// [readFscene] for the manifest. Throws a [FscenebFormatException] on a bad
/// magic, an unsupported container version, or a missing manifest.
SceneDocument readFsceneb(Uint8List bytes) {
  if (bytes.length < _headerByteLength) {
    throw const FscenebFormatException('Truncated container (no header)');
  }
  for (var i = 0; i < 4; i++) {
    if (bytes[i] != _magic[i]) {
      throw const FscenebFormatException(
        'Not a .fsceneb container (bad magic)',
      );
    }
  }
  final view = ByteData.sublistView(bytes);
  final version = view.getUint32(4, Endian.little);
  if (version > kFscenebVersion) {
    throw FscenebFormatException(
      'Container version $version is newer than supported $kFscenebVersion',
    );
  }
  final total = view.getUint32(8, Endian.little);
  if (total > bytes.length) {
    throw const FscenebFormatException('Container length exceeds the data');
  }

  String? manifest;
  final blobs = <LocalId, Uint8List>{};
  var offset = _headerByteLength;
  while (offset + 8 <= total) {
    final dataLength = view.getUint32(offset, Endian.little);
    final type = ascii.decode(
      Uint8List.sublistView(bytes, offset + 4, offset + 8),
    );
    final dataStart = offset + 8;
    final dataEnd = dataStart + dataLength;
    if (dataEnd > total) {
      throw const FscenebFormatException('Chunk extends past the container');
    }
    final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
    switch (type) {
      case _chunkJson:
        manifest = utf8.decode(data);
      case _chunkBlob:
        final (id, payload) = _decodeBlob(data);
        blobs[id] = payload;
      default:
        break; // Skip unrecognized chunk types.
    }
    final padded = dataLength + ((-dataLength) & (_alignment - 1));
    offset = dataStart + padded;
  }

  if (manifest == null) {
    throw const FscenebFormatException('Container has no JSON manifest chunk');
  }
  final document = readFscene(manifest);
  blobs.forEach((id, payload) {
    document.payload(id)?.bytes = payload;
  });
  return document;
}

Uint8List _encodeBlob(LocalId id, Uint8List payload) {
  final token = ascii.encode(id.toToken());
  final out = Uint8List(4 + token.length + payload.length);
  ByteData.sublistView(out).setUint32(0, token.length, Endian.little);
  out.setRange(4, 4 + token.length, token);
  out.setRange(4 + token.length, out.length, payload);
  return out;
}

(LocalId, Uint8List) _decodeBlob(Uint8List data) {
  if (data.length < 4) {
    throw const FscenebFormatException('Truncated payload chunk');
  }
  final idLength = ByteData.sublistView(data).getUint32(0, Endian.little);
  final tokenEnd = 4 + idLength;
  if (tokenEnd > data.length) {
    throw const FscenebFormatException('Payload chunk id runs past its data');
  }
  final token = ascii.decode(Uint8List.sublistView(data, 4, tokenEnd));
  // Copy so the payload does not retain a view onto the whole container buffer.
  final payload = Uint8List.fromList(Uint8List.sublistView(data, tokenEnd));
  return (LocalId.parse(token), payload);
}
