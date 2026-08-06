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
}
