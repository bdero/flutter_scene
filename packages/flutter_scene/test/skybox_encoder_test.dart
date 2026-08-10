import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/skybox_encoder.dart';

void main() {
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
