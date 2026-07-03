import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fog defaults to off with an exponential mode ready', () {
    final fog = Fog();
    expect(fog.enabled, isFalse);
    expect(fog.mode, FogMode.exponential);
    expect(fog.maxOpacity, 1.0);
    expect(fog.heightFalloff, 0.0);
    expect(fog.sunInScatter, 0.0);
  });

  test('FogMode indices match the shader mode ids', () {
    // fog.glsl switches on 0 none, 1 linear, 2 exponential, 3 exp2.
    expect(FogMode.none.index, 0);
    expect(FogMode.linear.index, 1);
    expect(FogMode.exponential.index, 2);
    expect(FogMode.exponentialSquared.index, 3);
  });

  test('visibilityDensity maps a distance to a Beer-Lambert density', () {
    // At the visibility distance, exp(-density*d) should equal the 0.02
    // contrast threshold, so density = -ln(0.02)/d.
    final density = Fog.visibilityDensity(100.0);
    expect(density, greaterThan(0.0));
    // Round-trip: transmittance at 100 m is ~0.02.
    expect(math.exp(-density * 100.0), closeTo(0.02, 1e-9));
    // Nearer visibility means denser fog.
    expect(Fog.visibilityDensity(50.0), greaterThan(density));
    // Non-positive distance is a safe zero.
    expect(Fog.visibilityDensity(0.0), 0.0);
  });
}
