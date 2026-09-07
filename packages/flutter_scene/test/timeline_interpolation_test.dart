/// Covers the three glTF sampler interpolations a timeline can carry: linear,
/// step, and cubic Hermite over per-keyframe tangents. Before these existed a
/// STEP sampler eased between its keys instead of holding them, and a
/// CUBICSPLINE sampler was flattened to its keyframe values with the tangents
/// thrown away, so both played back as something the author did not write.
library;

import 'dart:typed_data';

// The channel/resolver data model is internal; tests reach it directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show
        AnimationTransforms,
        DecomposedTransform,
        PropertyResolver,
        TimelineInterpolation;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

AnimationTransforms _transforms({Float32List? morphWeights}) {
  final target = AnimationTransforms(
    bindPose: DecomposedTransform(
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3.all(1.0),
    ),
  );
  if (morphWeights != null) {
    target.bindMorphWeights = Float32List.fromList(morphWeights);
    target.animatedMorphWeights = Float32List.fromList(morphWeights);
  }
  return target;
}

/// The translation a [resolver] produces at [time], at full weight.
Vector3 _translationAt(PropertyResolver resolver, double time) {
  final target = _transforms();
  resolver.apply(target, time, 1.0);
  return target.animatedPose.translation;
}

void main() {
  group('step', () {
    // Two keys a second apart: the origin, then x = 10.
    PropertyResolver stepTimeline() => PropertyResolver.makeTranslationTimeline(
      [0.0, 1.0],
      [Vector3.zero(), Vector3(10, 0, 0)],
      interpolation: TimelineInterpolation.step,
    );

    test('holds the previous keyframe across the whole segment', () {
      final resolver = stepTimeline();

      // Linear would read 1, 5 and 9 here. A step sampler is authored
      // precisely so it does not: the value must not move until the next key.
      expect(_translationAt(resolver, 0.1).x, 0.0);
      expect(_translationAt(resolver, 0.5).x, 0.0);
      expect(_translationAt(resolver, 0.9).x, 0.0);
    });

    test('jumps exactly at the next keyframe', () {
      final resolver = stepTimeline();

      expect(_translationAt(resolver, 0.999).x, 0.0);
      expect(_translationAt(resolver, 1.0).x, 10.0);
    });

    test('holds the last keyframe past the end', () {
      expect(_translationAt(stepTimeline(), 5.0).x, 10.0);
    });
  });

  group('linear stays linear', () {
    test('the default is unchanged by interpolation existing', () {
      final resolver = PropertyResolver.makeTranslationTimeline(
        [0.0, 1.0],
        [Vector3.zero(), Vector3(10, 0, 0)],
      );

      expect(_translationAt(resolver, 0.25).x, closeTo(2.5, 1e-6));
      expect(_translationAt(resolver, 0.5).x, closeTo(5.0, 1e-6));
    });
  });

  group('cubic', () {
    /// A segment from 0 to [end] seconds, x running 0 to 10, with the out-
    /// and in-tangents of the two keys set to [outTangent] and [inTangent]
    /// (units per second).
    PropertyResolver cubicTimeline({
      required double outTangent,
      required double inTangent,
      double end = 1.0,
    }) => PropertyResolver.makeTranslationTimeline(
      [0.0, end],
      [Vector3.zero(), Vector3(10, 0, 0)],
      interpolation: TimelineInterpolation.cubic,
      inTangents: [Vector3.zero(), Vector3(inTangent, 0, 0)],
      outTangents: [Vector3(outTangent, 0, 0), Vector3.zero()],
    );

    test('passes through both keyframes exactly', () {
      // The Hermite basis is h00=1 at s=0 and h01=1 at s=1, so however the
      // tangents are set the curve must still hit the authored keys.
      final resolver = cubicTimeline(outTangent: 40, inTangent: -25);

      expect(_translationAt(resolver, 0.0).x, closeTo(0.0, 1e-6));
      expect(_translationAt(resolver, 1.0).x, closeTo(10.0, 1e-6));
    });

    test('flat tangents ease in and out rather than running straight', () {
      // Zero tangents give the smoothstep curve: 3s^2 - 2s^3.
      final resolver = cubicTimeline(outTangent: 0, inTangent: 0);

      expect(_translationAt(resolver, 0.25).x, closeTo(10 * 0.15625, 1e-6));
      // Symmetric about the midpoint, where it agrees with linear.
      expect(_translationAt(resolver, 0.5).x, closeTo(5.0, 1e-6));
      expect(_translationAt(resolver, 0.75).x, closeTo(10 * 0.84375, 1e-6));
    });

    test('tangents matching the chord reproduce the straight line', () {
      // A tangent of 10 per second over a 1-second segment is exactly the
      // slope of the chord, which is the case where Hermite degenerates to
      // the linear result. Anything else means the basis is misweighted.
      final resolver = cubicTimeline(outTangent: 10, inTangent: 10);

      expect(_translationAt(resolver, 0.25).x, closeTo(2.5, 1e-6));
      expect(_translationAt(resolver, 0.5).x, closeTo(5.0, 1e-6));
      expect(_translationAt(resolver, 0.75).x, closeTo(7.5, 1e-6));
    });

    test('tangents are per second, so the segment duration scales them', () {
      // The chord of a 2-second run from 0 to 10 has a slope of 5 per second,
      // and chord-slope tangents are the case where Hermite collapses to the
      // straight line. The test above pins the same thing at 10 per second
      // over a 1-second segment. Tangents read as per-segment rather than per
      // second would need 10 here too, and 5 would bend the curve.
      final resolver = cubicTimeline(outTangent: 5, inTangent: 5, end: 2.0);

      expect(_translationAt(resolver, 0.5).x, closeTo(2.5, 1e-6));
      expect(_translationAt(resolver, 1.0).x, closeTo(5.0, 1e-6));
      expect(_translationAt(resolver, 1.5).x, closeTo(7.5, 1e-6));
    });

    test('an overshooting tangent leaves the keyframe range', () {
      // The reason cubic is worth carrying: a curve that arcs past its own
      // endpoints. Flattening to the keys, as the importer used to, cannot
      // produce this at all.
      final resolver = cubicTimeline(outTangent: 60, inTangent: 0);

      expect(_translationAt(resolver, 0.5).x, greaterThan(10.0));
    });
  });

  group('rotation', () {
    test('step holds the previous quaternion', () {
      final resolver = PropertyResolver.makeRotationTimeline(
        [0.0, 1.0],
        [Quaternion.identity(), Quaternion.axisAngle(Vector3(0, 1, 0), 1.5)],
        interpolation: TimelineInterpolation.step,
      );

      final target = _transforms();
      resolver.apply(target, 0.5, 1.0);

      expect(target.animatedPose.rotation.x, closeTo(0.0, 1e-6));
      expect(target.animatedPose.rotation.y, closeTo(0.0, 1e-6));
      expect(target.animatedPose.rotation.z, closeTo(0.0, 1e-6));
      expect(target.animatedPose.rotation.w.abs(), closeTo(1.0, 1e-6));
    });

    test('cubic passes through its keyframes and stays normalized', () {
      final end = Quaternion.axisAngle(Vector3(0, 1, 0), 1.2)..normalize();
      final resolver = PropertyResolver.makeRotationTimeline(
        [0.0, 1.0],
        [Quaternion.identity(), end],
        interpolation: TimelineInterpolation.cubic,
        inTangents: [Quaternion(0, 0, 0, 0), Quaternion(0, 0.4, 0, 0)],
        outTangents: [Quaternion(0, 0.4, 0, 0), Quaternion(0, 0, 0, 0)],
      );

      final atEnd = _transforms();
      resolver.apply(atEnd, 1.0, 1.0);
      expect(atEnd.animatedPose.rotation.y, closeTo(end.y, 1e-6));
      expect(atEnd.animatedPose.rotation.w, closeTo(end.w, 1e-6));

      // Component-wise Hermite does not preserve unit length on its own, so
      // the resolver must normalize or the pose picks up a scale.
      final midway = _transforms();
      resolver.apply(midway, 0.5, 1.0);
      expect(midway.animatedPose.rotation.length, closeTo(1.0, 1e-6));
    });
  });

  group('morph weights', () {
    test('step holds the previous weights', () {
      final resolver = PropertyResolver.makeMorphWeightsTimeline(
        [0.0, 1.0],
        Float32List.fromList([0.0, 1.0, 1.0, 0.0]),
        targetCount: 2,
        interpolation: TimelineInterpolation.step,
      );

      final target = _transforms(morphWeights: Float32List(2));
      resolver.apply(target, 0.5, 1.0);

      expect(target.animatedMorphWeights![0], 0.0);
      expect(target.animatedMorphWeights![1], 1.0);
    });

    test('cubic eases each target on its own tangents', () {
      // Both targets run 0 to 1 over the segment; only their tangents differ,
      // so a shared or transposed tangent read would show up here.
      final resolver = PropertyResolver.makeMorphWeightsTimeline(
        [0.0, 1.0],
        Float32List.fromList([0.0, 0.0, 1.0, 1.0]),
        targetCount: 2,
        interpolation: TimelineInterpolation.cubic,
        inTangents: Float32List.fromList([0.0, 0.0, 1.0, 0.0]),
        outTangents: Float32List.fromList([1.0, 0.0, 0.0, 0.0]),
      );

      final target = _transforms(morphWeights: Float32List(2));
      resolver.apply(target, 0.5, 1.0);

      // Target 0 has chord-slope tangents both ends: exactly linear, 0.5.
      expect(target.animatedMorphWeights![0], closeTo(0.5, 1e-6));
      // Target 1 has flat tangents: smoothstep, also 0.5 at the midpoint but
      // reached along a different curve, which the quarter point shows.
      expect(target.animatedMorphWeights![1], closeTo(0.5, 1e-6));

      final quarter = _transforms(morphWeights: Float32List(2));
      resolver.apply(quarter, 0.25, 1.0);
      expect(quarter.animatedMorphWeights![0], closeTo(0.25, 1e-6));
      expect(quarter.animatedMorphWeights![1], closeTo(0.15625, 1e-6));
    });
  });
}
