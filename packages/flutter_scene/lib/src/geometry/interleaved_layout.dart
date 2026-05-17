import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene_importer/constants.dart';

/// Translates structure-of-arrays vertex attributes into the interleaved
/// unskinned vertex layout.
///
/// The interleaved layout packs every attribute of a vertex contiguously:
/// 12 floats (48 bytes) per vertex, ordered position (3), normal (3),
/// texture coordinates (2), color (4).
///
/// This is the translation layer described in `docs/dynamic_geometry.md`.
/// The geometry construction API accepts attributes as independent typed
/// arrays; this adapter packs them into the single interleaved buffer the
/// built-in pipelines consume. It is intentionally the one place that
/// depends on the interleaved layout, so the rest of the geometry API can
/// move to independent attribute buffers later without an API change.
///
/// Every method here is pure and free of GPU resources, so the packing
/// can be exercised without a render context.
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

  /// Packs triangle [indices] into the narrowest index buffer that fits.
  ///
  /// Returns the packed bytes and whether a 32-bit element width was
  /// needed; a 16-bit buffer is used when every index is at most
  /// `0xFFFF`. Throws an [ArgumentError] if any index is negative.
  static ({Uint8List bytes, bool is32Bit}) packIndices(List<int> indices) {
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
      // Unnormalized cross product: its magnitude is twice the triangle
      // area, which weights each face's contribution by its size.
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
