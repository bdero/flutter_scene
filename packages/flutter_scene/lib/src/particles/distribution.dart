import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// One control point of a [ParticleCurve]: a [value] at normalized time [t]
/// (in `[0, 1]`).
class ParticleKeyframe {
  /// Creates a keyframe placing [value] at normalized time [t].
  const ParticleKeyframe(this.t, this.value);

  /// Normalized time of this keyframe, clamped into `[0, 1]` when baked.
  final double t;

  /// The curve value at [t].
  final double value;
}

/// A scalar curve over normalized time `[0, 1]`, authored as keyframes and
/// baked once into a lookup table so per-particle, per-frame [sample] calls are
/// a cheap clamped table lerp rather than a keyframe search.
///
/// Particle properties that vary over a particle's life (size, rotation,
/// alpha, drag) read a curve keyed on `age / lifetime`; system parameters that
/// vary over the emitter's run (emit rate) read one keyed on system age. The
/// curve is piecewise-linear between keyframes and clamped to the first/last
/// value outside their range.
class ParticleCurve {
  /// Builds a curve from [keyframes], baked into a [resolution]-entry table.
  ///
  /// Keyframes need not be sorted; ties keep their relative order. An empty
  /// list is treated as a constant `0`. [resolution] must be at least 2.
  ParticleCurve(List<ParticleKeyframe> keyframes, {this.resolution = 64})
    : assert(resolution >= 2),
      _lut = Float32List(resolution) {
    final sorted = [...keyframes]..sort((a, b) => a.t.compareTo(b.t));
    _bake(sorted);
  }

  /// A curve that is [value] everywhere.
  ParticleCurve.constant(double value)
    : this(<ParticleKeyframe>[ParticleKeyframe(0, value)], resolution: 2);

  /// A straight ramp from [from] at `t = 0` to [to] at `t = 1`.
  ParticleCurve.linear({double from = 0.0, double to = 1.0})
    : this(<ParticleKeyframe>[
        ParticleKeyframe(0, from),
        ParticleKeyframe(1, to),
      ], resolution: 2);

  /// The number of baked lookup-table entries.
  final int resolution;

  final Float32List _lut;

  void _bake(List<ParticleKeyframe> sorted) {
    if (sorted.isEmpty) {
      // Constant zero.
      for (var i = 0; i < resolution; i++) {
        _lut[i] = 0.0;
      }
      return;
    }
    for (var i = 0; i < resolution; i++) {
      final t = i / (resolution - 1);
      _lut[i] = _evaluateKeyframes(sorted, t);
    }
  }

  static double _evaluateKeyframes(List<ParticleKeyframe> sorted, double t) {
    // Clamp outside the keyframe range to the end values.
    if (t <= sorted.first.t) return sorted.first.value;
    if (t >= sorted.last.t) return sorted.last.value;
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (t >= a.t && t <= b.t) {
        final span = b.t - a.t;
        if (span <= 0) return b.value;
        final f = (t - a.t) / span;
        return a.value + (b.value - a.value) * f;
      }
    }
    return sorted.last.value;
  }

  /// Samples the curve at normalized time [t] (clamped into `[0, 1]`).
  double sample(double t) {
    final clamped = t < 0.0
        ? 0.0
        : t > 1.0
        ? 1.0
        : t;
    final x = clamped * (resolution - 1);
    final i = x.floor();
    if (i >= resolution - 1) return _lut[resolution - 1];
    final f = x - i;
    return _lut[i] + (_lut[i + 1] - _lut[i]) * f;
  }
}

/// One color stop of a [ColorGradient]: a linear RGBA [color] at normalized
/// time [t].
class ColorStop {
  /// Creates a stop placing [color] (linear RGBA) at normalized time [t].
  const ColorStop(this.t, this.color);

  /// Normalized time of this stop, in `[0, 1]`.
  final double t;

  /// Linear RGBA color at [t].
  final Vector4 color;
}

/// A color curve over normalized time `[0, 1]`, baked into a lookup table.
///
/// Like [ParticleCurve] but for linear RGBA colors. Used for color-over-life
/// gradients. Linearly interpolates between stops and clamps to the first/last
/// color outside their range.
class ColorGradient {
  /// Builds a gradient from [stops], baked into a [resolution]-entry table.
  ///
  /// Stops need not be sorted. An empty list is treated as opaque white. Each
  /// table entry holds four floats (r, g, b, a). [resolution] must be >= 2.
  ColorGradient(List<ColorStop> stops, {this.resolution = 64})
    : assert(resolution >= 2),
      _lut = Float32List(resolution * 4) {
    final sorted = [...stops]..sort((a, b) => a.t.compareTo(b.t));
    _bake(sorted);
  }

  /// A gradient that is [color] everywhere.
  ColorGradient.constant(Vector4 color)
    : this(<ColorStop>[ColorStop(0, color)], resolution: 2);

  /// The number of baked lookup-table entries (each four floats).
  final int resolution;

  final Float32List _lut;

  void _bake(List<ColorStop> sorted) {
    for (var i = 0; i < resolution; i++) {
      final t = i / (resolution - 1);
      final c = _evaluateStops(sorted, t);
      final o = i * 4;
      _lut[o] = c.x;
      _lut[o + 1] = c.y;
      _lut[o + 2] = c.z;
      _lut[o + 3] = c.w;
    }
  }

  static Vector4 _evaluateStops(List<ColorStop> sorted, double t) {
    if (sorted.isEmpty) return Vector4(1, 1, 1, 1);
    if (t <= sorted.first.t) return sorted.first.color.clone();
    if (t >= sorted.last.t) return sorted.last.color.clone();
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (t >= a.t && t <= b.t) {
        final span = b.t - a.t;
        if (span <= 0) return b.color.clone();
        final f = (t - a.t) / span;
        return a.color + (b.color - a.color) * f;
      }
    }
    return sorted.last.color.clone();
  }

  /// Samples the gradient at normalized time [t] (clamped into `[0, 1]`),
  /// writing the result into [out] (allocated when null) and returning it.
  Vector4 sample(double t, [Vector4? out]) {
    final result = out ?? Vector4.zero();
    final clamped = t < 0.0
        ? 0.0
        : t > 1.0
        ? 1.0
        : t;
    final x = clamped * (resolution - 1);
    var i = x.floor();
    if (i >= resolution - 1) {
      final o = (resolution - 1) * 4;
      result.setValues(_lut[o], _lut[o + 1], _lut[o + 2], _lut[o + 3]);
      return result;
    }
    final f = x - i;
    final o = i * 4;
    final n = o + 4;
    result.setValues(
      _lut[o] + (_lut[n] - _lut[o]) * f,
      _lut[o + 1] + (_lut[n + 1] - _lut[o + 1]) * f,
      _lut[o + 2] + (_lut[n + 2] - _lut[o + 2]) * f,
      _lut[o + 3] + (_lut[n + 3] - _lut[o + 3]) * f,
    );
    return result;
  }
}

/// A scalar value generator sampled per particle, the single value type behind
/// every scalar particle parameter.
///
/// [sample] takes the particle's normalized age (`age / lifetime`, in `[0, 1]`)
/// and a per-particle random in `[0, 1)` (stored at birth so sampling is
/// deterministic and repeatable). The variants cover the four common authoring
/// modes: a constant, a random range, a curve over life, and a per-particle
/// random blend between two curves.
sealed class FloatDistribution {
  const FloatDistribution();

  /// Returns the value for a particle at [normalizedAge] with per-particle
  /// random [random01].
  double sample(double normalizedAge, double random01);
}

/// A [FloatDistribution] that is [value] for every particle.
class ConstantFloat extends FloatDistribution {
  /// Creates a constant distribution.
  const ConstantFloat(this.value);

  /// The constant value.
  final double value;

  @override
  double sample(double normalizedAge, double random01) => value;
}

/// A [FloatDistribution] that picks a value in `[min, max]` per particle from
/// its stored random (constant over the particle's life).
class UniformFloat extends FloatDistribution {
  /// Creates a uniform-range distribution over `[min, max]`.
  const UniformFloat(this.min, this.max);

  /// Range bounds; [min] is returned at `random01 == 0`, [max] near `1`.
  final double min, max;

  @override
  double sample(double normalizedAge, double random01) =>
      min + (max - min) * random01;
}

/// A [FloatDistribution] that samples [curve] over the particle's normalized
/// age and scales it by [scale].
class CurveFloat extends FloatDistribution {
  /// Creates a curve-over-life distribution.
  const CurveFloat(this.curve, {this.scale = 1.0});

  /// The curve sampled over normalized age.
  final ParticleCurve curve;

  /// Multiplier applied to the sampled curve value.
  final double scale;

  @override
  double sample(double normalizedAge, double random01) =>
      curve.sample(normalizedAge) * scale;
}

/// A [FloatDistribution] whose value follows, per particle, a blend between a
/// [min] and [max] curve chosen by the particle's stored random. Each particle
/// keeps its own curve inside the envelope for the whole life.
class UniformCurveFloat extends FloatDistribution {
  /// Creates a distribution that blends between [min] and [max] curves by the
  /// per-particle random.
  const UniformCurveFloat(this.min, this.max);

  /// The lower and upper curves of the envelope.
  final ParticleCurve min, max;

  @override
  double sample(double normalizedAge, double random01) {
    final lo = min.sample(normalizedAge);
    final hi = max.sample(normalizedAge);
    return lo + (hi - lo) * random01;
  }
}

/// A color value generator sampled per particle, the color analog of
/// [FloatDistribution].
sealed class ColorDistribution {
  const ColorDistribution();

  /// Writes the color for a particle at [normalizedAge] with per-particle
  /// random [random01] into [out] (allocated when null) and returns it.
  Vector4 sample(double normalizedAge, double random01, [Vector4? out]);
}

/// A [ColorDistribution] that is [color] for every particle.
class ConstantColor extends ColorDistribution {
  /// Creates a constant color distribution.
  const ConstantColor(this.color);

  /// The constant linear RGBA color.
  final Vector4 color;

  @override
  Vector4 sample(double normalizedAge, double random01, [Vector4? out]) {
    final result = out ?? Vector4.zero();
    return result..setFrom(color);
  }
}

/// A [ColorDistribution] that samples [gradient] over the particle's normalized
/// age (color over life).
class GradientColor extends ColorDistribution {
  /// Creates a color-over-life distribution.
  const GradientColor(this.gradient);

  /// The gradient sampled over normalized age.
  final ColorGradient gradient;

  @override
  Vector4 sample(double normalizedAge, double random01, [Vector4? out]) =>
      gradient.sample(normalizedAge, out);
}

/// A [ColorDistribution] that picks a color between [a] and [b] per particle
/// from its stored random (constant over the particle's life).
class UniformColor extends ColorDistribution {
  /// Creates a distribution that blends between [a] and [b] by the per-particle
  /// random.
  const UniformColor(this.a, this.b);

  /// The two endpoint colors.
  final Vector4 a, b;

  @override
  Vector4 sample(double normalizedAge, double random01, [Vector4? out]) {
    final result = out ?? Vector4.zero();
    return result
      ..setFrom(a)
      ..add((b - a)..scale(random01));
  }
}
