// Covers the vertex and index conversions a geometry payload from a format 5
// or older document takes when realized: Z reflection of positions, normals,
// and tangents (with the tangent sign), and the triangle index swap that keeps
// the reflected triangles front facing.

import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<double> floats) =>
    Uint8List.sublistView(Float32List.fromList(floats));

List<double> _floats(Uint8List bytes) =>
    Float32List.sublistView(Uint8List.fromList(bytes));

void main() {
  group('legacy left-handed geometry', () {
    test(
      'interleaved unskinned vertices reflect position, normal, tangent',
      () {
        final vertex = [
          1.0, 2.0, 3.0, // position
          0.0, 0.5, 0.75, // normal
          0.25, 0.75, // tex_coords_0
          0.5, 0.5, // tex_coords_1
          1.0, 0.5, 0.25, 1.0, // color
          0.0, 0.75, -0.5, 1.0, // tangent
        ];
        final out = ResourceRealizer.reflectInterleavedZ(
          _bytes(vertex),
          1,
          skinned: false,
        );
        expect(out, [
          1.0, 2.0, -3.0, //
          0.0, 0.5, -0.75, //
          0.25, 0.75, 0.5, 0.5, //
          1.0, 0.5, 0.25, 1.0, //
          0.0, 0.75, 0.5, -1.0,
        ]);
      },
    );

    test('interleaved skinned vertices keep joints and weights', () {
      final vertex = [
        ...List<double>.generate(18, (i) => i + 1.0),
        1.0, 2.0, 3.0, 4.0, // joints
        0.5, 0.25, 0.125, 0.125, // weights
      ];
      final out = ResourceRealizer.reflectInterleavedZ(
        _bytes(vertex),
        1,
        skinned: true,
      );
      final expected = List<double>.of(vertex);
      for (final i in [2, 5, 16, 17]) {
        expected[i] = -expected[i];
      }
      expect(out, expected);
    });

    test('a zero tangent sign stays zero', () {
      final vertex = List<double>.filled(18, 0.0);
      final out = ResourceRealizer.reflectInterleavedZ(
        _bytes(vertex),
        1,
        skinned: false,
      );
      expect(out[17], 0.0);
      expect(out[17].isNegative, isFalse);
    });

    test('attribute streams reflect position, normal, tangent', () {
      final streams = UnskinnedAttributeStreams(
        position: _bytes([1, 2, 3, -4, 5, -6]),
        normal: _bytes([0, 0, 1, 1, 0, 0]),
        texCoord: _bytes([0.125, 0.25, 0.5, 0.75]),
        texCoord1: _bytes([0, 0, 0, 0]),
        color: _bytes([1, 1, 1, 1, 1, 1, 1, 1]),
        tangent: _bytes([1, 0, 0, 1, 0, 0, 1, -1]),
      );
      final out = ResourceRealizer.reflectSoaZ(streams);
      expect(_floats(out.position), [1, 2, -3, -4, 5, 6]);
      expect(_floats(out.normal), [0, 0, -1, 1, 0, 0]);
      expect(_floats(out.tangent), [1, 0, 0, -1, 0, 0, -1, 1]);
      expect(_floats(out.texCoord), _floats(streams.texCoord));
      // The source streams are left untouched.
      expect(_floats(streams.position), [1, 2, 3, -4, 5, -6]);
    });

    test('indices swap when exactly one legacy flag applies', () {
      bool swapped(bool winding, bool leftHanded) =>
          ResourceRealizer.legacyIndicesSwapped(
            legacyWinding: winding,
            legacyLeftHanded: leftHanded,
          );
      // Format 5, reflected only.
      expect(swapped(false, true), isTrue);
      // Format 4, reflected and wound clockwise, which cancel.
      expect(swapped(true, true), isFalse);
      expect(swapped(false, false), isFalse);
    });

    test('a triangle swap reverses each triangle in 16 and 32 bits', () {
      final u16 = Uint16List.fromList([0, 1, 2, 3, 4, 5]);
      final swapped16 = ResourceRealizer.swapTriangleWinding(
        Uint8List.sublistView(u16),
        uint32: false,
      );
      expect(Uint16List.sublistView(swapped16), [0, 2, 1, 3, 5, 4]);
      expect(u16, [0, 1, 2, 3, 4, 5]);

      final u32 = Uint32List.fromList([7, 70000, 9]);
      final swapped32 = ResourceRealizer.swapTriangleWinding(
        Uint8List.sublistView(u32),
        uint32: true,
      );
      expect(Uint32List.sublistView(swapped32), [7, 9, 70000]);
    });
  });
}
