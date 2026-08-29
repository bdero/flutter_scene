// Covers TimelineInterpolation.step: a stepped timeline holds the previous
// keyframe's value until the next one is reached.
library;

import 'package:flutter_scene/src/animation.dart'
    show
        AnimationTransforms,
        DecomposedTransform,
        PropertyResolver,
        TimelineInterpolation;
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

  test('cubic Hermite honors outgoing tangents', () {
    // Layout per keyframe: [inTangent, value, outTangent].
    final resolver = PropertyResolver.makeTranslationTimeline(
      [0.0, 1.0],
      [
        Vector3.zero(), Vector3.zero(), Vector3(30, 0, 0), // in, v, out @0
        Vector3.zero(), Vector3(10, 0, 0), Vector3.zero(), // in, v, out @1
      ],
      interpolation: TimelineInterpolation.cubic,
    );
    // Endpoints hit their keyed values exactly.
    final start = _transforms();
    resolver.apply(start, 0.0, 1.0);
    expect(start.animatedPose.translation.x, closeTo(0.0, 1e-6));
    final end = _transforms();
    resolver.apply(end, 1.0, 1.0);
    expect(end.animatedPose.translation.x, closeTo(10.0, 1e-6));

    // Midpoint with an outgoing tangent of 30/s: h10(0.5) * 30 lifts the
    // sample above the linear midpoint (5 -> 8.75).
    final mid = _transforms();
    resolver.apply(mid, 0.5, 1.0);
    expect(mid.animatedPose.translation.x, closeTo(8.75, 1e-6));
  });

  test('cubic rotation is component-wise Hermite, normalized', () {
    final resolver = PropertyResolver.makeRotationTimeline(
      [0.0, 1.0],
      [
        Quaternion(0, 0, 0, 0), Quaternion.identity(), Quaternion(0, 0, 0, 0),
        Quaternion(0, 0, 0, 0), Quaternion(0, 1, 0, 0), Quaternion(0, 0, 0, 0),
      ],
      interpolation: TimelineInterpolation.cubic,
    );
    final mid = _transforms();
    resolver.apply(mid, 0.5, 1.0);
    final q = mid.animatedPose.rotation;
    // Zero tangents degenerate to smoothstep weighting; the halfway
    // components are 0.5 each, renormalized to unit length.
    expect(q.length, closeTo(1.0, 1e-6));
    expect(q.y, closeTo(0.70710678, 1e-4));
    expect(q.w.abs(), closeTo(0.70710678, 1e-4));
  });
}
