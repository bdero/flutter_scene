/// Pure keyframe sampling for the editor's animation preview.
///
/// Extracted from [EditorController] so the semantics are unit-testable
/// headlessly. Evaluation is delegated to the engine's own resolvers, so
/// the preview plays exactly what the runtime will play — there is no
/// second interpolation implementation to keep in sync.
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/animation.dart' as engine;
import 'package:flutter_scene/src/animation.dart' show DecomposedTransform;
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Samples a keyframe channel at time [t].
///
/// [times] must be sorted; [values] holds one [stride]-component vector per
/// entry — stride 4 means rotations (quaternions), 3 means translation or
/// scale. A cubic channel's payload stores three vectors per keyframe
/// ([inTangent, value, outTangent]); its Hermite evaluation matches the
/// runtime's. An exact hit on a keyframe always returns that keyframe's own
/// value, including under [AnimationInterpolation.step]. Returns null when
/// the channel carries no keyframes.
List<double>? sampleAnimationChannel(
  Float32List times,
  Float32List values,
  int stride,
  double t, {
  AnimationInterpolation? interpolation,
}) {
  if (times.isEmpty) return null;
  final engineInterpolation = switch (interpolation) {
    AnimationInterpolation.step => engine.TimelineInterpolation.step,
    AnimationInterpolation.cubic => engine.TimelineInterpolation.cubic,
    _ => engine.TimelineInterpolation.linear,
  };
  final resolver = stride == 4
      ? engine.PropertyResolver.makeRotationTimeline(
          times.toList(),
          _quaternionChunks(values),
          interpolation: engineInterpolation,
        )
      : engine.PropertyResolver.makeTranslationTimeline(
          times.toList(),
          _vector3Chunks(values),
          interpolation: engineInterpolation,
        );
  final target = engine.AnimationTransforms(
    bindPose: DecomposedTransform(
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3.all(1),
    ),
  );
  resolver.apply(target, t, 1.0);
  if (stride == 4) {
    final q = target.animatedPose.rotation;
    return [q.x, q.y, q.z, q.w];
  }
  return [
    target.animatedPose.translation.x,
    target.animatedPose.translation.y,
    target.animatedPose.translation.z,
  ];
}

List<Vector3> _vector3Chunks(Float32List values) => [
  for (var base = 0; base + 3 <= values.length; base += 3)
    Vector3(values[base], values[base + 1], values[base + 2]),
];

List<Quaternion> _quaternionChunks(Float32List values) => [
  for (var base = 0; base + 4 <= values.length; base += 4)
    Quaternion(
      values[base],
      values[base + 1],
      values[base + 2],
      values[base + 3],
    ),
];
