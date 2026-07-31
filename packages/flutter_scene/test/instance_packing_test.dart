import 'dart:typed_data';

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

    test('sorts each winding group back to front', () {
      final mirrored = Matrix4.identity()
        ..scaleByVector3(Vector3(-1, 1, 1))
        ..setTranslationRaw(4, 0, 0);
      final packed = packInstanceTransforms(Matrix4.identity(), [
        Matrix4.translation(Vector3(2, 0, 0)),
        mirrored,
        Matrix4.translation(Vector3(8, 0, 0)),
        Matrix4.identity()
          ..scaleByVector3(Vector3(-1, 1, 1))
          ..setTranslationRaw(12, 0, 0),
      ], sortBackToFrontFrom: Vector3.zero());

      expect(packed.ccwCount, 2);
      expect(packed.cwCount, 2);
      expect(packed.ccw[12], 8);
      expect(packed.ccw[28], 2);
      expect(packed.cw[12], 12);
      expect(packed.cw[28], 4);
    });
  });

  group('packInstanceData', () {
    test('packs transform and color in each 20-float record', () {
      final packed = packInstanceData(
        Matrix4.translation(Vector3(1, 0, 0)),
        [Matrix4.translation(Vector3(2, 0, 0))],
        [Vector4(0.2, 0.4, 0.6, 0.8)],
      );

      expect(packed.ccwCount, 1);
      expect(packed.ccw[12], 3);
      expect(packed.ccw.sublist(16, 20), everyElement(isA<double>()));
      expect(packed.ccw[16], closeTo(0.2, 1e-6));
      expect(packed.ccw[17], closeTo(0.4, 1e-6));
      expect(packed.ccw[18], closeTo(0.6, 1e-6));
      expect(packed.ccw[19], closeTo(0.8, 1e-6));
    });

    test('sorts colors with their transforms', () {
      final packed = packInstanceData(
        Matrix4.identity(),
        [
          Matrix4.translation(Vector3(2, 0, 0)),
          Matrix4.translation(Vector3(8, 0, 0)),
        ],
        [Vector4(1, 0, 0, 1), Vector4(0, 1, 0, 1)],
        sortBackToFrontFrom: Vector3.zero(),
      );

      expect(packed.ccw[12], 8);
      expect(packed.ccw.sublist(16, 20), [0, 1, 0, 1]);
      expect(packed.ccw[32], 2);
      expect(packed.ccw.sublist(36, 40), [1, 0, 0, 1]);
    });

    test('packs only selected instance indices', () {
      final packed = packInstanceData(
        Matrix4.identity(),
        [
          Matrix4.translation(Vector3(2, 0, 0)),
          Matrix4.translation(Vector3(8, 0, 0)),
          Matrix4.translation(Vector3(4, 0, 0)),
        ],
        [Vector4(1, 0, 0, 1), Vector4(0, 1, 0, 1), Vector4(0, 0, 1, 1)],
        indices: const [2, 0],
        sortBackToFrontFrom: Vector3.zero(),
      );

      expect(packed.ccwCount, 2);
      expect(packed.ccw[12], 4);
      expect(packed.ccw.sublist(16, 20), [0, 0, 1, 1]);
      expect(packed.ccw[32], 2);
      expect(packed.ccw.sublist(36, 40), [1, 0, 0, 1]);
    });

    test('packs retained groups without a flattened transform list', () {
      final mirrored = Matrix4.identity()..scaleByVector3(Vector3(-1, 1, 1));
      final packed = packInstanceDataBatches([
        InstanceDataBatch(
          nodeTransform: Matrix4.translation(Vector3(10, 0, 0)),
          instances: [Matrix4.translation(Vector3(2, 0, 0)), mirrored],
          colors: [Vector4(1, 0, 0, 1), Vector4(0, 1, 0, 1)],
          nodeWindingFlipped: false,
          instanceWindingFlipped: const [false, true],
        ),
        InstanceDataBatch.single(
          nodeTransform: Matrix4.translation(Vector3(20, 0, 0)),
          nodeWindingFlipped: false,
        ),
      ]);

      expect(packed.ccwCount, 2);
      expect(packed.cwCount, 1);
      expect(packed.ccw[12], 12);
      expect(packed.ccw.sublist(16, 20), [1, 0, 0, 1]);
      expect(packed.ccw[32], 20);
      expect(packed.ccw.sublist(36, 40), [1, 1, 1, 1]);
      expect(packed.cw[12], 10);
      expect(packed.cw.sublist(16, 20), [0, 1, 0, 1]);
    });

    test('reuses scratch storage across immediate uploads', () {
      final scratch = InstancePackingScratch();
      final first = packInstanceData(
        Matrix4.identity(),
        [Matrix4.translation(Vector3(2, 0, 0))],
        [Vector4(1, 0, 0, 1)],
        scratch: scratch,
      );

      final second = packInstanceData(
        Matrix4.identity(),
        [Matrix4.translation(Vector3(8, 0, 0))],
        [Vector4(0, 1, 0, 1)],
        scratch: scratch,
      );

      expect(first.ccw[12], 8);
      expect(second.ccw[12], 8);
      expect(second.ccw.sublist(16, 20), [0, 1, 0, 1]);
    });

    test('copies selected cached records by winding group', () {
      final records = Float32List(3 * 20);
      for (var i = 0; i < 3; i++) {
        Matrix4.translation(
          Vector3(i * 4, 0, 0),
        ).copyIntoArray(records, i * 20);
        records.setAll(i * 20 + 16, [i.toDouble(), 0, 0, 1]);
      }
      final packed = packInstanceDataBatches([
        InstanceDataBatch.cached(
          packedWorldData: records,
          packedWindingFlipped: Uint8List.fromList([0, 1, 0]),
          indices: const [2, 1],
        ),
      ]);

      expect(packed.ccwCount, 1);
      expect(packed.cwCount, 1);
      expect(packed.ccw[12], 8);
      expect(packed.ccw[16], 2);
      expect(packed.cw[12], 4);
      expect(packed.cw[16], 1);
    });

    test('copies homogeneous cached records contiguously', () {
      final records = Float32List(2 * 20);
      Matrix4.translation(Vector3(3, 0, 0)).copyIntoArray(records, 0);
      records.setAll(16, [1, 0, 0, 1]);
      Matrix4.translation(Vector3(7, 0, 0)).copyIntoArray(records, 20);
      records.setAll(36, [0, 1, 0, 1]);

      final packed = packInstanceDataBatches([
        InstanceDataBatch.cached(
          packedWorldData: records,
          packedWindingFlipped: Uint8List(2),
        ),
      ]);

      expect(packed.ccw, records);
      expect(packed.cw, isEmpty);
    });

    test('copies cached transform records without color lanes', () {
      final records = Float32List(2 * 20);
      Matrix4.translation(Vector3(3, 0, 0)).copyIntoArray(records, 0);
      Matrix4.translation(Vector3(7, 0, 0)).copyIntoArray(records, 20);
      final packed = packInstanceTransformBatches([
        InstanceDataBatch.cached(
          packedWorldData: records,
          packedWindingFlipped: Uint8List.fromList([1, 0]),
        ),
      ]);

      expect(packed.ccwCount, 1);
      expect(packed.cwCount, 1);
      expect(packed.ccw[12], 7);
      expect(packed.cw[12], 3);
    });
  });
}
