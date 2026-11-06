import 'package:flutter_scene/src/render/radiance_layout.dart';
import 'package:flutter_scene/src/render/sky_bake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the cube prefilter runs each face of each band once', () {
    final steps = skyBakeStepCount(cube: true) - 6 - 1 - 1;
    expect(steps, 6 * kPrefilterBandCount);
    final seen = {for (var i = 0; i < steps; i++) skyBakeCubePrefilterStep(i)};
    expect(seen, hasLength(steps));
    for (final (:face, :band) in seen) {
      expect(face, inInclusiveRange(0, 5));
      expect(band, inInclusiveRange(0, kPrefilterBandCount - 1));
    }
  });

  test('the atlas layout still prefilters one band per step', () {
    expect(skyBakeStepCount(cube: false), 6 + 1 + kPrefilterBandCount + 1);
  });
}
