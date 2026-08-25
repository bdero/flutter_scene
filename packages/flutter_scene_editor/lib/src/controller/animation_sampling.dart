/// Pure keyframe sampling for the editor's animation preview.
///
/// Extracted from [EditorController] so the semantics — especially the step
/// mode's exact-keyframe-hit boundary — are unit-testable headlessly. This
/// must stay consistent with the runtime's `TimelineResolver` (which snaps
/// its lerp to 0 for step, so an exact hit yields the keyed value).
library;

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Samples a keyframe channel at time [t].
///
/// [times] must be sorted; [values] holds one [stride]-component vector per
/// entry (stride 4 means rotations, slerped as quaternions). A non-null
/// [interpolation] of [AnimationInterpolation.step] holds each keyframe's
/// value until the next one is reached — an exact hit on a keyframe still
/// returns that keyframe's own value. Returns null when the channel carries
/// no keyframes.
List<double>? sampleAnimationChannel(
  Float32List times,
  Float32List values,
  int stride,
  double t, {
  AnimationInterpolation? interpolation,
}) {
  if (times.isEmpty) return null;
  var hi = 0;
  while (hi < times.length && times[hi] < t) {
    hi++;
  }
  List<double> slice(int index) => [
    for (var j = 0; j < stride; j++) values[index * stride + j],
  ];
  if (hi <= 0) return slice(0);
  if (hi >= times.length) return slice(times.length - 1);
  // Step holds the previous keyframe until the next one is reached — but
  // an exact keyframe hit must still show that keyframe's own value
  // (matching the runtime, which computes lerp = 1 there).
  final step = interpolation == AnimationInterpolation.step;
  if (step && times[hi] > t) return slice(hi - 1);
  final lo = hi - 1;
  final span = times[hi] - times[lo];
  final f = span <= 0 ? 0.0 : (t - times[lo]) / span;
  if (stride == 4) {
    final a = Quaternion(
      values[lo * 4],
      values[lo * 4 + 1],
      values[lo * 4 + 2],
      values[lo * 4 + 3],
    );
    final b = Quaternion(
      values[hi * 4],
      values[hi * 4 + 1],
      values[hi * 4 + 2],
      values[hi * 4 + 3],
    );
    final blended = a.slerp(b, f);
    return [blended.x, blended.y, blended.z, blended.w];
  }
  final a = slice(lo);
  final b = slice(hi);
  return [for (var j = 0; j < stride; j++) a[j] + (b[j] - a[j]) * f];
}
