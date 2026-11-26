import 'package:flutter_scene/src/render/radiance_layout.dart';
import 'package:flutter_scene/src/render/sky_bake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the cube prefilter runs each face of each band once', () {
    final passes = [for (final step in skyBakeCubePrefilterSteps) ...step];
    expect(passes, hasLength(6 * kPrefilterBandCount));
    expect(passes.toSet(), hasLength(passes.length));
    expect(
      skyBakeStepCount(cube: true),
      6 + 1 + skyBakeCubePrefilterSteps.length + 1,
    );
  });

  test('no cube prefilter step outweighs one band 1 face or six passes', () {
    final budget = cubePrefilterPassCost(1);
    for (final step in skyBakeCubePrefilterSteps) {
      final cost = step.fold(
        0,
        (sum, p) => sum + cubePrefilterPassCost(p.band),
      );
      expect(cost, lessThanOrEqualTo(budget));
      expect(step.length, lessThanOrEqualTo(6));
    }
    // The light bands share steps, keeping the cycle short.
    expect(skyBakeCubePrefilterSteps.length, lessThan(3 * 6));
  });

  test('the atlas layout still prefilters one band per step', () {
    expect(skyBakeStepCount(cube: false), 6 + 1 + kPrefilterBandCount + 1);
  });
}
