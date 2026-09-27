import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/skybox_encoder.dart';
import 'package:flutter_scene/src/render/planar_reflection.dart';

void main() {
  test('reflection sky rays use the unclipped projection', () {
    final source = PerspectiveCamera(
      position: Vector3(4.7, 3.9, -8),
      target: Vector3(0, 1, 5),
    );
    final reflected = PlanarReflectionCamera(
      source: source,
      plane: Plane.normalconstant(Vector3(0, 1, 0), 0),
    );
    final unclipped = PerspectiveCamera(
      position: reflected.position,
      target: reflected.position + reflected.forward,
      up: reflected.up,
    );
    final actual = skyboxInverseViewProjection(
      reflected,
      const ui.Size(1280, 800),
    );
    final expected = skyboxInverseViewProjection(
      unclipped,
      const ui.Size(1280, 800),
    );
    // Corner rays are interpolated over the fullscreen triangles. Oblique
    // clipping must not distort that interpolation.
    Vector3 ray(Matrix4 inverse, double x, double y) {
      final h = inverse * Vector4(x, y, 1, 1);
      return Vector3(h.x, h.y, h.z) / h.w;
    }

    for (final weights in [Vector3(.2, .3, .5), Vector3(.6, .1, .3)]) {
      Vector3 interpolated(Matrix4 m) =>
          (ray(m, -1, -1) * weights.x +
                  ray(m, 1, -1) * weights.y +
                  ray(m, -1, 1) * weights.z)
              .normalized();
      expect(
        interpolated(actual).distanceTo(interpolated(expected)),
        lessThan(1e-5),
      );
    }
  });
  test('skybox transform ignores camera translation', () {
    final direction = Vector3(0, 0, 1);
    final originCamera = PerspectiveCamera(
      position: Vector3.zero(),
      target: direction,
    );
    final distantPosition = Vector3(1000000, -2000000, 3000000);
    final distantCamera = PerspectiveCamera(
      position: distantPosition,
      target: distantPosition + direction * 100,
    );

    final origin = skyboxInverseViewProjection(
      originCamera,
      const ui.Size(1920, 1080),
    );
    final distant = skyboxInverseViewProjection(
      distantCamera,
      const ui.Size(1920, 1080),
    );

    for (var i = 0; i < 16; i++) {
      expect(distant.storage[i], closeTo(origin.storage[i], 1e-6));
    }
  });

  test('skybox transform does not mutate a camera-owned view matrix', () {
    final camera = _CachedCamera();
    final before = camera.view.clone();

    skyboxInverseViewProjection(camera, const ui.Size(800, 600));

    expect(camera.view.storage, before.storage);
  });
}

class _CachedCamera extends Camera {
  final Matrix4 view = Matrix4.translationValues(2, 3, 4);

  @override
  Vector3 get position => Vector3(2, 3, 4);

  @override
  Vector3 get forward => Vector3(0, 0, 1);

  @override
  Vector3 get up => Vector3(0, 1, 0);

  @override
  CameraProjection get projection => PerspectiveProjection();

  @override
  Matrix4 getViewMatrix() => view;
}
