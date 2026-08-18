import 'package:flutter_scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Skin _skinWithJoints(int jointCount) {
  final skin = Skin();
  for (var i = 0; i < jointCount; i++) {
    skin.joints.add(Node());
    skin.inverseBindMatrices.add(Matrix4.identity());
  }
  return skin;
}

void main() {
  group('joints texture sizing', () {
    // A joint matrix spans four consecutive texels of one row, so an edge that
    // is not a multiple of four makes clampToEdge fold the last two samples
    // back onto the row and duplicates matrix columns.
    test('edge length is a multiple of four for small joint counts', () {
      for (var jointCount = 0; jointCount <= 8; jointCount++) {
        expect(
          _skinWithJoints(jointCount).getTextureWidth() % 4,
          0,
          reason: '$jointCount joints',
        );
      }
    });

    test('edge length holds every joint matrix', () {
      for (final jointCount in [0, 1, 2, 3, 4, 5, 16, 17, 60]) {
        final edge = _skinWithJoints(jointCount).getTextureWidth();
        expect(edge * edge, greaterThanOrEqualTo(jointCount * 4));
      }
    });

    test('edge length is a power of two', () {
      for (final jointCount in [0, 1, 3, 7, 33, 100]) {
        final edge = _skinWithJoints(jointCount).getTextureWidth();
        expect(edge & (edge - 1), 0, reason: '$jointCount joints -> $edge');
      }
    });
  });
}
