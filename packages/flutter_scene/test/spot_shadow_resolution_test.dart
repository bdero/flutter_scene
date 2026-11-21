import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' show ShadowCasterFaces, SpotLight;
import 'package:flutter_scene/src/render/spot_shadow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

SpotShadowFrame _frame(int resolution, List<Matrix4> matrices) =>
    SpotShadowFrame(
      casters: const [],
      matrices: matrices,
      tileResolution: resolution,
      depthBias: .003,
      normalBias: .07,
      softness: 2,
      casterFaces: ShadowCasterFaces.front,
      casterChannelMasks: const [],
      dropped: const [],
    );

Matrix4 _projection(Vector3 position) => SpotLight(
  range: 9,
  shadowNear: 1,
  shadowFieldOfView: math.pi / 2,
).shadowViewProjection(position, Vector3(0, 0, 1));

Vector4 _clip(Matrix4 matrix, Vector3 point) =>
    matrix.transform(Vector4(point.x, point.y, point.z, 1));

Vector3 _uvDepth(Vector4 clip) => Vector3(
  clip.x / clip.w * .5 + .5,
  clip.y / clip.w * .5 + .5,
  clip.z / clip.w,
);

void main() {
  test('512 spot projects into the lower quarter of a 2048 atlas tile', () {
    final origin = Vector3(3, 4, 5), caster = _projection(Vector3(3, 4, 5));
    final before = caster.storage.toList();
    final frame = _frame(512, [caster]);
    final sampling = frame.samplingMatrix(0, 2048);

    expect(frame.rasterResolution(2048), 512);
    expect(frame.atlasScale(2048), .25);
    expect(identical(sampling, caster), isFalse);
    for (final distance in [1.0, 3.0, 9.0]) {
      for (final x in [-1.0, 0.0, 1.0]) {
        for (final y in [-1.0, 0.0, 1.0]) {
          final point = origin + Vector3(x * distance, y * distance, distance);
          final original = _clip(caster, point),
              remapped = _clip(sampling, point);
          final actual = _uvDepth(remapped);
          expect(actual.x, closeTo((x + 1) * .125, 1e-12));
          expect(actual.y, closeTo((y + 1) * .125, 1e-12));
          expect(remapped.z, closeTo(original.z, 1e-12));
          expect(remapped.w, closeTo(original.w, 1e-12));
          expect(actual.z, closeTo(_uvDepth(original).z, 1e-12));
        }
      }
    }
    expect(caster.storage, before);
    expect(identical(frame.matrices.single, caster), isTrue);
  });

  test('512 spot in a native 512 tile keeps its caster matrix', () {
    final matrix = _projection(Vector3(-2, 7, 4));
    final frame = _frame(512, [matrix]);
    expect(frame.rasterResolution(512), 512);
    expect(frame.atlasScale(512), 1);
    expect(identical(frame.samplingMatrix(0, 512), matrix), isTrue);
  });

  test('spot raster requests clamp to the available atlas size', () {
    final matrix = _projection(Vector3.zero());
    final oversized = _frame(4096, [matrix]);
    expect(oversized.rasterResolution(2048), 2048);
    expect(oversized.atlasScale(2048), 1);
    expect(identical(oversized.samplingMatrix(0, 2048), matrix), isTrue);
    for (final request in [0, -64]) {
      final frame = _frame(request, [matrix]);
      expect(frame.rasterResolution(2048), 1);
      expect(frame.atlasScale(2048), 1 / 2048);
      final center = _uvDepth(
        _clip(frame.samplingMatrix(0, 2048), Vector3(0, 0, 3)),
      );
      expect(center.x, closeTo(.5 / 2048, 1e-12));
      expect(center.y, closeTo(.5 / 2048, 1e-12));
    }
  });

  test('each slot remaps its own translated projection without mutation', () {
    final origins = [Vector3(2, 3, 4), Vector3(-5, 8, -2)];
    final matrices = origins.map(_projection).toList();
    final before = matrices.map((m) => m.storage.toList()).toList();
    final frame = _frame(512, matrices);
    for (var i = 0; i < origins.length; i++) {
      final center = origins[i] + Vector3(0, 0, 3);
      final sampled = _uvDepth(_clip(frame.samplingMatrix(i, 2048), center));
      expect(sampled.x, closeTo(.125, 1e-12));
      expect(sampled.y, closeTo(.125, 1e-12));
      expect(matrices[i].storage, before[i]);
    }
  });
}
