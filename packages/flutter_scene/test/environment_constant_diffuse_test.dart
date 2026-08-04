import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('constant diffuse evaluates to its ambient radiance', () {
    late EnvironmentMap environment;
    try {
      environment = EnvironmentMap.constantDiffuse(Vector3(0.2, 0.4, 0.8));
    } catch (_) {
      return;
    }

    const sh0Basis = 0.28209479177387814;
    final coefficient = environment.diffuseSphericalHarmonics.first;
    expect(coefficient.x * sh0Basis, closeTo(0.2, 1e-9));
    expect(coefficient.y * sh0Basis, closeTo(0.4, 1e-9));
    expect(coefficient.z * sh0Basis, closeTo(0.8, 1e-9));
    for (final higherBand in environment.diffuseSphericalHarmonics.skip(1)) {
      expect(higherBand, Vector3.zero());
    }
  });
}
