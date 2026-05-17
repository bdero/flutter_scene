// Covers InterleavedLayoutAdapter: structure-of-arrays attributes packed
// into the interleaved unskinned vertex layout, index-buffer width
// selection, and area-weighted normal generation. Pure logic, so these
// run without a Flutter GPU context.

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
    test('generates +Z for a counter-clockwise triangle in the XY plane', () {
      final normals = InterleavedLayoutAdapter.generateNormals(
        positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
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
        positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
        vertexCount: 3,
      );
      expect(normals[2], closeTo(1, 1e-6));
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
