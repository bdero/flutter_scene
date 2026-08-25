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
/// returns that keyframe's own value. [AnimationInterpolation.cubic]
/// evaluates the cubic Hermite between keys; its payload then stores three
/// vectors per keyframe ([inTangent, value, outTangent]). Returns null when
/// the channel carries no keyframes.
List<double>? sampleAnimationChannel(
  Float32List times,
  Float32List values,
  int stride,
  double t, {
  AnimationInterpolation? interpolation,
}) {
  if (times.isEmpty) return null;
  final cubic = interpolation == AnimationInterpolation.cubic;
  final rowWidth = stride * (cubic ? 3 : 1);
  var hi = 0;
  while (hi < times.length && times[hi] < t) {
    hi++;
  }
  // The value slot of keyframe [index]: the middle third of a cubic row.
  List<double> slice(int index) {
    final base = index * rowWidth + (cubic ? stride : 0);
    return [for (var j = 0; j < stride; j++) values[base + j]];
  }

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
  if (cubic) {
    // Hermite with tangents scaled to the segment duration.
    final dt = span;
    final out0 = [
      for (var j = 0; j < stride; j++) values[(lo * 3 + 2) * stride + j] * dt,
    ];
    final in1 = [
      for (var j = 0; j < stride; j++) values[(hi * 3) * stride + j] * dt,
    ];
    final a = slice(lo);
    final b = slice(hi);
    double h00(double s) => 2 * s * s * s - 3 * s * s + 1;
    double h10(double s) => s * s * s - 2 * s * s + s;
    double h01(double s) => -2 * s * s * s + 3 * s * s;
    double h11(double s) => s * s * s - s * s;
    if (stride == 4) {
      final blended = Quaternion(
        a[0] * h00(f) + out0[0] * h10(f) + b[0] * h01(f) + in1[0] * h11(f),
        a[1] * h00(f) + out0[1] * h10(f) + b[1] * h01(f) + in1[1] * h11(f),
        a[2] * h00(f) + out0[2] * h10(f) + b[2] * h01(f) + in1[2] * h11(f),
        a[3] * h00(f) + out0[3] * h10(f) + b[3] * h01(f) + in1[3] * h11(f),
      )..normalize();
      return [blended.x, blended.y, blended.z, blended.w];
    }
    return [
      for (var j = 0; j < stride; j++)
        a[j] * h00(f) + out0[j] * h10(f) + b[j] * h01(f) + in1[j] * h11(f),
    ];
  }
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
