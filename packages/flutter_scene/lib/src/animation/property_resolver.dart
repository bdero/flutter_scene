part of '../animation.dart';

/// How a timeline produces values between its keyframes.
///
/// Mirrors glTF's sampler interpolation modes, which is where timelines
/// usually come from.
/// {@category Animation}
enum TimelineInterpolation {
  /// Straight lerp between neighboring keyframes; slerp for rotation.
  linear,

  /// Holds the previous keyframe's value until the next one is reached.
  ///
  /// The value jumps at the keyframe rather than easing toward it, which is
  /// what a switch, a visibility flip, or a hand-keyed pose pop wants.
  step,

  /// Cubic Hermite between neighboring keyframes, using each keyframe's own
  /// in- and out-tangents.
  ///
  /// Tangents are in value units per second, matching glTF `CUBICSPLINE`,
  /// and are supplied alongside the values rather than packed into them, so
  /// a keyframe stays one entry at one index no matter how it interpolates.
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
  ///
  /// [interpolation] selects how values are produced between keyframes.
  /// [inTangents] and [outTangents] are required by (and only by)
  /// [TimelineInterpolation.cubic], one per keyframe, in units per second.
  static PropertyResolver makeTranslationTimeline(
    List<double> times,
    List<Vector3> values, {
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
    List<Vector3>? inTangents,
    List<Vector3>? outTangents,
  }) {
    return TranslationTimelineResolver._(
      times,
      values,
      interpolation,
      inTangents,
      outTangents,
    );
  }

  /// Creates a rotation resolver that spherically interpolates between
  /// the keyframe quaternions in [values] at the corresponding [times].
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing.
  ///
  /// [interpolation] selects how values are produced between keyframes.
  /// [inTangents] and [outTangents] are required by (and only by)
  /// [TimelineInterpolation.cubic], one per keyframe, in units per second.
  static PropertyResolver makeRotationTimeline(
    List<double> times,
    List<Quaternion> values, {
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
    List<Quaternion>? inTangents,
    List<Quaternion>? outTangents,
  }) {
    return RotationTimelineResolver._(
      times,
      values,
      interpolation,
      inTangents,
      outTangents,
    );
  }

  /// Creates a scale resolver that linearly interpolates between the
  /// keyframe scales in [values] at the corresponding [times].
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing.
  ///
  /// [interpolation] selects how values are produced between keyframes.
  /// [inTangents] and [outTangents] are required by (and only by)
  /// [TimelineInterpolation.cubic], one per keyframe, in units per second.
  static PropertyResolver makeScaleTimeline(
    List<double> times,
    List<Vector3> values, {
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
    List<Vector3>? inTangents,
    List<Vector3>? outTangents,
  }) {
    return ScaleTimelineResolver._(
      times,
      values,
      interpolation,
      inTangents,
      outTangents,
    );
  }

  /// Creates a morph weights resolver that linearly interpolates between
  /// keyframed weight vectors.
  ///
  /// [values] is the flattened keyframe data, [targetCount] weights per
  /// keyframe in target order (`times.length * targetCount` floats), the
  /// shape a glTF `weights` sampler decodes to.
  ///
  /// [interpolation] selects how values are produced between keyframes.
  /// [inTangents] and [outTangents] are required by (and only by)
  /// [TimelineInterpolation.cubic], and carry the same flattened shape as
  /// [values], in units per second.
  static PropertyResolver makeMorphWeightsTimeline(
    List<double> times,
    Float32List values, {
    required int targetCount,
    TimelineInterpolation interpolation = TimelineInterpolation.linear,
    Float32List? inTangents,
    Float32List? outTangents,
  }) {
    return MorphWeightsTimelineResolver._(
      times,
      values,
      targetCount,
      interpolation,
      inTangents,
      outTangents,
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

// Cubic Hermite basis, in the glTF CUBICSPLINE form: p(s) = h00*v0 +
// h10*(dt*m0) + h01*v1 + h11*(dt*m1), where m0 is the segment's starting
// keyframe's out-tangent and m1 the ending keyframe's in-tangent.
double _h00(double s) => 2 * s * s * s - 3 * s * s + 1;
double _h10(double s) => s * s * s - 2 * s * s + s;
double _h01(double s) => -2 * s * s * s + 3 * s * s;
double _h11(double s) => s * s * s - s * s;

double _hermite(
  double v0,
  double m0,
  double v1,
  double m1,
  double s,
  double dt,
) => v0 * _h00(s) + m0 * dt * _h10(s) + v1 * _h01(s) + m1 * dt * _h11(s);

Vector3 _hermiteVector3(
  Vector3 v0,
  Vector3 m0,
  Vector3 v1,
  Vector3 m1,
  double s,
  double dt,
) => Vector3(
  _hermite(v0.x, m0.x, v1.x, m1.x, s, dt),
  _hermite(v0.y, m0.y, v1.y, m1.y, s, dt),
  _hermite(v0.z, m0.z, v1.z, m1.z, s, dt),
);

/// Component-wise Hermite followed by a normalize, which is what the glTF
/// spec prescribes for a `CUBICSPLINE` rotation sampler. The interpolant is
/// not a great-circle arc, but it passes through every keyframe with the
/// authored tangent, which slerping the segment ends would not.
Quaternion _hermiteQuaternion(
  Quaternion v0,
  Quaternion m0,
  Quaternion v1,
  Quaternion m1,
  double s,
  double dt,
) => Quaternion(
  _hermite(v0.x, m0.x, v1.x, m1.x, s, dt),
  _hermite(v0.y, m0.y, v1.y, m1.y, s, dt),
  _hermite(v0.z, m0.z, v1.z, m1.z, s, dt),
  _hermite(v0.w, m0.w, v1.w, m1.w, s, dt),
)..normalize();

/// Shared keyframe lookup for the per-property timeline resolvers.
///
/// Implementations supply the value-array storage and per-frame
/// interpolation; this base class handles binary-style search through
/// the time axis to compute a `(index, lerp)` pair.
abstract class TimelineResolver implements PropertyResolver {
  final List<double> _times;

  /// How values are produced between keyframes.
  final TimelineInterpolation interpolation;

  TimelineResolver._(this._times, this.interpolation);

  /// Whether this timeline evaluates cubic Hermite segments.
  bool get _cubic => interpolation == TimelineInterpolation.cubic;

  /// The seconds spanned by the segment ending at keyframe [index]. Hermite
  /// tangents are per second, so the basis needs the segment's duration to
  /// scale them into the segment's own parameter space.
  double _segmentSeconds(int index) => _times[index] - _times[index - 1];

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
    // Step holds the previous keyframe until the next one is reached, which
    // is exactly a lerp weight pinned to zero for the whole segment.
    if (interpolation == TimelineInterpolation.step) {
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

  /// The per-keyframe tangents, set only for
  /// [TimelineInterpolation.cubic].
  final List<Vector3>? _inTangents;
  final List<Vector3>? _outTangents;

  /// The per-keyframe in-tangents, or null when not cubic. Read by the
  /// scene serializer.
  List<Vector3>? get inTangents =>
      _inTangents == null ? null : List.unmodifiable(_inTangents);

  /// The per-keyframe out-tangents, or null when not cubic. Read by the
  /// scene serializer.
  List<Vector3>? get outTangents =>
      _outTangents == null ? null : List.unmodifiable(_outTangents);

  TranslationTimelineResolver._(
    List<double> times,
    this._values,
    TimelineInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(times.length == _values.length);
    assert(_tangentsMatch(interpolation, times.length, _inTangents?.length));
    assert(_tangentsMatch(interpolation, times.length, _outTangents?.length));
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Vector3 value = _values[key.index];
    if (key.lerp < 1) {
      value = _cubic
          ? _hermiteVector3(
              _values[key.index - 1],
              _outTangents![key.index - 1],
              value,
              _inTangents![key.index],
              key.lerp,
              _segmentSeconds(key.index),
            )
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

  /// The per-keyframe tangents, set only for
  /// [TimelineInterpolation.cubic].
  final List<Quaternion>? _inTangents;
  final List<Quaternion>? _outTangents;

  /// The per-keyframe in-tangents, or null when not cubic. Read by the
  /// scene serializer.
  List<Quaternion>? get inTangents =>
      _inTangents == null ? null : List.unmodifiable(_inTangents);

  /// The per-keyframe out-tangents, or null when not cubic. Read by the
  /// scene serializer.
  List<Quaternion>? get outTangents =>
      _outTangents == null ? null : List.unmodifiable(_outTangents);

  RotationTimelineResolver._(
    List<double> times,
    this._values,
    TimelineInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(times.length == _values.length);
    assert(_tangentsMatch(interpolation, times.length, _inTangents?.length));
    assert(_tangentsMatch(interpolation, times.length, _outTangents?.length));
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Quaternion value = _values[key.index];
    if (key.lerp < 1) {
      value = _cubic
          ? _hermiteQuaternion(
              _values[key.index - 1],
              _outTangents![key.index - 1],
              value,
              _inTangents![key.index],
              key.lerp,
              _segmentSeconds(key.index),
            )
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

  /// The per-keyframe tangents, set only for
  /// [TimelineInterpolation.cubic].
  final List<Vector3>? _inTangents;
  final List<Vector3>? _outTangents;

  /// The per-keyframe in-tangents, or null when not cubic. Read by the
  /// scene serializer.
  List<Vector3>? get inTangents =>
      _inTangents == null ? null : List.unmodifiable(_inTangents);

  /// The per-keyframe out-tangents, or null when not cubic. Read by the
  /// scene serializer.
  List<Vector3>? get outTangents =>
      _outTangents == null ? null : List.unmodifiable(_outTangents);

  ScaleTimelineResolver._(
    List<double> times,
    this._values,
    TimelineInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(times.length == _values.length);
    assert(_tangentsMatch(interpolation, times.length, _inTangents?.length));
    assert(_tangentsMatch(interpolation, times.length, _outTangents?.length));
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Vector3 value = _values[key.index];
    if (key.lerp < 1) {
      value = _cubic
          ? _hermiteVector3(
              _values[key.index - 1],
              _outTangents![key.index - 1],
              value,
              _inTangents![key.index],
              key.lerp,
              _segmentSeconds(key.index),
            )
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

  /// The per-keyframe tangents, flattened like [_values] and set only for
  /// [TimelineInterpolation.cubic].
  final Float32List? _inTangents;
  final Float32List? _outTangents;

  /// The flattened per-keyframe in-tangents, or null when not cubic. Read
  /// by the scene serializer.
  Float32List? get inTangents =>
      _inTangents == null ? null : Float32List.fromList(_inTangents);

  /// The flattened per-keyframe out-tangents, or null when not cubic. Read
  /// by the scene serializer.
  Float32List? get outTangents =>
      _outTangents == null ? null : Float32List.fromList(_outTangents);

  MorphWeightsTimelineResolver._(
    List<double> times,
    this._values,
    this.targetCount,
    TimelineInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(targetCount >= 0);
    assert(times.length * targetCount == _values.length);
    assert(_tangentsMatch(interpolation, _values.length, _inTangents?.length));
    assert(_tangentsMatch(interpolation, _values.length, _outTangents?.length));
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
    final current = key.index * targetCount;
    final previous = (key.index - 1) * targetCount;
    final count = targetCount < animated.length ? targetCount : animated.length;
    final segment = key.lerp < 1 && _cubic ? _segmentSeconds(key.index) : 0.0;
    for (var i = 0; i < count; i++) {
      var value = _values[current + i];
      if (key.lerp < 1) {
        final a = _values[previous + i];
        value = _cubic
            ? _hermite(
                a,
                _outTangents![previous + i],
                value,
                _inTangents![current + i],
                key.lerp,
                segment,
              )
            : a + (value - a) * key.lerp;
      }
      animated[i] += (value - bind[i]) * weight;
    }
  }
}

/// Whether a tangent list of [tangentLength] entries fits a timeline of
/// [valueLength] values under [interpolation]: cubic needs exactly one
/// tangent per value, and every other mode needs none at all.
bool _tangentsMatch(
  TimelineInterpolation interpolation,
  int valueLength,
  int? tangentLength,
) => interpolation == TimelineInterpolation.cubic
    ? tangentLength == valueLength
    : tangentLength == null;
