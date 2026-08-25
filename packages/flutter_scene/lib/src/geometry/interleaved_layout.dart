import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/constants.dart';

/// Translates structure-of-arrays vertex attributes into the interleaved
/// unskinned vertex layout.
///
/// The interleaved layout packs every attribute of a vertex contiguously:
/// 18 floats (72 bytes) per vertex, ordered position (3), normal (3),
/// primary texture coordinates (2), secondary texture coordinates (2),
/// color (4), tangent (4).
///
/// The geometry construction API accepts attributes as independent typed
/// arrays; this adapter packs them into the single interleaved buffer the
/// built-in pipelines consume. It is intentionally the one place that
/// depends on the interleaved layout, so the rest of the geometry API can
/// move to independent attribute buffers later without an API change.
///
/// Every method here is pure and free of GPU resources, so the packing
/// can be exercised without a render context.
/// Six tightly packed per-attribute unskinned vertex streams.
class UnskinnedAttributeStreams {
  const UnskinnedAttributeStreams({
    required this.position,
    required this.normal,
    required this.texCoord,
    required this.texCoord1,
    required this.color,
    required this.tangent,
  });

  final Uint8List position;
  final Uint8List normal;
  final Uint8List texCoord;
  final Uint8List texCoord1;
  final Uint8List color;
  final Uint8List tangent;
}

abstract final class InterleavedLayoutAdapter {
  static const int legacyUnskinnedVertexBytes = 48;
  static const int legacySkinnedVertexBytes = 80;

  /// Floats per vertex in the interleaved unskinned layout.
  static const int floatsPerVertex = kUnskinnedPerVertexSize ~/ 4;

  /// Packs [vertexCount] vertices of structure-of-arrays attributes into
  /// one interleaved unskinned vertex buffer.
  ///
  /// [positions] is required and must hold `3 * vertexCount` floats.
  /// [normals] (`3 * vertexCount`), [texCoords] and [texCoords1]
  /// (`2 * vertexCount` each), [colors], and [tangents]
  /// (`4 * vertexCount` each) are optional.
  /// Absent attributes use the standard neutral defaults.
  static Uint8List packUnskinned({
    required Float32List positions,
    required int vertexCount,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? texCoords1,
    Float32List? colors,
    Float32List? tangents,
  }) {
    _checkLength('positions', positions.length, 3 * vertexCount);
    if (normals != null) {
      _checkLength('normals', normals.length, 3 * vertexCount);
    }
    if (texCoords != null) {
      _checkLength('texCoords', texCoords.length, 2 * vertexCount);
    }
    if (texCoords1 != null) {
      _checkLength('texCoords1', texCoords1.length, 2 * vertexCount);
    }
    if (colors != null) {
      _checkLength('colors', colors.length, 4 * vertexCount);
    }
    if (tangents != null) {
      _checkLength('tangents', tangents.length, 4 * vertexCount);
    }

    final out = Float32List(vertexCount * floatsPerVertex);
    for (var v = 0; v < vertexCount; v++) {
      final o = v * floatsPerVertex;
      out[o + 0] = positions[v * 3 + 0];
      out[o + 1] = positions[v * 3 + 1];
      out[o + 2] = positions[v * 3 + 2];
      if (normals != null) {
        out[o + 3] = normals[v * 3 + 0];
        out[o + 4] = normals[v * 3 + 1];
        out[o + 5] = normals[v * 3 + 2];
      } else {
        out[o + 5] = 1.0;
      }
      if (texCoords != null) {
        out[o + 6] = texCoords[v * 2 + 0];
        out[o + 7] = texCoords[v * 2 + 1];
      }
      if (texCoords1 != null) {
        out[o + 8] = texCoords1[v * 2 + 0];
        out[o + 9] = texCoords1[v * 2 + 1];
      }
      if (colors != null) {
        out[o + 10] = colors[v * 4 + 0];
        out[o + 11] = colors[v * 4 + 1];
        out[o + 12] = colors[v * 4 + 2];
        out[o + 13] = colors[v * 4 + 3];
      } else {
        out[o + 10] = 1.0;
        out[o + 11] = 1.0;
        out[o + 12] = 1.0;
        out[o + 13] = 1.0;
      }
      if (tangents != null) {
        out[o + 14] = tangents[v * 4 + 0];
        out[o + 15] = tangents[v * 4 + 1];
        out[o + 16] = tangents[v * 4 + 2];
        out[o + 17] = tangents[v * 4 + 3];
      }
    }
    return out.buffer.asUint8List();
  }

  /// Bytes per vertex of each de-interleaved unskinned attribute stream:
  /// position (`vec3`), normal (`vec3`), two texture coordinates (`vec2`),
  /// color (`vec4`), tangent (`vec4`). Their sum is
  /// [kUnskinnedPerVertexSize].
  static const int positionStreamBytes = 12;
  static const int normalStreamBytes = 12;
  static const int texCoordStreamBytes = 8;
  static const int texCoord1StreamBytes = 8;
  static const int colorStreamBytes = 16;
  static const int tangentStreamBytes = 16;

  /// Byte offset of each attribute within the interleaved 72-byte vertex.
  static const int _normalByteOffset = 12;
  static const int _texCoordByteOffset = 24;
  static const int _texCoord1ByteOffset = 32;
  static const int _colorByteOffset = 40;
  static const int _tangentByteOffset = 56;

  /// The `.fscene` payload layout string for a de-interleaved
  /// (structure-of-arrays) unskinned vertex buffer with six attribute
  /// streams concatenated, position, normal, UV0, UV1, color, then tangent. The
  /// older `unskinned` layout is the interleaved form.
  static const String unskinnedSoaLayout = 'unskinned_soa_uv1_tangent';
  static const String unskinnedInterleavedLayout = 'unskinned_uv1_tangent';
  static const String skinnedLayout = 'skinned_uv1_tangent';

  /// Expands the original four-stream unskinned payload with zero UV1 and
  /// tangent streams.
  static UnskinnedAttributeStreams upgradeLegacyUnskinnedSoa(
    Uint8List soa,
    int vertexCount,
  ) {
    final expected = vertexCount * legacyUnskinnedVertexBytes;
    if (soa.lengthInBytes != expected) {
      throw ArgumentError(
        'legacy unskinned payload holds ${soa.lengthInBytes} bytes; expected '
        '$expected for $vertexCount vertices',
      );
    }
    final buffer = soa.buffer;
    var offset = soa.offsetInBytes;
    Uint8List take(int bytesPerVertex) {
      final view = buffer.asUint8List(offset, bytesPerVertex * vertexCount);
      offset += bytesPerVertex * vertexCount;
      return view;
    }

    return UnskinnedAttributeStreams(
      position: take(positionStreamBytes),
      normal: take(normalStreamBytes),
      texCoord: take(texCoordStreamBytes),
      texCoord1: Uint8List(texCoord1StreamBytes * vertexCount),
      color: take(colorStreamBytes),
      tangent: Uint8List(tangentStreamBytes * vertexCount),
    );
  }

  /// Expands the original interleaved unskinned layout with zero UV1 and
  /// tangents.
  static Uint8List upgradeLegacyUnskinnedInterleaved(
    ByteData legacy,
    int vertexCount,
  ) {
    final expected = vertexCount * legacyUnskinnedVertexBytes;
    if (legacy.lengthInBytes != expected) {
      throw ArgumentError(
        'legacy unskinned payload holds ${legacy.lengthInBytes} bytes; expected '
        '$expected for $vertexCount vertices',
      );
    }
    final source = Float32List.sublistView(legacy);
    final out = Float32List(vertexCount * floatsPerVertex);
    for (var vertex = 0; vertex < vertexCount; vertex++) {
      final src = vertex * 12;
      final dst = vertex * floatsPerVertex;
      out.setRange(dst, dst + 8, source, src);
      out.setRange(dst + 10, dst + 14, source, src + 8);
    }
    return out.buffer.asUint8List();
  }

  /// Expands the original interleaved skinned layout with zero UV1 and
  /// tangents while preserving joints and weights.
  static Uint8List upgradeLegacySkinnedInterleaved(
    ByteData legacy,
    int vertexCount,
  ) {
    final expected = vertexCount * legacySkinnedVertexBytes;
    if (legacy.lengthInBytes != expected) {
      throw ArgumentError(
        'legacy skinned payload holds ${legacy.lengthInBytes} bytes; expected '
        '$expected for $vertexCount vertices',
      );
    }
    final source = Float32List.sublistView(legacy);
    final out = Float32List(vertexCount * 26);
    for (var vertex = 0; vertex < vertexCount; vertex++) {
      final src = vertex * 20;
      final dst = vertex * 26;
      out.setRange(dst, dst + 8, source, src);
      out.setRange(dst + 10, dst + 14, source, src + 8);
      out.setRange(dst + 18, dst + 26, source, src + 12);
    }
    return out.buffer.asUint8List();
  }

  /// Concatenates the six per-attribute streams into one buffer, position,
  /// normal, UV0, UV1, color, then tangent. This is the on-disk
  /// structure-of-arrays vertex payload; [sliceUnskinnedStreams] is the
  /// inverse.
  static Uint8List concatUnskinnedStreams(UnskinnedAttributeStreams streams) {
    final out = Uint8List(
      streams.position.length +
          streams.normal.length +
          streams.texCoord.length +
          streams.texCoord1.length +
          streams.color.length +
          streams.tangent.length,
    );
    var offset = 0;
    out.setAll(offset, streams.position);
    offset += streams.position.length;
    out.setAll(offset, streams.normal);
    offset += streams.normal.length;
    out.setAll(offset, streams.texCoord);
    offset += streams.texCoord.length;
    out.setAll(offset, streams.texCoord1);
    offset += streams.texCoord1.length;
    out.setAll(offset, streams.color);
    offset += streams.color.length;
    out.setAll(offset, streams.tangent);
    return out;
  }

  /// Slices a concatenated structure-of-arrays unskinned vertex payload back
  /// into its six attribute streams as views into [soa] (no copy). The
  /// inverse of [concatUnskinnedStreams].
  static UnskinnedAttributeStreams sliceUnskinnedStreams(
    Uint8List soa,
    int vertexCount,
  ) {
    final buffer = soa.buffer;
    var offset = soa.offsetInBytes;
    Uint8List take(int bytesPerVertex) {
      final view = buffer.asUint8List(offset, bytesPerVertex * vertexCount);
      offset += bytesPerVertex * vertexCount;
      return view;
    }

    return UnskinnedAttributeStreams(
      position: take(positionStreamBytes),
      normal: take(normalStreamBytes),
      texCoord: take(texCoordStreamBytes),
      texCoord1: take(texCoord1StreamBytes),
      color: take(colorStreamBytes),
      tangent: take(tangentStreamBytes),
    );
  }

  /// Splits one interleaved unskinned vertex buffer into the six tightly
  /// packed per-attribute streams.
  ///
  /// The interleaved input is [kUnskinnedPerVertexSize] bytes per vertex,
  /// ordered position, normal, UV0, UV1, color, and tangent.
  static UnskinnedAttributeStreams splitUnskinnedAttributes(
    ByteData interleaved,
    int vertexCount,
  ) {
    final expected = vertexCount * kUnskinnedPerVertexSize;
    if (interleaved.lengthInBytes < expected) {
      throw ArgumentError(
        'interleaved holds ${interleaved.lengthInBytes} bytes; expected at '
        'least $expected for $vertexCount unskinned vertices',
      );
    }
    final src = interleaved.buffer.asUint8List(
      interleaved.offsetInBytes,
      interleaved.lengthInBytes,
    );
    final position = Uint8List(positionStreamBytes * vertexCount);
    final normal = Uint8List(normalStreamBytes * vertexCount);
    final texCoord = Uint8List(texCoordStreamBytes * vertexCount);
    final texCoord1 = Uint8List(texCoord1StreamBytes * vertexCount);
    final color = Uint8List(colorStreamBytes * vertexCount);
    final tangent = Uint8List(tangentStreamBytes * vertexCount);
    for (var v = 0; v < vertexCount; v++) {
      final s = v * kUnskinnedPerVertexSize;
      position.setRange(v * 12, v * 12 + 12, src, s);
      normal.setRange(v * 12, v * 12 + 12, src, s + _normalByteOffset);
      texCoord.setRange(v * 8, v * 8 + 8, src, s + _texCoordByteOffset);
      texCoord1.setRange(v * 8, v * 8 + 8, src, s + _texCoord1ByteOffset);
      color.setRange(v * 16, v * 16 + 16, src, s + _colorByteOffset);
      tangent.setRange(v * 16, v * 16 + 16, src, s + _tangentByteOffset);
    }
    return UnskinnedAttributeStreams(
      position: position,
      normal: normal,
      texCoord: texCoord,
      texCoord1: texCoord1,
      color: color,
      tangent: tangent,
    );
  }

  /// Builds the six per-attribute streams directly from structure-of-arrays
  /// attribute lists, filling defaults for absent attributes (normal
  /// `(0, 0, 1)`, texture coordinate `(0, 0)`, color opaque white).
  ///
  /// This is the structure-of-arrays counterpart to [packUnskinned]; it
  /// avoids building an interleaved buffer at all, so a structure-of-arrays
  /// source uploads each stream with no interleave/de-interleave round trip.
  static UnskinnedAttributeStreams unskinnedAttributeStreams({
    required Float32List positions,
    required int vertexCount,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? texCoords1,
    Float32List? colors,
    Float32List? tangents,
  }) {
    _checkLength('positions', positions.length, 3 * vertexCount);
    if (normals != null) {
      _checkLength('normals', normals.length, 3 * vertexCount);
    }
    if (texCoords != null) {
      _checkLength('texCoords', texCoords.length, 2 * vertexCount);
    }
    if (texCoords1 != null) {
      _checkLength('texCoords1', texCoords1.length, 2 * vertexCount);
    }
    if (colors != null) {
      _checkLength('colors', colors.length, 4 * vertexCount);
    }
    if (tangents != null) {
      _checkLength('tangents', tangents.length, 4 * vertexCount);
    }

    // Supplied attributes copy in bulk (setAll on typed data is a memmove);
    // only absent attributes walk per vertex to fill their defaults. Large
    // streamed meshes construct on the UI thread, so per-element Dart loops
    // here are a frame hitch.
    final position = Float32List(3 * vertexCount)..setAll(0, positions);
    final normal = Float32List(3 * vertexCount);
    if (normals != null) {
      normal.setAll(0, normals);
    } else {
      for (var v = 0; v < vertexCount; v++) {
        normal[v * 3 + 2] = 1.0;
      }
    }
    final texCoord = Float32List(2 * vertexCount);
    if (texCoords != null) texCoord.setAll(0, texCoords);
    final texCoord1 = Float32List(2 * vertexCount);
    if (texCoords1 != null) texCoord1.setAll(0, texCoords1);
    final color = Float32List(4 * vertexCount);
    if (colors != null) {
      color.setAll(0, colors);
    } else {
      color.fillRange(0, color.length, 1.0);
    }
    final tangent = Float32List(4 * vertexCount);
    if (tangents != null) tangent.setAll(0, tangents);
    return UnskinnedAttributeStreams(
      position: position.buffer.asUint8List(),
      normal: normal.buffer.asUint8List(),
      texCoord: texCoord.buffer.asUint8List(),
      texCoord1: texCoord1.buffer.asUint8List(),
      color: color.buffer.asUint8List(),
      tangent: tangent.buffer.asUint8List(),
    );
  }

  /// Packs triangle [indices] into the narrowest index buffer that fits.
  ///
  /// Returns the packed bytes and whether a 32-bit element width was
  /// needed; a 16-bit buffer is used when every index is at most
  /// `0xFFFF`. Throws an [ArgumentError] if any index is negative.
  static ({Uint8List bytes, bool is32Bit}) packIndices(List<int> indices) {
    // Already-typed index lists pass through without the validation scan or
    // a repack: their element types cannot hold negatives, and a caller
    // supplying Uint32List has chosen the 32-bit width (a streamed mesh
    // decides this off the UI thread).
    if (indices is Uint16List) {
      return (
        bytes: indices.buffer.asUint8List(
          indices.offsetInBytes,
          indices.lengthInBytes,
        ),
        is32Bit: false,
      );
    }
    if (indices is Uint32List) {
      return (
        bytes: indices.buffer.asUint8List(
          indices.offsetInBytes,
          indices.lengthInBytes,
        ),
        is32Bit: true,
      );
    }
    var maxIndex = 0;
    for (final index in indices) {
      if (index < 0) {
        throw ArgumentError.value(
          index,
          'indices',
          'Index must not be negative',
        );
      }
      if (index > maxIndex) maxIndex = index;
    }
    if (maxIndex > 0xFFFF) {
      return (
        bytes: Uint32List.fromList(indices).buffer.asUint8List(),
        is32Bit: true,
      );
    }
    return (
      bytes: Uint16List.fromList(indices).buffer.asUint8List(),
      is32Bit: false,
    );
  }

  /// Computes area-weighted vertex normals for [positions]
  /// (`3 * vertexCount` floats).
  ///
  /// When [indices] is supplied the positions are treated as an indexed
  /// triangle list; otherwise they are a non-indexed triangle list and
  /// [vertexCount] must be a multiple of three. Each triangle's
  /// unnormalized face normal is accumulated onto its three vertices, so
  /// larger triangles contribute more strongly to shared vertices.
  ///
  /// Assumes Counter-Clockwise (CCW) model-space front-face winding, so the
  /// face normal is the standard cross product of the edges
  /// `(b - a) x (c - a)`.
  static Float32List generateNormals({
    required Float32List positions,
    required int vertexCount,
    List<int>? indices,
  }) {
    _checkLength('positions', positions.length, 3 * vertexCount);
    final normals = Float32List(3 * vertexCount);

    void accumulate(int a, int b, int c) {
      final ax = positions[a * 3],
          ay = positions[a * 3 + 1],
          az = positions[a * 3 + 2];
      final bx = positions[b * 3],
          by = positions[b * 3 + 1],
          bz = positions[b * 3 + 2];
      final cx = positions[c * 3],
          cy = positions[c * 3 + 1],
          cz = positions[c * 3 + 2];
      final e1x = bx - ax, e1y = by - ay, e1z = bz - az;
      final e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
      // Unnormalized right-hand cross product (e1 x e2): its magnitude is
      // twice the triangle area, which weights each face's contribution by its
      // size.
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;
      for (final v in [a, b, c]) {
        normals[v * 3] += nx;
        normals[v * 3 + 1] += ny;
        normals[v * 3 + 2] += nz;
      }
    }

    if (indices != null) {
      if (indices.length % 3 != 0) {
        throw ArgumentError(
          'indices has ${indices.length} entries; a triangle list needs a '
          'multiple of three',
        );
      }
      for (var t = 0; t < indices.length; t += 3) {
        accumulate(indices[t], indices[t + 1], indices[t + 2]);
      }
    } else {
      if (vertexCount % 3 != 0) {
        throw ArgumentError(
          'A non-indexed triangle list needs a vertex count that is a '
          'multiple of three; got $vertexCount',
        );
      }
      for (var v = 0; v < vertexCount; v += 3) {
        accumulate(v, v + 1, v + 2);
      }
    }

    for (var v = 0; v < vertexCount; v++) {
      final x = normals[v * 3], y = normals[v * 3 + 1], z = normals[v * 3 + 2];
      final length = math.sqrt(x * x + y * y + z * z);
      if (length > 1e-12) {
        normals[v * 3] = x / length;
        normals[v * 3 + 1] = y / length;
        normals[v * 3 + 2] = z / length;
      } else {
        normals[v * 3] = 0.0;
        normals[v * 3 + 1] = 0.0;
        normals[v * 3 + 2] = 1.0;
      }
    }
    return normals;
  }

  static void _checkLength(String name, int actual, int expected) {
    if (actual != expected) {
      throw ArgumentError(
        '$name has $actual floats; expected $expected for the given vertex '
        'count',
      );
    }
  }
}
