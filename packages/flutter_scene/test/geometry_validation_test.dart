// Upload- and construction-time validation on the low-level geometry entry
// points. These checks throw before any GPU access, so they run headlessly
// without a Flutter GPU context.

import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uploadVertexData stride validation', () {
    test('skinned upload throws on a wrong stride', () {
      // 96 bytes per vertex (a legacy layout missing UV1), where the skinned
      // layout is 104. Would otherwise upload and render as washed-out colors
      // and see-through faces.
      final wrong = ByteData(96 * 3);
      expect(
        () => SkinnedGeometry().uploadVertexData(wrong, 3, null),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('104-byte'), contains('joints 4, weights 4')),
          ),
        ),
      );
    });

    test('unskinned upload throws on a wrong stride', () {
      // 72-byte layout given 80 bytes per vertex.
      final wrong = ByteData(80 * 4);
      expect(
        () => UnskinnedGeometry().uploadVertexData(wrong, 4, null),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('72-byte'),
          ),
        ),
      );
    });

    test('a too-long buffer is rejected, not just a too-short one', () {
      // Right stride, wrong vertexCount: 104 * 5 bytes described as 3 vertices.
      final tooLong = ByteData(104 * 5);
      expect(
        () => SkinnedGeometry().uploadVertexData(tooLong, 3, null),
        throwsArgumentError,
      );
    });
  });

  group('setCustomAttribute arity validation', () {
    test('throws when data length does not match vertexCount * components', () {
      final g = UnskinnedGeometry();
      // Set the vertex count headlessly (no GPU); an empty stream list binds
      // nothing but records the count the arity check reads.
      g.setVertexStreams(const [], 4);
      // 4 vertices at 2 components needs 8 floats; supply 9.
      expect(
        () => g.setCustomAttribute('a_wind', Float32List(9), components: 2),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('9 floats'), contains('needs 8')),
          ),
        ),
      );
    });

    test('the components guard still throws for an out-of-range count', () {
      final g = UnskinnedGeometry();
      g.setVertexStreams(const [], 4);
      expect(
        () => g.setCustomAttribute('a', Float32List(20), components: 5),
        throwsArgumentError,
      );
    });
  });
}
