import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('packInstanceTransforms', () {
    test('packs world transforms column-major, 16 floats per instance', () {
      final node = Matrix4.translation(Vector3(1, 2, 3));
      final instances = <Matrix4>[
        Matrix4.translation(Vector3(10, 0, 0)),
        (Matrix4.translation(Vector3(0, 10, 0)) * Matrix4.rotationY(0.5))
            as Matrix4,
      ];
      final packed = packInstanceTransforms(node, instances);
      expect(packed.cwCount, 0);
      expect(packed.ccwCount, 2);
      for (var i = 0; i < instances.length; i++) {
        final expected = (node * instances[i]) as Matrix4;
        expect(
          packed.ccw.sublist(i * 16, i * 16 + 16),
          expected.storage,
          reason:
              'instance $i must be the node-times-instance world '
              'transform in column-major order',
        );
      }
    });

    test('splits mirrored instances into the clockwise group', () {
      final node = Matrix4.identity();
      final mirrored = Matrix4.identity()..scaleByVector3(Vector3(-1, 1, 1));
      final packed = packInstanceTransforms(node, [
        Matrix4.identity(),
        mirrored,
        Matrix4.identity(),
      ]);
      expect(packed.ccwCount, 2);
      expect(packed.cwCount, 1);
      expect(packed.cw.sublist(0, 16), mirrored.storage);
    });

    test('node winding parity inverts the split', () {
      final node = Matrix4.identity()..scaleByVector3(Vector3(-1, 1, 1));
      final mirrored = Matrix4.identity()..scaleByVector3(Vector3(-1, 1, 1));
      final packed = packInstanceTransforms(node, [
        Matrix4.identity(), // combined parity: flipped (node only)
        mirrored, // combined parity: unflipped (double mirror)
      ], nodeWindingFlipped: true);
      expect(packed.cwCount, 1);
      expect(packed.ccwCount, 1);
      // The double-mirrored instance lands in the ccw group with its full
      // world transform.
      final world = (node * mirrored) as Matrix4;
      expect(packed.ccw.sublist(0, 16), world.storage);
    });

    test('handles an empty instance list', () {
      final packed = packInstanceTransforms(Matrix4.identity(), const []);
      expect(packed.ccwCount, 0);
      expect(packed.cwCount, 0);
    });
  });
}
