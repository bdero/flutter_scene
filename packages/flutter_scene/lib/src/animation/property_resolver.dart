part of '../animation.dart';

/// Computes a per-property animated value from a timeline of keyframes.
///
/// Subclasses cover the [AnimationProperty] flavors. Between keyframes each
/// moves as its [AnimationInterpolation] says: holding the previous value,
/// interpolating linearly (spherically for rotation), or following a cubic
/// spline. Use the [PropertyResolver] factories to construct one rather than
/// instantiating subclasses directly.
///
/// A cubic spline timeline takes an in-tangent and an out-tangent per
/// keyframe. Tangents are per second, as glTF stores them, so each segment
/// scales them by its duration.
abstract class PropertyResolver {
  /// Returns the end time of the property in seconds.
  double getEndTime();

  /// Resolve and apply the property value to a target node. This
  /// operation is additive; a given node property may be amended by
  /// many different PropertyResolvers prior to rendering. For example,
  /// an AnimationPlayer may blend multiple Animations together by
  /// applying several AnimationClips.
  void apply(AnimationTransforms target, double timeInSeconds, double weight);

  /// Creates a translation resolver over the keyframe positions in [values]
  /// at the corresponding [times], moving between them as [interpolation]
  /// says.
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing. A cubic spline also needs [inTangents]
  /// and [outTangents], one per keyframe.
  static PropertyResolver makeTranslationTimeline(
    List<double> times,
    List<Vector3> values, {
    AnimationInterpolation interpolation = AnimationInterpolation.linear,
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

  /// Creates a rotation resolver over the keyframe quaternions in [values]
  /// at the corresponding [times]. A linear timeline interpolates them
  /// spherically, and a cubic spline normalizes each result.
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing. A cubic spline also needs [inTangents]
  /// and [outTangents], one per keyframe.
  static PropertyResolver makeRotationTimeline(
    List<double> times,
    List<Quaternion> values, {
    AnimationInterpolation interpolation = AnimationInterpolation.linear,
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

  /// Creates a scale resolver over the keyframe scales in [values] at the
  /// corresponding [times], moving between them as [interpolation] says.
  ///
  /// `times` and `values` must have the same length and `times` must be
  /// monotonically non-decreasing. A cubic spline also needs [inTangents]
  /// and [outTangents], one per keyframe.
  static PropertyResolver makeScaleTimeline(
    List<double> times,
    List<Vector3> values, {
    AnimationInterpolation interpolation = AnimationInterpolation.linear,
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

  /// Creates a morph weights resolver over keyframed weight vectors.
  ///
  /// [values] is the flattened keyframe data, [targetCount] weights per
  /// keyframe in target order (`times.length * targetCount` floats), the
  /// shape a glTF `weights` sampler decodes to. A cubic spline's
  /// [inTangents] and [outTangents] are flattened the same way.
  static PropertyResolver makeMorphWeightsTimeline(
    List<double> times,
    Float32List values, {
    required int targetCount,
    AnimationInterpolation interpolation = AnimationInterpolation.linear,
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

  /// Creates a resolver for the [AnimationProperty.path] property [path],
  /// with [componentCount] floats per keyframe. A cubic spline's
  /// [inTangents] and [outTangents] are flattened like [values].
  static PropertyResolver makePathTimeline(
    String path,
    List<double> times,
    Float32List values, {
    required int componentCount,
    AnimationInterpolation interpolation = AnimationInterpolation.linear,
    Float32List? inTangents,
    Float32List? outTangents,
  }) {
    return PathTimelineResolver._(
      path,
      times,
      values,
      componentCount,
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

/// Shared keyframe lookup for the per-property timeline resolvers.
///
/// Implementations supply the value-array storage and per-frame
/// interpolation; this base class handles binary-style search through
/// the time axis to compute a `(index, lerp)` pair.
abstract class TimelineResolver implements PropertyResolver {
  final List<double> _times;

  /// How the timeline moves between keyframes.
  final AnimationInterpolation interpolation;

  TimelineResolver._(this._times, this.interpolation);

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
    return _TimelineKey(nextTimeIndex, lerp);
  }

  /// The cubic Hermite weights at [key], which lies between two keyframes,
  /// for the previous keyframe's value, its out-tangent, the next keyframe's
  /// value, and that keyframe's in-tangent. The tangent weights include the
  /// segment's duration.
  (double, double, double, double) _cubicWeights(_TimelineKey key) {
    final s = key.lerp;
    final s2 = s * s;
    final s3 = s2 * s;
    final duration = _times[key.index] - _times[key.index - 1];
    return (
      2 * s3 - 3 * s2 + 1,
      (s3 - 2 * s2 + s) * duration,
      -2 * s3 + 3 * s2,
      (s3 - s2) * duration,
    );
  }

  /// The value at [key], which lies between two keyframes, of a [Vector3]
  /// timeline.
  Vector3 _vector3Between(
    _TimelineKey key,
    List<Vector3> values,
    List<Vector3>? inTangents,
    List<Vector3>? outTangents,
  ) {
    final previous = values[key.index - 1];
    final next = values[key.index];
    switch (interpolation) {
      case AnimationInterpolation.step:
        return previous;
      case AnimationInterpolation.linear:
        return previous.lerp(next, key.lerp);
      case AnimationInterpolation.cubicSpline:
        final (fromValue, fromTangent, toValue, toTangent) = _cubicWeights(key);
        return previous * fromValue +
            outTangents![key.index - 1] * fromTangent +
            next * toValue +
            inTangents![key.index] * toTangent;
    }
  }

  /// The value at [key], which lies between two keyframes, of one component
  /// of a flattened timeline, whose floats for those keyframes sit at
  /// [previous] and [next].
  double _componentBetween(
    _TimelineKey key,
    Float32List values,
    Float32List? inTangents,
    Float32List? outTangents,
    int previous,
    int next,
  ) {
    switch (interpolation) {
      case AnimationInterpolation.step:
        return values[previous];
      case AnimationInterpolation.linear:
        final a = values[previous];
        return a + (values[next] - a) * key.lerp;
      case AnimationInterpolation.cubicSpline:
        final (fromValue, fromTangent, toValue, toTangent) = _cubicWeights(key);
        return values[previous] * fromValue +
            outTangents![previous] * fromTangent +
            values[next] * toValue +
            inTangents![next] * toTangent;
    }
  }
}

/// Whether a timeline with [count] values has the tangents its
/// [interpolation] needs, one per value.
bool _hasTangents(
  AnimationInterpolation interpolation,
  int count,
  int? inTangentCount,
  int? outTangentCount,
) {
  return interpolation != AnimationInterpolation.cubicSpline ||
      (inTangentCount == count && outTangentCount == count);
}

/// Resolves a translation timeline, blended into
/// [AnimationTransforms.animatedPose] as an offset from the bind pose.
class TranslationTimelineResolver extends TimelineResolver {
  final List<Vector3> _values;
  final List<Vector3>? _inTangents;
  final List<Vector3>? _outTangents;

  /// The keyframe values. Read by the scene serializer.
  List<Vector3> get values => List.unmodifiable(_values);

  /// The cubic spline in-tangents, if any. Read by the scene serializer.
  List<Vector3>? get inTangents =>
      _inTangents == null ? null : List.unmodifiable(_inTangents);

  /// The cubic spline out-tangents, if any. Read by the scene serializer.
  List<Vector3>? get outTangents =>
      _outTangents == null ? null : List.unmodifiable(_outTangents);

  TranslationTimelineResolver._(
    List<double> times,
    this._values,
    AnimationInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(times.length == _values.length);
    assert(
      _hasTangents(
        interpolation,
        _values.length,
        _inTangents?.length,
        _outTangents?.length,
      ),
    );
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Vector3 value = _values[key.index];
    if (key.lerp < 1) {
      value = _vector3Between(key, _values, _inTangents, _outTangents);
    }

    target.animatedPose.translation +=
        (value - target.bindPose.translation) * weight;
  }
}

/// Resolves a rotation timeline, accumulating clip weights relative to the
/// node's uncovered bind weight. Two fully covering clips interpolate
/// directly between their poses. Three or more rotations use incremental
/// weighted slerp in registration order.
class RotationTimelineResolver extends TimelineResolver {
  final List<Quaternion> _values;
  final List<Quaternion>? _inTangents;
  final List<Quaternion>? _outTangents;

  /// The keyframe values. Read by the scene serializer.
  List<Quaternion> get values => List.unmodifiable(_values);

  /// The cubic spline in-tangents, if any. Read by the scene serializer.
  List<Quaternion>? get inTangents =>
      _inTangents == null ? null : List.unmodifiable(_inTangents);

  /// The cubic spline out-tangents, if any. Read by the scene serializer.
  List<Quaternion>? get outTangents =>
      _outTangents == null ? null : List.unmodifiable(_outTangents);

  RotationTimelineResolver._(
    List<double> times,
    this._values,
    AnimationInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(times.length == _values.length);
    assert(
      _hasTangents(
        interpolation,
        _values.length,
        _inTangents?.length,
        _outTangents?.length,
      ),
    );
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty || weight <= 0) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Quaternion value = _values[key.index];
    if (key.lerp < 1) {
      value = _between(key);
    }

    final accumulated = target.rotationBlendWeight == null
        ? null
        : target.rotationBlendWeight! + weight;
    target.animatedPose.rotation = target.animatedPose.rotation.slerp(
      value,
      accumulated == null ? weight : weight / accumulated,
    );
    target.rotationBlendWeight = accumulated;
  }

  /// The rotation at [key], which lies between two keyframes.
  Quaternion _between(_TimelineKey key) {
    final previous = _values[key.index - 1];
    final next = _values[key.index];
    switch (interpolation) {
      case AnimationInterpolation.step:
        return previous;
      case AnimationInterpolation.linear:
        return previous.slerp(next, key.lerp);
      case AnimationInterpolation.cubicSpline:
        // glTF splines a rotation per component, then normalizes it.
        final (fromValue, fromTangent, toValue, toTangent) = _cubicWeights(key);
        final spline =
            previous.scaled(fromValue) +
            _outTangents![key.index - 1].scaled(fromTangent) +
            next.scaled(toValue) +
            _inTangents![key.index].scaled(toTangent);
        return spline.normalized();
    }
  }
}

/// Resolves a scale timeline.
///
/// The blended scale is normalized against the bind pose so weighted
/// blends behave multiplicatively (a weight of `1` reaches the keyframe
/// scale exactly).
class ScaleTimelineResolver extends TimelineResolver {
  final List<Vector3> _values;
  final List<Vector3>? _inTangents;
  final List<Vector3>? _outTangents;

  /// The keyframe values. Read by the scene serializer.
  List<Vector3> get values => List.unmodifiable(_values);

  /// The cubic spline in-tangents, if any. Read by the scene serializer.
  List<Vector3>? get inTangents =>
      _inTangents == null ? null : List.unmodifiable(_inTangents);

  /// The cubic spline out-tangents, if any. Read by the scene serializer.
  List<Vector3>? get outTangents =>
      _outTangents == null ? null : List.unmodifiable(_outTangents);

  ScaleTimelineResolver._(
    List<double> times,
    this._values,
    AnimationInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(times.length == _values.length);
    assert(
      _hasTangents(
        interpolation,
        _values.length,
        _inTangents?.length,
        _outTangents?.length,
      ),
    );
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    if (_values.isEmpty) {
      return;
    }

    _TimelineKey key = _getTimelineKey(timeInSeconds);
    Vector3 value = _values[key.index];
    if (key.lerp < 1) {
      value = _vector3Between(key, _values, _inTangents, _outTangents);
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

/// Resolves a morph weights timeline per target, blended into
/// [AnimationTransforms.animatedMorphWeights] as an offset from the rest
/// weights (matching the translation blend rule).
class MorphWeightsTimelineResolver extends TimelineResolver {
  final Float32List _values;
  final Float32List? _inTangents;
  final Float32List? _outTangents;

  /// Weights per keyframe.
  final int targetCount;

  /// The flattened keyframe values ([targetCount] per keyframe). Read by
  /// the scene serializer.
  Float32List get values => Float32List.fromList(_values);

  /// The flattened cubic spline in-tangents, if any.
  Float32List? get inTangents =>
      _inTangents == null ? null : Float32List.fromList(_inTangents);

  /// The flattened cubic spline out-tangents, if any.
  Float32List? get outTangents =>
      _outTangents == null ? null : Float32List.fromList(_outTangents);

  MorphWeightsTimelineResolver._(
    List<double> times,
    this._values,
    this.targetCount,
    AnimationInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(targetCount >= 0);
    assert(times.length * targetCount == _values.length);
    assert(
      _hasTangents(
        interpolation,
        _values.length,
        _inTangents?.length,
        _outTangents?.length,
      ),
    );
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
    for (var i = 0; i < count; i++) {
      var value = _values[current + i];
      if (key.lerp < 1) {
        value = _componentBetween(
          key,
          _values,
          _inTangents,
          _outTangents,
          previous + i,
          current + i,
        );
      }
      animated[i] += (value - bind[i]) * weight;
    }
  }
}

/// Resolves a path property timeline, blended into the path's
/// [AnimatedPathState] as an offset from its rest value (matching the
/// translation blend rule).
class PathTimelineResolver extends TimelineResolver {
  /// The property this drives, relative to the bound node.
  final String path;

  final Float32List _values;
  final Float32List? _inTangents;
  final Float32List? _outTangents;

  /// Floats per keyframe.
  final int componentCount;

  /// The flattened keyframe values ([componentCount] per keyframe). Read by
  /// the scene serializer.
  Float32List get values => Float32List.fromList(_values);

  /// The flattened cubic spline in-tangents, if any. Read by the scene
  /// serializer.
  Float32List? get inTangents =>
      _inTangents == null ? null : Float32List.fromList(_inTangents);

  /// The flattened cubic spline out-tangents, if any. Read by the scene
  /// serializer.
  Float32List? get outTangents =>
      _outTangents == null ? null : Float32List.fromList(_outTangents);

  PathTimelineResolver._(
    this.path,
    List<double> times,
    this._values,
    this.componentCount,
    AnimationInterpolation interpolation,
    this._inTangents,
    this._outTangents,
  ) : super._(times, interpolation) {
    assert(componentCount > 0);
    assert(times.length * componentCount == _values.length);
    assert(
      _hasTangents(
        interpolation,
        _values.length,
        _inTangents?.length,
        _outTangents?.length,
      ),
    );
  }

  @override
  void apply(AnimationTransforms target, double timeInSeconds, double weight) {
    final state = target.paths[path];
    if (state == null || _values.isEmpty) return;
    final key = _getTimelineKey(timeInSeconds);
    final current = key.index * componentCount;
    final previous = (key.index - 1) * componentCount;
    final count = min(componentCount, state.animated.length);
    for (var i = 0; i < count; i++) {
      var value = _values[current + i];
      if (key.lerp < 1) {
        value = _componentBetween(
          key,
          _values,
          _inTangents,
          _outTangents,
          previous + i,
          current + i,
        );
      }
      state.animated[i] += (value - state.bind[i]) * weight;
    }
  }
}
