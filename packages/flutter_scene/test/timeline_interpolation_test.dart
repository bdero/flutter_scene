// Covers TimelineInterpolation.step: a stepped timeline holds the previous
// keyframe's value until the next one is reached.
library;

import 'package:flutter_scene/src/animation.dart'
    show
        AnimationTransforms,
        DecomposedTransform,
        PropertyResolver,
        TimelineInterpolation;
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

AnimationTransforms _transforms() => AnimationTransforms(
  bindPose: DecomposedTransform(
    translation: Vector3.zero(),
    rotation: Quaternion.identity(),
    scale: Vector3.all(1),
  ),
);

void main() {
  // A two-key translation timeline: 0 -> (10, 0, 0) over one second.
  List<double> sampleAt(double time, TimelineInterpolation interpolation) {
    final resolver = PropertyResolver.makeTranslationTimeline(
      [0.0, 1.0],
      [Vector3.zero(), Vector3(10, 0, 0)],
      interpolation: interpolation,
    );
    final transforms = _transforms();
    resolver.apply(transforms, time, 1.0);
    return [
      transforms.animatedPose.translation.x,
      transforms.animatedPose.translation.y,
      transforms.animatedPose.translation.z,
    ];
  }

  test('linear blends between keyframes', () {
    expect(sampleAt(0.5, TimelineInterpolation.linear)[0], closeTo(5.0, 1e-6));
  });

  test('step holds the previous keyframe until the next one', () {
    final mid = sampleAt(0.5, TimelineInterpolation.step);
    expect(mid[0], closeTo(0.0, 1e-6));
    // At the second keyframe exactly, its value applies.
    expect(sampleAt(1.0, TimelineInterpolation.step)[0], closeTo(10.0, 1e-6));
    // Before the first keyframe, the first value applies.
    expect(sampleAt(-0.5, TimelineInterpolation.step)[0], closeTo(0.0, 1e-6));
  });

  test('default interpolation is linear', () {
    final resolver = PropertyResolver.makeTranslationTimeline(
      [0.0, 1.0],
      [Vector3.zero(), Vector3(10, 0, 0)],
    );
    final transforms = _transforms();
    resolver.apply(transforms, 0.5, 1.0);
    expect(transforms.animatedPose.translation.x, closeTo(5.0, 1e-6));
  });
}
