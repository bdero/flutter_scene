// Covers SunLight: deriving and updating a DirectionalLight from a sky's sun.

import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/sun_light.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A bare SunSky so the binding can be tested without GPU-backed sky sources.
class _FakeSun implements SunSky {
  _FakeSun(this.sunDirection, this.sunLightColor, this.sunLightIntensity);
  @override
  Vector3 sunDirection;
  @override
  Vector3 sunLightColor;
  @override
  double sunLightIntensity;
}

void main() {
  test('aims the light opposite the sun and follows its color/intensity', () {
    final sun = _FakeSun(Vector3(0, 1, 0), Vector3(1, 0.9, 0.8), 4.0);
    final binding = SunLight(sun, castsShadow: true, intensityScale: 0.5);

    final light = binding.resolve();
    expect(light.direction, Vector3(0, -1, 0));
    expect(light.color, Vector3(1, 0.9, 0.8));
    expect(light.intensity, 2.0); // 4.0 * 0.5
    expect(light.castsShadow, isTrue);

    // resolve mutates one light object in place, so the scene graph keeps the
    // same registered light as the sun moves.
    expect(identical(binding.resolve(), light), isTrue);
    sun.sunDirection = Vector3(1, 0, 0);
    binding.resolve();
    expect(light.direction, Vector3(-1, 0, 0));
  });

  test('explicit color/intensity overrides win over the sky', () {
    final sun = _FakeSun(Vector3(0, 1, 0), Vector3(1, 1, 1), 3.0);
    final binding = SunLight(
      sun,
      color: Vector3(0.2, 0.4, 0.6),
      intensity: 1.0,
    );

    final light = binding.resolve();
    expect(light.color, Vector3(0.2, 0.4, 0.6));
    expect(light.intensity, 1.0);
  });

  test('shadow knobs pass through to the managed light', () {
    final sun = _FakeSun(Vector3(0, 1, 0), Vector3(1, 1, 1), 3.0);
    final binding = SunLight(
      sun,
      shadowMaxDistance: 80.0,
      shadowCascadeCount: 2,
      shadowSoftness: 0.2,
    );

    final light = binding.resolve();
    expect(light.shadowMaxDistance, 80.0);
    expect(light.shadowCascadeCount, 2);
    expect(light.shadowSoftness, 0.2);
  });
}
