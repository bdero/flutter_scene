// Covers InterleavedLayoutAdapter: structure-of-arrays attributes packed
// into the interleaved unskinned vertex layout, index-buffer width
// selection, and area-weighted normal generation. Pure logic, so these
// run without a Flutter GPU context.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('packUnskinned', () {
    test('interleaves every supplied attribute', () {
      // All values are exactly representable as 32-bit floats so the
      // packed bytes can be compared without a tolerance.
      final bytes = InterleavedLayoutAdapter.packUnskinned(
        positions: Float32List.fromList([1, 2, 3, 4, 5, 6]),
        vertexCount: 2,
        normals: Float32List.fromList([0, 1, 0, 1, 0, 0]),
        texCoords: Float32List.fromList([0.5, 0.25, 0.75, 0.125]),
        colors: Float32List.fromList([1, 0, 0, 1, 0, 1, 0, 0.5]),
      );
      final floats = Float32List.sublistView(bytes);
      expect(floats, hasLength(2 * InterleavedLayoutAdapter.floatsPerVertex));
      // Vertex 0.
      expect(floats.sublist(0, 12), [1, 2, 3, 0, 1, 0, 0.5, 0.25, 1, 0, 0, 1]);
      // Vertex 1.
      expect(floats.sublist(12, 24), [
        4,
        5,
        6,
        1,
        0,
        0,
        0.75,
        0.125,
        0,
        1,
        0,
        0.5,
      ]);
    });

    test('fills defaults for absent attributes', () {
      final bytes = InterleavedLayoutAdapter.packUnskinned(
        positions: Float32List.fromList([1, 2, 3]),
        vertexCount: 1,
      );
      final floats = Float32List.sublistView(bytes);
      // Position, default normal (0,0,1), default uv (0,0), default
      // color opaque white.
      expect(floats, [1, 2, 3, 0, 0, 1, 0, 0, 1, 1, 1, 1]);
    });

    test('throws when an attribute length mismatches the vertex count', () {
      expect(
        () => InterleavedLayoutAdapter.packUnskinned(
          positions: Float32List.fromList([1, 2, 3]),
          vertexCount: 1,
          normals: Float32List.fromList([0, 0, 1, 0, 0, 1]),
        ),
        throwsArgumentError,
      );
    });
  });

  group('splitUnskinnedAttributes', () {
    test('separates the interleaved buffer into four per-attribute streams', () {
      // Two vertices, all attributes distinct and exactly float-representable.
      final interleaved = InterleavedLayoutAdapter.packUnskinned(
        positions: Float32List.fromList([1, 2, 3, 4, 5, 6]),
        vertexCount: 2,
        normals: Float32List.fromList([7, 8, 9, 10, 11, 12]),
        texCoords: Float32List.fromList([13, 14, 15, 16]),
        colors: Float32List.fromList([17, 18, 19, 20, 21, 22, 23, 24]),
      );
      final streams = InterleavedLayoutAdapter.splitUnskinnedAttributes(
        ByteData.sublistView(interleaved),
        2,
      );

      expect(Float32List.sublistView(streams.position), [1, 2, 3, 4, 5, 6]);
      expect(Float32List.sublistView(streams.normal), [7, 8, 9, 10, 11, 12]);
      expect(Float32List.sublistView(streams.texCoord), [13, 14, 15, 16]);
      expect(Float32List.sublistView(streams.color), [
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
      ]);
    });

    test('throws when the interleaved buffer is too short', () {
      expect(
        () => InterleavedLayoutAdapter.splitUnskinnedAttributes(
          ByteData(48),
          2, // needs 96 bytes
        ),
        throwsArgumentError,
      );
    });
  });

  group('unskinnedAttributeStreams', () {
    test('packs structure-of-arrays attributes with defaults', () {
      final streams = InterleavedLayoutAdapter.unskinnedAttributeStreams(
        positions: Float32List.fromList([1, 2, 3]),
        vertexCount: 1,
      );
      expect(Float32List.sublistView(streams.position), [1, 2, 3]);
      // Defaults: normal (0,0,1), texcoord (0,0), color opaque white.
      expect(Float32List.sublistView(streams.normal), [0, 0, 1]);
      expect(Float32List.sublistView(streams.texCoord), [0, 0]);
      expect(Float32List.sublistView(streams.color), [1, 1, 1, 1]);
    });

    test('round-trips through split back to the same per-attribute bytes', () {
      final positions = Float32List.fromList([1, 2, 3, 4, 5, 6]);
      final normals = Float32List.fromList([7, 8, 9, 10, 11, 12]);
      final texCoords = Float32List.fromList([13, 14, 15, 16]);
      final colors = Float32List.fromList([17, 18, 19, 20, 21, 22, 23, 24]);
      final direct = InterleavedLayoutAdapter.unskinnedAttributeStreams(
        positions: positions,
        vertexCount: 2,
        normals: normals,
        texCoords: texCoords,
        colors: colors,
      );
      final interleaved = InterleavedLayoutAdapter.packUnskinned(
        positions: positions,
        vertexCount: 2,
        normals: normals,
        texCoords: texCoords,
        colors: colors,
      );
      final viaSplit = InterleavedLayoutAdapter.splitUnskinnedAttributes(
        ByteData.sublistView(interleaved),
        2,
      );
      expect(direct.position, viaSplit.position);
      expect(direct.normal, viaSplit.normal);
      expect(direct.texCoord, viaSplit.texCoord);
      expect(direct.color, viaSplit.color);
    });
  });

  group('packIndices', () {
    test('uses a 16-bit buffer when every index fits', () {
      final packed = InterleavedLayoutAdapter.packIndices([0, 1, 2, 0xFFFF]);
      expect(packed.is32Bit, isFalse);
      expect(packed.bytes, hasLength(4 * 2));
      expect(Uint16List.sublistView(packed.bytes), [0, 1, 2, 0xFFFF]);
    });

    test('uses a 32-bit buffer when an index exceeds 16 bits', () {
      final packed = InterleavedLayoutAdapter.packIndices([0, 70000]);
      expect(packed.is32Bit, isTrue);
      expect(packed.bytes, hasLength(2 * 4));
      expect(Uint32List.sublistView(packed.bytes), [0, 70000]);
    });

    test('throws on a negative index', () {
      expect(
        () => InterleavedLayoutAdapter.packIndices([0, -1, 2]),
        throwsArgumentError,
      );
    });
  });

  group('generateNormals', () {
    test('generates +Z for a front-face-wound triangle in the XY plane', () {
      // Wound like the cuboid's +Z face (clockwise in model space, the
      // engine's front-face convention), so the normal points at the
      // viewer of that face.
      final normals = InterleavedLayoutAdapter.generateNormals(
        positions: Float32List.fromList([1, -1, 0, -1, -1, 0, 1, 1, 0]),
        vertexCount: 3,
        indices: [0, 1, 2],
      );
      for (var v = 0; v < 3; v++) {
        expect(normals[v * 3 + 0], closeTo(0, 1e-6));
        expect(normals[v * 3 + 1], closeTo(0, 1e-6));
        expect(normals[v * 3 + 2], closeTo(1, 1e-6));
      }
    });

    test('handles a non-indexed triangle list', () {
      final normals = InterleavedLayoutAdapter.generateNormals(
        positions: Float32List.fromList([1, -1, 0, -1, -1, 0, 1, 1, 0]),
        vertexCount: 3,
      );
      expect(normals[2], closeTo(1, 1e-6));
    });

    test('matches analytic normals on a curved front-face-wound grid', () {
      // A dome z = b(1 - nx^2)(1 - ny^2) over [-1, 1]^2, wound per the
      // engine front-face convention (the same construction as the
      // widget-texture example's screen). The generated smooth normals
      // must agree with the analytic surface normals, including SIGN
      // (pointing out of the bulge, toward the front-face viewer).
      const n = 8;
      const bulge = 0.3;
      final positions = Float32List((n + 1) * (n + 1) * 3);
      for (var r = 0; r <= n; r++) {
        final ny = r / n * 2 - 1;
        for (var c = 0; c <= n; c++) {
          final nx = c / n * 2 - 1;
          final v = r * (n + 1) + c;
          positions[v * 3] = nx;
          positions[v * 3 + 1] = ny;
          positions[v * 3 + 2] = bulge * (1 - nx * nx) * (1 - ny * ny);
        }
      }
      final indices = <int>[];
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          final bl = r * (n + 1) + c;
          final br = bl + 1;
          final tl = bl + n + 1;
          final tr = tl + 1;
          indices.addAll([br, bl, tr, tr, bl, tl]);
        }
      }
      final normals = InterleavedLayoutAdapter.generateNormals(
        positions: positions,
        vertexCount: (n + 1) * (n + 1),
        indices: indices,
      );
      for (var r = 0; r <= n; r++) {
        final ny = r / n * 2 - 1;
        for (var c = 0; c <= n; c++) {
          final nx = c / n * 2 - 1;
          final v = r * (n + 1) + c;
          final dzdx = bulge * -2 * nx * (1 - ny * ny);
          final dzdy = bulge * (1 - nx * nx) * -2 * ny;
          final inverseLength = 1 / sqrt(dzdx * dzdx + dzdy * dzdy + 1);
          final dot =
              normals[v * 3] * -dzdx * inverseLength +
              normals[v * 3 + 1] * -dzdy * inverseLength +
              normals[v * 3 + 2] * inverseLength;
          expect(
            dot,
            greaterThan(0.98),
            reason:
                'vertex ($nx, $ny) generated normal disagrees with '
                'the analytic surface normal',
          );
        }
      }
    });

    test('falls back to (0, 0, 1) for a vertex touched by no triangle', () {
      // Four vertices, one triangle referencing only the first three.
      final normals = InterleavedLayoutAdapter.generateNormals(
        positions: Float32List.fromList([
          0, 0, 0, 1, 0, 0, 0, 1, 0, 9, 9, 9, //
        ]),
        vertexCount: 4,
        indices: [0, 1, 2],
      );
      expect(normals.sublist(9, 12), [0, 0, 1]);
    });

    test('throws when an indexed list is not a multiple of three', () {
      expect(
        () => InterleavedLayoutAdapter.generateNormals(
          positions: Float32List.fromList([0, 0, 0, 1, 0, 0]),
          vertexCount: 2,
          indices: [0, 1],
        ),
        throwsArgumentError,
      );
    });
  });
}
