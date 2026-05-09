part of '../animation.dart';

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
    List<Vector3> values,
  ) {
    return TranslationTimelineResolver._(times, values);
  }

  /// Creates a rotation resolver that spherically interpolates between
  /// the keyframe quaternions in [values] at the corresponding [times].
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing.
  static PropertyResolver makeRotationTimeline(
    List<double> times,
    List<Quaternion> values,
  ) {
    return RotationTimelineResolver._(times, values);
  }

  /// Creates a scale resolver that linearly interpolates between the
  /// keyframe scales in [values] at the corresponding [times].
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing.
  static PropertyResolver makeScaleTimeline(
    List<double> times,
    List<Vector3> values,
  ) {
    return ScaleTimelineResolver._(times, values);
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

/// Shared keyframe lookup for the per-property timeline resolvers.
///
/// Implementations supply the value-array storage and per-frame
/// interpolation; this base class handles binary-style search through
/// the time axis to compute a `(index, lerp)` pair.
abstract class TimelineResolver implements PropertyResolver {
  final List<double> _times;

  TimelineResolver._(this._times);

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
    return _TimelineKey(nextTimeIndex, lerp);
  }
}

/// Resolves a translation timeline with per-component linear
/// interpolation, blended into [AnimationTransforms.animatedPose] as an
/// offset from the bind pose.
class TranslationTimelineResolver extends TimelineResolver {
  final List<Vector3> _values;

  TranslationTimelineResolver._(List<double> times, this._values)
    : super._(times) {
    assert(times.length == _values.length);
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Vector3 value = _values[key.index];
    if (key.lerp < 1) {
      value = _values[key.index - 1].lerp(value, key.lerp);
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

  RotationTimelineResolver._(List<double> times, this._values)
    : super._(times) {
    assert(times.length == _values.length);
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Quaternion value = _values[key.index];
    if (key.lerp < 1) {
      value = _values[key.index - 1].slerp(value, key.lerp);
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

  ScaleTimelineResolver._(List<double> times, this._values) : super._(times) {
    assert(times.length == _values.length);
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Vector3 value = _values[key.index];
    if (key.lerp < 1) {
      value = _values[key.index - 1].lerp(value, key.lerp);
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
