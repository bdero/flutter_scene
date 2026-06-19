// Covers EnvironmentSettings.lerp: continuous fields interpolate, discrete
// fields switch at the halfway point, and the endpoints reproduce the inputs.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('continuous fields interpolate, discrete switch at 0.5', () {
    final a = EnvironmentSettings(
      exposure: 1.0,
      environmentIntensity: 0.0,
      brightness: 1.0,
      bloomIntensity: 0.0,
      toneMapping: ToneMappingMode.linear,
    );
    final b = EnvironmentSettings(
      exposure: 3.0,
      environmentIntensity: 2.0,
      brightness: 2.0,
      bloomIntensity: 1.0,
      toneMapping: ToneMappingMode.aces,
    );

    final mid = EnvironmentSettings.lerp(a, b, 0.5);
    expect(mid.exposure, 2.0);
    expect(mid.environmentIntensity, 1.0);
    expect(mid.brightness, 1.5);
    expect(mid.bloomIntensity, 0.5);
    // Discrete fields switch to b at t >= 0.5.
    expect(mid.toneMapping, ToneMappingMode.aces);

    final quarter = EnvironmentSettings.lerp(a, b, 0.25);
    expect(quarter.exposure, closeTo(1.5, 1e-9));
    expect(quarter.toneMapping, ToneMappingMode.linear); // still a

    // Endpoints reproduce the inputs.
    final start = EnvironmentSettings.lerp(a, b, 0.0);
    expect(start.exposure, 1.0);
    expect(start.toneMapping, ToneMappingMode.linear);
    final end = EnvironmentSettings.lerp(a, b, 1.0);
    expect(end.exposure, 3.0);
    expect(end.toneMapping, ToneMappingMode.aces);
  });

  test('vector grading fields interpolate per component', () {
    final a = EnvironmentSettings(gain: Vector3(0, 0, 0));
    final b = EnvironmentSettings(gain: Vector3(2, 4, 6));
    final mid = EnvironmentSettings.lerp(a, b, 0.5);
    expect(mid.gain, Vector3(1, 2, 3));
  });
}
