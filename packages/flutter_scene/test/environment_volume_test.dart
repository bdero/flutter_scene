// Covers EnvironmentVolume coverage and blendEnvironmentVolumes: local volumes
// blend in by camera position, blendDistance fades the contribution, and
// priority orders overlapping volumes.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a local box volume blends fully inside and not outside', () {
    final base = EnvironmentSettings(exposure: 1.0);
    final volume = EnvironmentVolume(
      settings: EnvironmentSettings(exposure: 3.0),
      bounds: BoxVolumeBounds(
        center: Vector3.zero(),
        halfExtents: Vector3.all(1),
      ),
    );
    expect(
      blendEnvironmentVolumes(base, [volume], Vector3.zero()).exposure,
      3.0,
    );
    expect(
      blendEnvironmentVolumes(base, [volume], Vector3(5, 0, 0)).exposure,
      1.0,
    );
  });

  test('blendDistance fades the contribution outside the surface', () {
    final base = EnvironmentSettings(exposure: 0.0);
    final volume = EnvironmentVolume(
      settings: EnvironmentSettings(exposure: 1.0),
      bounds: SphereVolumeBounds(center: Vector3.zero(), radius: 1.0),
      blendDistance: 2.0,
    );
    // 1 unit outside the radius-1 sphere: coverage = 1 - 1/2 = 0.5.
    final at = blendEnvironmentVolumes(base, [volume], Vector3(2, 0, 0));
    expect(at.exposure, closeTo(0.5, 1e-9));
  });

  test('weight scales the contribution', () {
    final base = EnvironmentSettings(exposure: 0.0);
    final volume = EnvironmentVolume(
      settings: EnvironmentSettings(exposure: 1.0),
      weight: 0.25,
    );
    expect(
      blendEnvironmentVolumes(base, [volume], Vector3.zero()).exposure,
      closeTo(0.25, 1e-9),
    );
  });

  test('higher priority applies last (wins)', () {
    final base = EnvironmentSettings(exposure: 0.0);
    final low = EnvironmentVolume(
      settings: EnvironmentSettings(exposure: 1.0),
      priority: 0,
    );
    final high = EnvironmentVolume(
      settings: EnvironmentSettings(exposure: 2.0),
      priority: 1,
    );
    // List order shouldn't matter; priority decides.
    expect(
      blendEnvironmentVolumes(base, [high, low], Vector3.zero()).exposure,
      2.0,
    );
  });
}
