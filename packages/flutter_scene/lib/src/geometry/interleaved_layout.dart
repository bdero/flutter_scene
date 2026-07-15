import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/constants.dart';

/// Translates structure-of-arrays vertex attributes into the interleaved
/// unskinned vertex layout.
///
/// The interleaved layout packs every attribute of a vertex contiguously:
/// 12 floats (48 bytes) per vertex, ordered position (3), normal (3),
/// texture coordinates (2), color (4).
///
/// The geometry construction API accepts attributes as independent typed
/// arrays; this adapter packs them into the single interleaved buffer the
/// built-in pipelines consume. It is intentionally the one place that
/// depends on the interleaved layout, so the rest of the geometry API can
/// move to independent attribute buffers later without an API change.
///
/// Every method here is pure and free of GPU resources, so the packing
/// can be exercised without a render context.
/// Four tightly packed per-attribute unskinned vertex streams (structure of
/// arrays): [position] (12 bytes/vertex), [normal] (12), [texCoord] (8), and
/// [color] (16). Each is contiguous, so the depth-style passes bind only
/// [position] and a dynamic update can rewrite only the changed attribute.
class UnskinnedAttributeStreams {
  const UnskinnedAttributeStreams({
    required this.position,
    required this.normal,
    required this.texCoord,
    required this.color,
  });

  final Uint8List position;
  final Uint8List normal;
  final Uint8List texCoord;
  final Uint8List color;
}

abstract final class InterleavedLayoutAdapter {
  /// Floats per vertex in the interleaved unskinned layout.
  static const int floatsPerVertex = kUnskinnedPerVertexSize ~/ 4;

  /// Packs [vertexCount] vertices of structure-of-arrays attributes into
  /// one interleaved unskinned vertex buffer.
  ///
  /// [positions] is required and must hold `3 * vertexCount` floats.
  /// [normals] (`3 * vertexCount`), [texCoords] (`2 * vertexCount`), and
  /// [colors] (`4 * vertexCount`) are optional. Absent attributes are
  /// filled with defaults: normal `(0, 0, 1)`, texture coordinate
  /// `(0, 0)`, color opaque white.
  static Uint8List packUnskinned({
    required Float32List positions,
    required int vertexCount,
    Float32List? normals,
    Float32List? texCoords,
    Float32List? colors,
  }) {
    _checkLength('positions', positions.length, 3 * vertexCount);
    if (normals != null) {
      _checkLength('normals', normals.length, 3 * vertexCount);
    }
    if (texCoords != null) {
      _checkLength('texCoords', texCoords.length, 2 * vertexCount);
    }
    if (colors != null) {
      _checkLength('colors', colors.length, 4 * vertexCount);
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
      if (colors != null) {
        out[o + 8] = colors[v * 4 + 0];
        out[o + 9] = colors[v * 4 + 1];
        out[o + 10] = colors[v * 4 + 2];
        out[o + 11] = colors[v * 4 + 3];
      } else {
        out[o + 8] = 1.0;
        out[o + 9] = 1.0;
        out[o + 10] = 1.0;
        out[o + 11] = 1.0;
      }
    }
    return out.buffer.asUint8List();
  }

  /// Bytes per vertex of each de-interleaved unskinned attribute stream:
  /// position (`vec3`), normal (`vec3`), texture coordinates (`vec2`), color
  /// (`vec4`). Their sum is [kUnskinnedPerVertexSize].
  static const int positionStreamBytes = 12;
  static const int normalStreamBytes = 12;
  static const int texCoordStreamBytes = 8;
  static const int colorStreamBytes = 16;

  /// Byte offset of each attribute within the interleaved 48-byte vertex.
  static const int _normalByteOffset = 12;
  static const int _texCoordByteOffset = 24;
  static const int _colorByteOffset = 32;

  /// The `.fscene` payload layout string for a de-interleaved
  /// (structure-of-arrays) unskinned vertex buffer: the four attribute
  /// streams concatenated, position then normal then texcoord then color. The
  /// older `unskinned` layout is the interleaved form.
  static const String unskinnedSoaLayout = 'unskinned_soa';

  /// Concatenates the four per-attribute streams into one buffer, position
  /// then normal then texcoord then color. This is the on-disk
  /// structure-of-arrays vertex payload; [sliceUnskinnedStreams] is the
  /// inverse.
  static Uint8List concatUnskinnedStreams(UnskinnedAttributeStreams streams) {
    final out = Uint8List(
      streams.position.length +
          streams.normal.length +
          streams.texCoord.length +
          streams.color.length,
    );
    var offset = 0;
    out.setAll(offset, streams.position);
    offset += streams.position.length;
    out.setAll(offset, streams.normal);
    offset += streams.normal.length;
    out.setAll(offset, streams.texCoord);
    offset += streams.texCoord.length;
    out.setAll(offset, streams.color);
    return out;
  }

  /// Slices a concatenated structure-of-arrays unskinned vertex payload back
  /// into its four attribute streams as views into [soa] (no copy). The
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
      color: take(colorStreamBytes),
    );
  }

  /// Splits one interleaved unskinned vertex buffer into the four tightly
  /// packed per-attribute streams.
  ///
  /// The interleaved input is [kUnskinnedPerVertexSize] (48) bytes per
  /// vertex, ordered position, normal, texture coordinates, color. Pure, so
  /// it can run off the render isolate.
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
    final color = Uint8List(colorStreamBytes * vertexCount);
    for (var v = 0; v < vertexCount; v++) {
      final s = v * kUnskinnedPerVertexSize;
      position.setRange(v * 12, v * 12 + 12, src, s);
      normal.setRange(v * 12, v * 12 + 12, src, s + _normalByteOffset);
      texCoord.setRange(v * 8, v * 8 + 8, src, s + _texCoordByteOffset);
      color.setRange(v * 16, v * 16 + 16, src, s + _colorByteOffset);
    }
    return UnskinnedAttributeStreams(
      position: position,
      normal: normal,
      texCoord: texCoord,
      color: color,
    );
  }

  /// Builds the four per-attribute streams directly from structure-of-arrays
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
    Float32List? colors,
  }) {
    _checkLength('positions', positions.length, 3 * vertexCount);
    if (normals != null) {
      _checkLength('normals', normals.length, 3 * vertexCount);
    }
    if (texCoords != null) {
      _checkLength('texCoords', texCoords.length, 2 * vertexCount);
    }
    if (colors != null) {
      _checkLength('colors', colors.length, 4 * vertexCount);
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
    final color = Float32List(4 * vertexCount);
    if (colors != null) {
      color.setAll(0, colors);
    } else {
      color.fillRange(0, color.length, 1.0);
    }
    return UnskinnedAttributeStreams(
      position: position.buffer.asUint8List(),
      normal: normal.buffer.asUint8List(),
      texCoord: texCoord.buffer.asUint8List(),
      color: color.buffer.asUint8List(),
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
  /// larger faces contribute proportionally; the result is normalized
  /// per vertex. Vertices touched by no (or only degenerate) triangles
  /// receive a default normal of `(0, 0, 1)`.
  ///
  /// Normals point out of the face the engine renders as front. The
  /// engine's front faces wind clockwise in model space (the hand-built
  /// primitives' convention; rasterization is Y-down, which flips the
  /// apparent winding to counter-clockwise), so the face normal is the
  /// REVERSED right-hand cross product of the edges.
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
      // Unnormalized cross product (reversed for the engine's clockwise
      // front-face winding): its magnitude is twice the triangle area,
      // which weights each face's contribution by its size.
      final nx = e2y * e1z - e2z * e1y;
      final ny = e2z * e1x - e2x * e1z;
      final nz = e2x * e1y - e2y * e1x;
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
