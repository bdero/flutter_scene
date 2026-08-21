// Decoder for the glTF 2.0 vendor extension EXT_meshopt_compression.
//
// Stream layouts follow the extension's "Appendix A: Bitstream" (mode 0
// attributes, mode 1 triangles, mode 2 indices) and the post-decode transforms
// follow "Appendix B: Filters" (1 octahedral, 2 quaternion, 3 exponential).
// Buffer-view fields and placeholder-buffer rules follow "Specifying
// compressed views" and "Fallback buffers".
//
// Attribute streams also carry a second codec version whose header byte is
// 0xa1, which current encoders emit. It adds 1-bit sentinel groups, all-zero
// and literal data blocks, and per-4-byte-channel delta widths on top of the
// version the appendix documents.
//
// Bit arithmetic here stays inside 32 bits (web ints are 53-bit with 32-bit
// bitwise semantics), so wider values are assembled through [ByteData] and
// rotated with multiplication rather than shifts.

import 'dart:math' as math;
import 'dart:typed_data';

import 'accessor.dart';
import 'types.dart';

/// Replaces every compressed buffer view in [doc] with a plain view over
/// decoded bytes appended to [bufferData].
///
/// Runs before anything reads an accessor, so the rest of the import sees an
/// ordinary document. Returns the inputs unchanged when nothing is compressed.
/// The compressed source is read from [bufferData] (the primary buffer);
/// placeholder and fallback buffers are never loaded, so they are never read.
({GltfDocument doc, Uint8List bufferData}) decodeMeshoptBufferViews(
  GltfDocument doc,
  Uint8List bufferData,
) {
  if (!doc.bufferViews.any((v) => v.meshopt != null)) {
    return (doc: doc, bufferData: bufferData);
  }

  final blob = BytesBuilder();
  blob.add(bufferData);
  final views = <GltfBufferView>[];
  final decodedViews = <int>{};

  for (final view in doc.bufferViews) {
    final compression = view.meshopt;
    if (compression == null) {
      views.add(view);
      continue;
    }
    final decoded = _decodeBufferView(compression, bufferData);
    while (blob.length % 4 != 0) {
      blob.addByte(0);
    }
    decodedViews.add(views.length);
    views.add(
      GltfBufferView(
        buffer: 0,
        byteOffset: blob.length,
        byteLength: decoded.length,
        byteStride: view.byteStride,
      ),
    );
    blob.add(decoded);
  }

  final decoded = doc.copyWith(bufferViews: views);
  final decodedData = blob.toBytes();
  _validateDecodedAccessors(decoded, decodedViews, decodedData);
  return (doc: decoded, bufferData: decodedData);
}

/// Buffer indices the decoding path must not load, either tagged as a
/// fallback or a URI-less placeholder that only compressed views reference.
///
/// A buffer holding compressed data is never one of these, even when it is
/// mistagged, so callers still load it.
Set<int> meshoptPlaceholderBuffers(GltfDocument doc) {
  final result = <int>{};
  for (int i = 0; i < doc.buffers.length; i++) {
    final buffer = doc.buffers[i];
    // Index 0 with no URI is the GLB binary chunk, which is always readable.
    if (buffer.meshoptFallback || (i > 0 && buffer.uri == null)) {
      result.add(i);
    }
  }
  if (result.isEmpty) return result;
  for (final view in doc.bufferViews) {
    final compression = view.meshopt;
    if (compression == null) continue;
    result.remove(compression.buffer);
  }
  return result;
}

Uint8List _decodeBufferView(
  GltfMeshoptCompression compression,
  Uint8List bufferData,
) {
  // TODO(meshopt-multi-buffer): both import paths hand the decoder a single
  // buffer, so compressed data has to live in it.
  if (compression.buffer != 0) {
    throw FormatException(
      'EXT_meshopt_compression sources compressed data from buffer '
      '${compression.buffer}; only the primary buffer is supported',
    );
  }
  if (compression.count < 0 || compression.byteStride <= 0) {
    throw FormatException(
      'EXT_meshopt_compression view has count ${compression.count} and '
      'byteStride ${compression.byteStride}',
    );
  }
  final start = compression.byteOffset;
  final end = start + compression.byteLength;
  if (start < 0 || end > bufferData.length) {
    throw FormatException(
      'EXT_meshopt_compression view spans bytes $start..$end of a '
      '${bufferData.length} byte buffer',
    );
  }
  // Checked up front so a stride the filter forbids is reported as such rather
  // than as whatever the bitstream does with it.
  _checkFilterStride(compression);

  final source = Uint8List.sublistView(bufferData, start, end);
  final target = Uint8List(compression.decodedByteLength);

  try {
    switch (compression.mode) {
      case 'ATTRIBUTES':
        _decodeVertexBuffer(
          target,
          compression.count,
          compression.byteStride,
          source,
        );
        _applyFilter(
          target,
          compression.count,
          compression.byteStride,
          compression.filter,
        );
      case 'TRIANGLES':
        _decodeIndexBuffer(
          target,
          compression.count,
          compression.byteStride,
          source,
        );
      case 'INDICES':
        _decodeIndexSequence(
          target,
          compression.count,
          compression.byteStride,
          source,
        );
      default:
        throw FormatException(
          'Unknown EXT_meshopt_compression mode "${compression.mode}"',
        );
    }
  } on FormatException {
    rethrow;
  } catch (e) {
    // A truncated or corrupt stream runs off the end of a list or hands a
    // filter a non-finite value; report it as bad input, not as a crash.
    throw FormatException(
      'Malformed EXT_meshopt_compression ${compression.mode} stream ($e)',
    );
  }
  return target;
}

// Filters only apply to attribute data, and each constrains the stride.
void _checkFilterStride(GltfMeshoptCompression compression) {
  final filter = compression.filter;
  if (filter == 'NONE') return;
  if (compression.mode != 'ATTRIBUTES') {
    throw FormatException(
      'EXT_meshopt_compression ${compression.mode} mode cannot carry the '
      '"$filter" filter',
    );
  }
  final stride = compression.byteStride;
  switch (filter) {
    case 'OCTAHEDRAL':
      if (stride != 4 && stride != 8) {
        throw FormatException(
          'EXT_meshopt_compression octahedral filter needs a stride of 4 or '
          '8, got $stride',
        );
      }
    case 'QUATERNION':
      if (stride != 8) {
        throw FormatException(
          'EXT_meshopt_compression quaternion filter needs a stride of 8, got '
          '$stride',
        );
      }
    case 'EXPONENTIAL':
      if (stride % 4 != 0) {
        throw FormatException(
          'EXT_meshopt_compression exponential filter needs a stride that is '
          'a multiple of 4, got $stride',
        );
      }
    default:
      // TODO(meshopt-color-filter): the codec has since grown a COLOR filter
      // that this extension version does not define. Decode it here once the
      // extension picks it up.
      throw FormatException('Unknown EXT_meshopt_compression filter "$filter"');
  }
}

// Checks every accessor that reads decoded data, so a stream that decoded into
// plausible-looking garbage fails here instead of downstream. Index accessors
// are additionally range-checked against the vertex count they index into.
void _validateDecodedAccessors(
  GltfDocument doc,
  Set<int> decodedViews,
  Uint8List bufferData,
) {
  for (final accessor in doc.accessors) {
    final viewIndex = accessor.bufferView;
    if (viewIndex == null || !decodedViews.contains(viewIndex)) continue;
    final view = doc.bufferViews[viewIndex];
    final elementBytes =
        accessor.type.componentCount * accessor.componentType.bytes;
    final stride = view.byteStride ?? elementBytes;
    final needed = accessor.count == 0
        ? 0
        : accessor.byteOffset + (accessor.count - 1) * stride + elementBytes;
    if (needed > view.byteLength) {
      throw FormatException(
        'glTF accessor needs $needed bytes of a ${view.byteLength} byte '
        'EXT_meshopt_compression view',
      );
    }
  }

  for (final mesh in doc.meshes) {
    for (final primitive in mesh.primitives) {
      final indices = primitive.indices;
      final position = primitive.attributes['POSITION'];
      if (indices == null || position == null) continue;
      if (indices >= doc.accessors.length || position >= doc.accessors.length) {
        continue;
      }
      final accessor = doc.accessors[indices];
      final viewIndex = accessor.bufferView;
      if (viewIndex == null || !decodedViews.contains(viewIndex)) continue;
      final vertexCount = doc.accessors[position].count;
      final values = readAccessorAsUint32(
        accessor,
        doc.bufferViews,
        bufferData,
      );
      for (final value in values) {
        if (value >= vertexCount) {
          throw FormatException(
            'Decoded EXT_meshopt_compression index $value addresses a '
            'primitive with $vertexCount vertices',
          );
        }
      }
    }
  }
}

// Mode 0: attributes.
void _decodeVertexBuffer(
  Uint8List target,
  int count,
  int byteStride,
  Uint8List source,
) {
  if (byteStride % 4 != 0 || byteStride > 256) {
    throw FormatException(
      'EXT_meshopt_compression attribute stride $byteStride is not a '
      'multiple of 4 within 256 bytes',
    );
  }
  if (source.isEmpty || (source[0] != 0xa0 && source[0] != 0xa1)) {
    throw FormatException(
      'EXT_meshopt_compression attribute stream has header byte '
      '0x${source.isEmpty ? '' : source[0].toRadixString(16)}, expected '
      '0xa0 or 0xa1',
    );
  }
  final version = source[0] - 0xa0;

  // The tail holds the baseline element, plus one channel byte per 4-byte
  // group for version 1, and is padded out to a fixed minimum.
  final tailSize = version == 0 ? byteStride : byteStride + byteStride ~/ 4;
  final paddedTail = math.max(tailSize, version == 0 ? 32 : 24);
  if (source.length - 1 < paddedTail) {
    throw FormatException(
      'EXT_meshopt_compression attribute stream is ${source.length} bytes, '
      'too short to hold a $paddedTail byte tail',
    );
  }
  final tailOffset = source.length - tailSize;
  final baseline = Uint8List.fromList(
    source.sublist(tailOffset, tailOffset + byteStride),
  );
  final channels = version == 0
      ? null
      : Uint8List.sublistView(source, tailOffset + byteStride, source.length);

  final maxBlockElements = math.min(
    _alignDown(0x2000 ~/ byteStride, 16),
    0x100,
  );
  // One delta plane per byte of the element, each holding the block's deltas
  // for that byte position.
  final deltas = Uint8List(maxBlockElements * byteStride);

  // Bits per delta for each group header value, by codec version and (for
  // version 1) the data block's control mode.
  const headerModes = [
    [0, 2, 4, 8], // version 0
    [0, 1, 2, 4], // version 1, control 0
    [1, 2, 4, 8], // version 1, control 1
  ];

  final scratch = ByteData(4);
  int offset = 1;

  for (int blockBase = 0; blockBase < count; blockBase += maxBlockElements) {
    final blockCount = math.min(count - blockBase, maxBlockElements);
    final groupCount = _alignUp(blockCount, 16) ~/ 16;
    final headerBytes = _alignUp(groupCount, 4) ~/ 4;

    final controlOffset = offset;
    offset += version == 0 ? 0 : byteStride ~/ 4;

    for (int byte = 0; byte < byteStride; byte++) {
      final deltaBase = byte * blockCount;
      final control = version == 0
          ? 0
          : (source[controlOffset + (byte >> 2)] >> ((byte & 0x03) << 1)) &
                0x03;

      if (control == 2) {
        // Every delta for this byte is zero and nothing is stored.
        deltas.fillRange(deltaBase, deltaBase + blockCount, 0);
        continue;
      }
      if (control == 3) {
        // Deltas are stored verbatim with no group headers.
        deltas.setRange(deltaBase, deltaBase + blockCount, source, offset);
        offset += blockCount;
        continue;
      }

      final headerOffset = offset;
      offset += headerBytes;

      for (int group = 0; group < groupCount; group++) {
        final header =
            (source[headerOffset + (group >> 2)] >> ((group & 0x03) << 1)) &
            0x03;
        final bits = headerModes[version == 0 ? 0 : control + 1][header];
        final deltaOffset = deltaBase + (group << 4);

        switch (bits) {
          case 0:
            // All 16 deltas are zero.
            deltas.fillRange(deltaOffset, deltaOffset + 16, 0);
          case 1:
            // 1-bit sentinel encoding, stored least significant bit first.
            final base = offset;
            offset += 2;
            for (int m = 0; m < 16; m++) {
              int delta = (source[base + (m >> 3)] >> (m & 0x07)) & 0x01;
              if (delta == 1) delta = source[offset++];
              deltas[deltaOffset + m] = delta;
            }
          case 2:
            // 2-bit sentinel encoding, stored most significant bit first.
            final base = offset;
            offset += 4;
            for (int m = 0; m < 16; m++) {
              int delta =
                  (source[base + (m >> 2)] >> (6 - ((m & 0x03) << 1))) & 0x03;
              if (delta == 3) delta = source[offset++];
              deltas[deltaOffset + m] = delta;
            }
          case 4:
            // 4-bit sentinel encoding, stored most significant bit first.
            final base = offset;
            offset += 8;
            for (int m = 0; m < 16; m++) {
              int delta =
                  (source[base + (m >> 1)] >> (4 - ((m & 0x01) << 2))) & 0x0f;
              if (delta == 0x0f) delta = source[offset++];
              deltas[deltaOffset + m] = delta;
            }
          default:
            // All 16 deltas are stored as bytes.
            deltas.setRange(deltaOffset, deltaOffset + 16, source, offset);
            offset += 16;
        }
      }
    }

    for (int element = 0; element < blockCount; element++) {
      final targetBase = (blockBase + element) * byteStride;

      for (int group = 0; group < byteStride; group += 4) {
        final channel = version == 0 ? 0 : channels![group >> 2] & 0x03;

        switch (channel) {
          case 0:
            // Byte deltas against the previous element, zigzag encoded.
            for (int byte = group; byte < group + 4; byte++) {
              final delta = _unzigzag(deltas[byte * blockCount + element]);
              final value = (baseline[byte] + delta) & 0xff;
              baseline[byte] = value;
              target[targetBase + byte] = value;
            }
          case 1:
            // 16-bit deltas against the previous element, zigzag encoded.
            for (int byte = group; byte < group + 4; byte += 2) {
              final delta = _unzigzag(
                deltas[byte * blockCount + element] +
                    (deltas[(byte + 1) * blockCount + element] << 8),
              );
              final previous = baseline[byte] + (baseline[byte + 1] << 8);
              final value = (previous + delta) & 0xffff;
              baseline[byte] = value & 0xff;
              baseline[byte + 1] = value >> 8;
              target[targetBase + byte] = baseline[byte];
              target[targetBase + byte + 1] = baseline[byte + 1];
            }
          case 2:
            // 32-bit deltas XORed against the previous element, rotated right
            // by the channel byte's high nibble.
            scratch.setUint8(0, deltas[group * blockCount + element]);
            scratch.setUint8(1, deltas[(group + 1) * blockCount + element]);
            scratch.setUint8(2, deltas[(group + 2) * blockCount + element]);
            scratch.setUint8(3, deltas[(group + 3) * blockCount + element]);
            final rotation = channels![group >> 2] >> 4;
            scratch.setUint32(
              0,
              _rotateRight32(scratch.getUint32(0, Endian.little), rotation),
              Endian.little,
            );
            for (int byte = 0; byte < 4; byte++) {
              final value = baseline[group + byte] ^ scratch.getUint8(byte);
              baseline[group + byte] = value;
              target[targetBase + group + byte] = value;
            }
          default:
            throw FormatException(
              'Unknown EXT_meshopt_compression channel mode $channel',
            );
        }
      }
    }
  }

  if (offset != source.length - paddedTail) {
    throw FormatException(
      'EXT_meshopt_compression attribute stream ends at byte $offset of '
      '${source.length}, expected ${source.length - paddedTail}',
    );
  }
}

int _alignUp(int value, int alignment) =>
    value + (alignment - value % alignment) % alignment;

int _alignDown(int value, int alignment) => value - value % alignment;

int _unzigzag(int value) => value.isOdd ? -((value ~/ 2) + 1) : value ~/ 2;

// Keeps a running index inside 32 bits the way the encoder's arithmetic does.
int _wrap32(int value) => value % 4294967296;

// Rotates a 32-bit value right without touching bits above 31.
int _rotateRight32(int value, int bits) {
  if (bits == 0) return value;
  final divisor = 1 << bits;
  return (value ~/ divisor) + (value % divisor) * (4294967296 ~/ divisor);
}

// Mode 1: triangles.
void _decodeIndexBuffer(
  Uint8List target,
  int count,
  int byteStride,
  Uint8List source,
) {
  _requireIndexStride(byteStride);
  if (count % 3 != 0) {
    throw FormatException(
      'EXT_meshopt_compression triangle stream has $count indices, which is '
      'not a whole number of triangles',
    );
  }
  final triangles = count ~/ 3;
  // Header byte, one code byte per triangle, then variable data ahead of the
  // 16-byte lookup table.
  if (source.length < 1 + triangles + 16) {
    throw FormatException(
      'EXT_meshopt_compression triangle stream is ${source.length} bytes, too '
      'short for $triangles triangles',
    );
  }
  if (source[0] != 0xe1) {
    throw FormatException(
      'EXT_meshopt_compression triangle stream has header byte '
      '0x${source[0].toRadixString(16)}, expected 0xe1',
    );
  }
  final tableOffset = source.length - 16;

  final cursor = _StreamCursor(source, 1 + triangles);
  final out = _IndexWriter(target, byteStride);
  // Filled the way the encoder's fifos start, so a reference to an entry the
  // encoder never wrote decodes to an index no primitive can hold.
  final edgeFifo = Uint32List(32)..fillRange(0, 32, 0xffffffff);
  final vertexFifo = Uint32List(16)..fillRange(0, 16, 0xffffffff);
  int edgeOffset = 0;
  int vertexOffset = 0;
  int next = 0;
  int last = 0;

  int readEdge(int n) => edgeFifo[(edgeOffset - 1 - n) & 31];
  int readVertex(int n) => vertexFifo[(vertexOffset - 1 - n) & 15];
  void pushEdge(int v) {
    edgeFifo[edgeOffset] = v;
    edgeOffset = (edgeOffset + 1) & 31;
  }

  void pushVertex(int v) {
    vertexFifo[vertexOffset] = v;
    vertexOffset = (vertexOffset + 1) & 15;
  }

  int codeOffset = 1;
  for (int i = 0; i < triangles; i++) {
    final code = source[codeOffset++];
    final b0 = code >> 4;
    final b1 = code & 0x0f;

    int a, b, c;
    if (b0 < 0x0f) {
      // A shared edge from the edge fifo, stored most recent pair last.
      a = readEdge((b0 << 1) + 0);
      b = readEdge((b0 << 1) + 1);

      if (b1 == 0x00) {
        c = next++;
        pushVertex(c);
      } else if (b1 < 0x0d) {
        c = readVertex(b1);
      } else if (b1 == 0x0d) {
        last = c = _wrap32(last - 1);
        pushVertex(c);
      } else if (b1 == 0x0e) {
        last = c = _wrap32(last + 1);
        pushVertex(c);
      } else {
        cursor.requireData(tableOffset);
        last = c = _wrap32(last + _unzigzag(cursor.readLeb128()));
        pushVertex(c);
      }

      // Edge pushes store each pair second element first.
      pushEdge(b);
      pushEdge(c);
      pushEdge(c);
      pushEdge(a);
    } else if (b1 < 0x0e) {
      // Two of the three corners come from a code in the lookup table.
      final e = source[tableOffset + b1];
      final z = e >> 4;
      final w = e & 0x0f;

      a = next++;
      b = z == 0x00 ? next++ : readVertex(z - 1);
      c = w == 0x00 ? next++ : readVertex(w - 1);

      pushVertex(a);
      if (z == 0x00) pushVertex(b);
      if (w == 0x00) pushVertex(c);

      pushEdge(a);
      pushEdge(b);
      pushEdge(b);
      pushEdge(c);
      pushEdge(c);
      pushEdge(a);
    } else {
      // The same code stored inline instead of looked up, which also allows
      // delta-coded corners.
      cursor.requireData(tableOffset);
      final e = cursor.readByte();
      if (e == 0x00) next = 0;
      final z = e >> 4;
      final w = e & 0x0f;

      if (b1 == 0x0e) {
        a = next++;
      } else {
        last = a = _wrap32(last + _unzigzag(cursor.readLeb128()));
      }

      if (z == 0x00) {
        b = next++;
      } else if (z == 0x0f) {
        last = b = _wrap32(last + _unzigzag(cursor.readLeb128()));
      } else {
        b = readVertex(z - 1);
      }

      if (w == 0x00) {
        c = next++;
      } else if (w == 0x0f) {
        last = c = _wrap32(last + _unzigzag(cursor.readLeb128()));
      } else {
        c = readVertex(w - 1);
      }

      pushVertex(a);
      if (z == 0x00 || z == 0x0f) pushVertex(b);
      if (w == 0x00 || w == 0x0f) pushVertex(c);

      pushEdge(a);
      pushEdge(b);
      pushEdge(b);
      pushEdge(c);
      pushEdge(c);
      pushEdge(a);
    }

    out.write(a);
    out.write(b);
    out.write(c);
  }

  if (cursor.offset != tableOffset) {
    throw FormatException(
      'EXT_meshopt_compression triangle stream leaves '
      '${tableOffset - cursor.offset} bytes between its data and its lookup '
      'table',
    );
  }
}

// Mode 2: indices.
void _decodeIndexSequence(
  Uint8List target,
  int count,
  int byteStride,
  Uint8List source,
) {
  _requireIndexStride(byteStride);
  // Header byte, at least one byte per index, then a 4-byte tail.
  if (source.length < 1 + count + 4) {
    throw FormatException(
      'EXT_meshopt_compression index stream is ${source.length} bytes, too '
      'short for $count indices',
    );
  }
  if (source[0] != 0xd1) {
    throw FormatException(
      'EXT_meshopt_compression index stream has header byte '
      '0x${source[0].toRadixString(16)}, expected 0xd1',
    );
  }
  final tailOffset = source.length - 4;
  final cursor = _StreamCursor(source, 1);
  final out = _IndexWriter(target, byteStride);
  // Two baselines, picked per index by the delta's low bit.
  final last = Uint32List(2);

  for (int i = 0; i < count; i++) {
    cursor.requireData(tailOffset);
    final value = cursor.readLeb128();
    final lane = value & 0x01;
    last[lane] = last[lane] + _unzigzag(value ~/ 2);
    out.write(last[lane]);
  }

  if (cursor.offset != tailOffset) {
    throw FormatException(
      'EXT_meshopt_compression index stream leaves '
      '${tailOffset - cursor.offset} bytes between its data and its tail',
    );
  }
}

void _requireIndexStride(int byteStride) {
  if (byteStride != 2 && byteStride != 4) {
    throw FormatException(
      'EXT_meshopt_compression index stride $byteStride is neither 2 nor 4',
    );
  }
}

// A read cursor over a compressed stream's variable-length data section.
class _StreamCursor {
  _StreamCursor(this.source, this.offset);

  final Uint8List source;
  int offset;

  int readByte() => source[offset++];

  /// Fails when the data section has already run into the stream's tail.
  void requireData(int tailOffset) {
    if (offset >= tailOffset) {
      throw const FormatException(
        'EXT_meshopt_compression stream reads past the end of its data',
      );
    }
  }

  /// Reads a 32-bit LEB128 value from at most five bytes, wrapping past bit 31
  /// like the encoder does.
  int readLeb128() {
    int value = source[offset++];
    if (value < 0x80) return value;
    value -= 0x80;
    int shift = 128;
    for (int i = 0; i < 4; i++) {
      final byte = source[offset++];
      value = (value + (byte & 0x7f) * shift) % 4294967296;
      if (byte < 0x80) break;
      shift *= 128;
    }
    return value;
  }
}

// Writes decoded indices at the view's index width.
class _IndexWriter {
  _IndexWriter(Uint8List target, this.byteStride)
    : _data = ByteData.sublistView(target);

  final ByteData _data;
  final int byteStride;
  int _offset = 0;

  void write(int value) {
    if (byteStride == 2) {
      _data.setUint16(_offset, value % 65536, Endian.little);
    } else {
      _data.setUint32(_offset, value % 4294967296, Endian.little);
    }
    _offset += byteStride;
  }
}

void _applyFilter(Uint8List target, int count, int byteStride, String filter) {
  switch (filter) {
    case 'OCTAHEDRAL':
      _filterOctahedral(target, count, byteStride);
    case 'QUATERNION':
      _filterQuaternion(target, count);
    case 'EXPONENTIAL':
      _filterExponential(target, count, byteStride);
  }
}

// Filter 1: octahedral. Rebuilds a unit vector from its octahedral
// projection, in place, keeping the fourth component. Rounding is half away
// from zero, matching the encoder.
void _filterOctahedral(Uint8List target, int count, int byteStride) {
  final wide = byteStride == 8;
  final data = ByteData.sublistView(target);
  final maxInt = wide ? 32767.0 : 127.0;

  for (int i = 0; i < count; i++) {
    final base = i * byteStride;
    double read(int component) => wide
        ? data.getInt16(base + component * 2, Endian.little).toDouble()
        : data.getInt8(base + component).toDouble();
    void write(int component, double value) {
      final rounded = value.round();
      if (wide) {
        data.setInt16(base + component * 2, rounded, Endian.little);
      } else {
        data.setInt8(base + component, rounded);
      }
    }

    // The third component carries the encoding's representation of 1.0, which
    // is what makes the precision per element.
    final one = read(2);
    double x = read(0) / one;
    double y = read(1) / one;
    final z = 1.0 - x.abs() - y.abs();
    final t = math.max(-z, 0.0);
    x -= x >= 0 ? t : -t;
    y -= y >= 0 ? t : -t;
    final scale = maxInt / math.sqrt(x * x + y * y + z * z);
    write(0, x * scale);
    write(1, y * scale);
    write(2, z * scale);
  }
}

// Filter 2: quaternion. Rebuilds the dropped largest component and rotates
// the components back into place.
void _filterQuaternion(Uint8List target, int count) {
  final data = ByteData.sublistView(target);

  for (int i = 0; i < count; i++) {
    final base = i * 8;
    final packed = data.getInt16(base + 6, Endian.little);
    final largest = packed & 0x03;
    // The same word carries 1.0 in the encoding's precision, with the bottom
    // two bits spent on the dropped component's index.
    final one = _toInt16((packed & 0xffff) | 0x03);
    final scale = math.sqrt1_2 / one;
    final x = data.getInt16(base, Endian.little) * scale;
    final y = data.getInt16(base + 2, Endian.little) * scale;
    final z = data.getInt16(base + 4, Endian.little) * scale;
    final w = math.sqrt(math.max(0.0, 1.0 - x * x - y * y - z * z));

    void write(int component, double value) => data.setInt16(
      base + (((largest + component) & 0x03) << 1),
      (value * 32767).round(),
      Endian.little,
    );

    write(1, x);
    write(2, y);
    write(3, z);
    write(0, w);
  }
}

int _toInt16(int value) => value >= 0x8000 ? value - 0x10000 : value;

// Filter 3: exponential. Each 4-byte lane holds a signed 8-bit exponent and a
// signed 24-bit mantissa, decoding to a float.
void _filterExponential(Uint8List target, int count, int byteStride) {
  final data = ByteData.sublistView(target);
  final scratch = ByteData(4);
  final lanes = count * (byteStride ~/ 4);

  for (int i = 0; i < lanes; i++) {
    final base = i * 4;
    final exponent = data.getInt8(base + 3);
    final mantissa =
        data.getUint8(base) +
        data.getUint8(base + 1) * 256 +
        data.getInt8(base + 2) * 65536;
    // 2^exponent as a float, assembled from its bit pattern.
    scratch.setUint32(
      0,
      ((exponent + 127) * 8388608) % 4294967296,
      Endian.little,
    );
    data.setFloat32(
      base,
      scratch.getFloat32(0, Endian.little) * mantissa,
      Endian.little,
    );
  }
}
