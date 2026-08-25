// Pins the editor preview's keyframe sampling semantics — the exact
// behaviors that must match the runtime's TimelineResolver, including the
// step mode's exact-keyframe-hit boundary.
import 'dart:typed_data';

import 'package:flutter_scene_editor/src/controller/animation_sampling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

Float32List _floats(List<double> values) => Float32List.fromList(values);

void main() {
  final times = _floats([0.0, 1.0]);
  final translation = _floats([0, 0, 0, 10, 0, 0]);

  test('linear blends between neighboring keyframes', () {
    final result = sampleAnimationChannel(times, translation, 3, 0.5)!;
    expect(result[0], closeTo(5.0, 1e-6));
  });

  test('an exact keyframe hit returns that keyframe under any mode', () {
    // The regression: step used to return the previous pose here.
    final stepped = sampleAnimationChannel(
      times,
      translation,
      3,
      1.0,
      interpolation: AnimationInterpolation.step,
    )!;
    expect(stepped[0], closeTo(10.0, 1e-6));
    final linear = sampleAnimationChannel(times, translation, 3, 1.0)!;
    expect(linear[0], closeTo(10.0, 1e-6));
  });

  test('step holds the previous keyframe between keys; linear does not', () {
    final stepped = sampleAnimationChannel(
      times,
      translation,
      3,
      0.5,
      interpolation: AnimationInterpolation.step,
    )!;
    expect(stepped[0], closeTo(0.0, 1e-6));
    final linear = sampleAnimationChannel(times, translation, 3, 0.5)!;
    expect(linear[0], closeTo(5.0, 1e-6));
  });

  test('times outside the timeline clamp to the end keyframes', () {
    for (final interpolation in [null, AnimationInterpolation.step]) {
      expect(
        sampleAnimationChannel(
          times,
          translation,
          3,
          -1.0,
          interpolation: interpolation,
        )![0],
        closeTo(0.0, 1e-6),
      );
      expect(
        sampleAnimationChannel(
          times,
          translation,
          3,
          2.0,
          interpolation: interpolation,
        )![0],
        closeTo(10.0, 1e-6),
      );
    }
  });

  test('a rotation channel slerps with stride 4', () {
    final quatTimes = _floats([0.0, 1.0]);
    // Identity to a 180 degree yaw about Y.
    final values = _floats([
      0, 0, 0, 1, //
      0, 1, 0, 0, //
    ]);
    final mid = sampleAnimationChannel(
      quatTimes,
      values,
      4,
      0.5,
      interpolation: AnimationInterpolation.step,
    );
    // Step holds identity at the midpoint...
    expect(mid![0], closeTo(0.0, 1e-6));
    expect(mid[3], closeTo(1.0, 1e-6));
    // ...while linear lands halfway along the quaternion arc: slerping
    // identity toward a 180-degree yaw covers a 90-degree arc, so the
    // halfway components are sin/cos of 45 degrees.
    final linearMid = sampleAnimationChannel(quatTimes, values, 4, 0.5)!;
    expect(linearMid[1], closeTo(0.70710678, 1e-6));
    expect(linearMid[3].abs(), closeTo(0.70710678, 1e-6));
  });

  test('an empty channel samples as null', () {
    expect(sampleAnimationChannel(_floats([]), _floats([]), 3, 0.0), isNull);
  });
}
