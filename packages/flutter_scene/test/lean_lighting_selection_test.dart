// Covers when a frame may draw with the lean lit entries: only while every
// feature they compile out is off, and never under the debug override.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/light.dart'
    show debugDisableLeanLighting, leanLightingAllowed, shadingTierOverride;
import 'package:flutter_test/flutter_test.dart';

bool _allowed({
  bool irradianceField = false,
  Fog? fog,
  int rectAreaLightCount = 0,
  bool environmentBlending = false,
  bool ambientOcclusion = false,
  int pointShadowTileCount = 0,
}) => leanLightingAllowed(
  irradianceField: irradianceField,
  fog: fog,
  rectAreaLightCount: rectAreaLightCount,
  environmentBlending: environmentBlending,
  ambientOcclusion: ambientOcclusion,
  pointShadowTileCount: pointShadowTileCount,
);

void main() {
  test('a frame with none of the compiled-out features allows lean', () {
    expect(_allowed(), isTrue);
  });

  test('fog only blocks lean while it applies', () {
    expect(_allowed(fog: Fog()), isTrue);
    expect(
      _allowed(
        fog: Fog()
          ..enabled = true
          ..mode = FogMode.none,
      ),
      isTrue,
    );
    expect(_allowed(fog: Fog()..enabled = true), isFalse);
  });

  test('each compiled-out feature blocks lean', () {
    expect(_allowed(irradianceField: true), isFalse);
    expect(_allowed(rectAreaLightCount: 1), isFalse);
    expect(_allowed(environmentBlending: true), isFalse);
    expect(_allowed(ambientOcclusion: true), isFalse);
    expect(_allowed(pointShadowTileCount: 2), isFalse);
  });

  test('the debug override forces the full entries', () {
    debugDisableLeanLighting = true;
    addTearDown(() => debugDisableLeanLighting = false);
    expect(_allowed(), isFalse);
  });

  test('a warm-up override forces either tier', () {
    addTearDown(() => shadingTierOverride = null);
    shadingTierOverride = true;
    expect(_allowed(fog: Fog()..enabled = true), isTrue);
    shadingTierOverride = false;
    expect(_allowed(), isFalse);
  });
}
