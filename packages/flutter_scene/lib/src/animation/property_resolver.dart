part of '../animation.dart';

/// How a timeline produces values between keyframes.
enum TimelineInterpolation {
  /// Straight lerp (rotation: slerp) between neighboring keyframes.
  linear,

  /// Hold the previous keyframe's value until the next one is reached.
  step,

  /// Cubic Hermite using per-keyframe tangents; the value list then holds
  /// three entries per keyframe in glTF order
  /// ([inTangent, value, outTangent]).
  cubic,
}

/// Computes a per-property animated value from a timeline of keyframes.
///
/// Subclasses cover the three [AnimationProperty] flavors with the
/// correct interpolator: linear interpolation for translation and scale,
/// spherical linear interpolation for rotation. Use the [PropertyResolver]
/// factories to construct one rather than instantiating subclasses
/// directly.
abstract class PropertyResolver {
  /// Returns the end time of the property in seconds.
  double getEndTime();

  /// Resolve and apply the property value to a target node. This
  /// operation is additive; a given node property may be amended by
  /// many different PropertyResolvers prior to rendering. For example,
  /// an AnimationPlayer may blend multiple Animations together by
  /// applying several AnimationClips.
  void apply(AnimationTransforms target, double timeInSeconds, double weight);

  /// Creates a translation resolver that linearly interpolates between
  /// the keyframe positions in [values] at the corresponding [times].
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing.
  static PropertyResolver makeTranslationTimeline(
    List<double> times,
    List<Vector3> values, {
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
  }) {
    return TranslationTimelineResolver._(times, values, interpolation);
  }

  /// Creates a rotation resolver that spherically interpolates between
  /// the keyframe quaternions in [values] at the corresponding [times].
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing.
  static PropertyResolver makeRotationTimeline(
    List<double> times,
    List<Quaternion> values, {
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
  }) {
    return RotationTimelineResolver._(times, values, interpolation);
  }

  /// Creates a scale resolver that linearly interpolates between the
  /// keyframe scales in [values] at the corresponding [times].
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing.
  static PropertyResolver makeScaleTimeline(
    List<double> times,
    List<Vector3> values, {
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
  }) {
    return ScaleTimelineResolver._(times, values, interpolation);
  }

  /// Creates a morph weights resolver that linearly interpolates between
  /// keyframed weight vectors.
  ///
  /// [values] is the flattened keyframe data, [targetCount] weights per
  /// keyframe in target order (`times.length * targetCount` floats), the
  /// shape a glTF `weights` sampler decodes to.
  static PropertyResolver makeMorphWeightsTimeline(
    List<double> times,
    Float32List values, {
    required int targetCount,
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
  }) {
    return MorphWeightsTimelineResolver._(
      times,
      values,
      targetCount,
      interpolation,
    );
  }
}

class _TimelineKey {
  /// The index of the closest previous keyframe.
  int index = 0;

  /// Used to interpolate between the resolved values for `timeline_index - 1`
  /// and `timeline_index`. The range of this value should always be `0>N>=1`.
  double lerp = 1.0;

  _TimelineKey(this.index, this.lerp);
}

// Cubic Hermite basis functions.
double _h00(double s) => 2 * s * s * s - 3 * s * s + 1;
double _h10(double s) => s * s * s - 2 * s * s + s;
double _h01(double s) => -2 * s * s * s + 3 * s * s;
double _h11(double s) => s * s * s - s * s;

Vector3 _hermiteVec3(
  Vector3 v0,
  Vector3 m0,
  Vector3 v1,
  Vector3 m1,
  double s,
) => v0 * _h00(s) + m0 * _h10(s) + v1 * _h01(s) + m1 * _h11(s);

/// Component-wise Hermite, normalized afterwards — the standard glTF-style
/// approximation for CUBICSPLINE rotation samplers.
Quaternion _hermiteQuat(
  Quaternion q0,
  Quaternion m0,
  Quaternion q1,
  Quaternion m1,
  double s,
) => Quaternion(
  q0.x * _h00(s) + m0.x * _h10(s) + q1.x * _h01(s) + m1.x * _h11(s),
  q0.y * _h00(s) + m0.y * _h10(s) + q1.y * _h01(s) + m1.y * _h11(s),
  q0.z * _h00(s) + m0.z * _h10(s) + q1.z * _h01(s) + m1.z * _h11(s),
  q0.w * _h00(s) + m0.w * _h10(s) + q1.w * _h01(s) + m1.w * _h11(s),
)..normalize();

/// Shared keyframe lookup for the per-property timeline resolvers.
///
/// Implementations supply the value-array storage and per-frame
/// interpolation; this base class handles binary-style search through
/// the time axis to compute a `(index, lerp)` pair.
abstract class TimelineResolver implements PropertyResolver {
  final List<double> _times;

  /// How values are produced between keyframes.
  final TimelineInterpolation _interpolation;

  TimelineResolver._(
    this._times, [
    this._interpolation = TimelineInterpolation.linear,
  ]);

  /// The keyframe times, in seconds. Read by the scene serializer.
  List<double> get times => List.unmodifiable(_times);

  @override
  double getEndTime() {
    return _times.isEmpty ? 0.0 : _times.last;
  }

  _TimelineKey _getTimelineKey(double time) {
    if (_times.length <= 1 || time <= _times.first) {
      return _TimelineKey(0, 1);
    }
    if (time >= _times.last) {
      return _TimelineKey(_times.length - 1, 1);
    }
    int nextTimeIndex = _times.indexWhere((t) => t >= time);

    double previousTime = _times[nextTimeIndex - 1];
    double nextTime = _times[nextTimeIndex];

    double lerp = (time - previousTime) / (nextTime - previousTime);
    // Step holds the previous keyframe until the next one is reached.
    if (_interpolation == TimelineInterpolation.step && lerp < 1) {
      lerp = 0;
    }
    return _TimelineKey(nextTimeIndex, lerp);
  }
}

/// Resolves a translation timeline with per-component linear
/// interpolation, blended into [AnimationTransforms.animatedPose] as an
/// offset from the bind pose.
class TranslationTimelineResolver extends TimelineResolver {
  final List<Vector3> _values;

  /// The keyframe values. Read by the scene serializer.
  List<Vector3> get values => List.unmodifiable(_values);

  TranslationTimelineResolver._(
    List<double> times,
    this._values,
    TimelineInterpolation interpolation,
  ) : super._(times, interpolation) {
    // A cubic channel carries three vectors per keyframe.
    assert(
      _values.length == times.length ||
          (_interpolation == TimelineInterpolation.cubic &&
              _values.length == times.length * 3),
    );
  }

  /// The Hermite sample between keys [index - 1] and [index].
  Vector3 _cubicValue(int index, double s) {
    final dt = _times[index] - _times[index - 1];
    return _hermiteVec3(
      _values[(index - 1) * 3 + 1],
      _values[(index - 1) * 3 + 2] * dt,
      _values[index * 3 + 1],
      _values[index * 3] * dt,
      s,
    );
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    // A cubic channel's list holds [inTangent, value, outTangent] triplets.
    final slot = _interpolation == TimelineInterpolation.cubic
        ? key.index * 3 + 1
        : key.index;
    Vector3 value = _values[slot];
    if (key.lerp < 1) {
      value = _interpolation == TimelineInterpolation.cubic
          ? _cubicValue(key.index, key.lerp)
          : _values[key.index - 1].lerp(value, key.lerp);
    }

    target.animatedPose.translation +=
        (value - target.bindPose.translation) * weight;
  }
}

/// Resolves a rotation timeline with spherical linear interpolation,
/// slerping the current animated rotation toward the keyframed rotation
/// by the supplied weight.
class RotationTimelineResolver extends TimelineResolver {
  final List<Quaternion> _values;

  /// The keyframe values. Read by the scene serializer.
  List<Quaternion> get values => List.unmodifiable(_values);

  RotationTimelineResolver._(
    List<double> times,
    this._values,
    TimelineInterpolation interpolation,
  ) : super._(times, interpolation) {
    // A cubic channel carries three quaternions per keyframe.
    assert(
      _values.length == times.length ||
          (_interpolation == TimelineInterpolation.cubic &&
              _values.length == times.length * 3),
    );
  }

  /// The Hermite sample between keys [index - 1] and [index], evaluated
  /// component-wise and normalized.
  Quaternion _cubicValue(int index, double s) {
    final dt = _times[index] - _times[index - 1];
    Quaternion scale(Quaternion q, double f) =>
        Quaternion(q.x * f, q.y * f, q.z * f, q.w * f);
    return _hermiteQuat(
      _values[(index - 1) * 3 + 1],
      scale(_values[(index - 1) * 3 + 2], dt),
      _values[index * 3 + 1],
      scale(_values[index * 3], dt),
      s,
    );
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    // A cubic channel's list holds [inTangent, value, outTangent] triplets.
    final slot = _interpolation == TimelineInterpolation.cubic
        ? key.index * 3 + 1
        : key.index;
    Quaternion value = _values[slot];
    if (key.lerp < 1) {
      value = _interpolation == TimelineInterpolation.cubic
          ? _cubicValue(key.index, key.lerp)
          : _values[key.index - 1].slerp(value, key.lerp);
    }

    target.animatedPose.rotation = target.animatedPose.rotation.slerp(
      value,
      weight,
    );
  }
}

/// Resolves a scale timeline with per-component linear interpolation.
///
/// The blended scale is normalized against the bind pose so weighted
/// blends behave multiplicatively (a weight of `1` reaches the keyframe
/// scale exactly).
class ScaleTimelineResolver extends TimelineResolver {
  final List<Vector3> _values;

  /// The keyframe values. Read by the scene serializer.
  List<Vector3> get values => List.unmodifiable(_values);

  ScaleTimelineResolver._(
    List<double> times,
    this._values,
    TimelineInterpolation interpolation,
  ) : super._(times, interpolation) {
    // A cubic channel carries three vectors per keyframe.
    assert(
      _values.length == times.length ||
          (_interpolation == TimelineInterpolation.cubic &&
              _values.length == times.length * 3),
    );
  }

  /// The Hermite sample between keys [index - 1] and [index].
  Vector3 _cubicValue(int index, double s) {
    final dt = _times[index] - _times[index - 1];
    return _hermiteVec3(
      _values[(index - 1) * 3 + 1],
      _values[(index - 1) * 3 + 2] * dt,
      _values[index * 3 + 1],
      _values[index * 3] * dt,
      s,
    );
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    // A cubic channel's list holds [inTangent, value, outTangent] triplets.
    final slot = _interpolation == TimelineInterpolation.cubic
        ? key.index * 3 + 1
        : key.index;
    Vector3 value = _values[slot];
    if (key.lerp < 1) {
      value = _interpolation == TimelineInterpolation.cubic
          ? _cubicValue(key.index, key.lerp)
          : _values[key.index - 1].lerp(value, key.lerp);
    }

    Vector3 scale = Vector3(
      1,
      1,
      1,
    ).lerp(value.divided(target.bindPose.scale), weight);

    target.animatedPose.scale = Vector3(
      target.animatedPose.scale.x * scale.x,
      target.animatedPose.scale.y * scale.y,
      target.animatedPose.scale.z * scale.z,
    );
  }
}

/// Resolves a morph weights timeline with per-target linear interpolation,
/// blended into [AnimationTransforms.animatedMorphWeights] as an offset
/// from the rest weights (matching the translation blend rule).
class MorphWeightsTimelineResolver extends TimelineResolver {
  final Float32List _values;

  /// Weights per keyframe.
  final int targetCount;

  /// The flattened keyframe values ([targetCount] per keyframe). Read by
  /// the scene serializer.
  Float32List get values => Float32List.fromList(_values);

  MorphWeightsTimelineResolver._(
    List<double> times,
    this._values,
    this.targetCount,
    TimelineInterpolation interpolation,
  ) : super._(times, interpolation) {
    assert(targetCount >= 0);
    // A cubic channel carries three (in, value, out) weight vectors per
    // keyframe.
    final perKey =
        targetCount * (_interpolation == TimelineInterpolation.cubic ? 3 : 1);
    assert(times.length * perKey == _values.length);
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    final animated = target.animatedMorphWeights;
    final bind = target.bindMorphWeights;
    if (animated == null || bind == null || targetCount == 0) {
      return;
    }
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    final cubic = _interpolation == TimelineInterpolation.cubic;
    final stride = targetCount * (cubic ? 3 : 1);
    final current = key.index * stride;
    final previous = (key.index - 1) * stride;
    final count = targetCount < animated.length ? targetCount : animated.length;
    for (var i = 0; i < count; i++) {
      var value =
          _values[cubic ? current + targetCount + i : current + i];
      if (key.lerp < 1) {
        if (cubic) {
          final dt = _times[key.index] - _times[key.index - 1];
          final v0 = _values[previous + targetCount + i];
          final m0 = _values[previous + 2 * targetCount + i] * dt;
          final v1 = _values[current + targetCount + i];
          final m1 = _values[current + i] * dt;
          value =
              v0 * _h00(key.lerp) +
              m0 * _h10(key.lerp) +
              v1 * _h01(key.lerp) +
              m1 * _h11(key.lerp);
        } else {
          final a = _values[previous + i];
          value = a + (value - a) * key.lerp;
        }
      }
      animated[i] += (value - bind[i]) * weight;
    }
  }
}
