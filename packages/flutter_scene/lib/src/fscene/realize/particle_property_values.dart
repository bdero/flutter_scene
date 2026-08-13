/// Conversions between the particle value generators ([FloatDistribution],
/// [ParticleCurve], [ColorGradient]) and the structured [PropertyValue]s the
/// `.fscene` format and the editor carry for the `distribution`, `curve`, and
/// `gradient` property kinds.
///
/// Each value is a tagged [MapValue] of plain scalars, lists, and colors, so it
/// rides the existing property serialization (text and binary) and the editor's
/// value coercion with no special cases. The shapes are:
///
///  * curve: `{keys: [{t, v}, ...]}`
///  * gradient: `{stops: [{t, color: {r, g, b, a}}, ...]}`
///  * distribution: `{kind: 'constant'|'uniform'|'curve'|'uniformCurve', ...}`
///  * color distribution: `{kind: 'constant'|'gradient'|'uniform', ...}`
///
/// Decoding is tolerant: missing or malformed entries fall back to sensible
/// defaults rather than throwing, so a hand-edited document still loads.
library;

import 'package:vector_math/vector_math.dart';

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/particles/distribution.dart';

// --- ParticleCurve ---

/// Encodes [curve]'s control points as `{keys: [{t, v}, ...]}`.
MapValue encodeParticleCurve(ParticleCurve curve) => MapValue({
  'keys': ListValue([
    for (final k in curve.keyframes)
      MapValue({'t': DoubleValue(k.t), 'v': DoubleValue(k.value)}),
  ]),
});

/// Decodes a [ParticleCurve] from [value]; an empty or absent key list yields a
/// constant-zero curve.
ParticleCurve decodeParticleCurve(PropertyValue? value) {
  final keys = <ParticleKeyframe>[];
  if (value is MapValue && value.values['keys'] is ListValue) {
    for (final entry in (value.values['keys']! as ListValue).values) {
      if (entry is MapValue) {
        keys.add(
          ParticleKeyframe(
            readDouble(entry.values, 't', 0),
            readDouble(entry.values, 'v', 0),
          ),
        );
      }
    }
  }
  return ParticleCurve(keys);
}

// --- ColorGradient ---

/// Encodes [gradient]'s stops as `{stops: [{t, color: {r, g, b, a}}, ...]}`.
MapValue encodeColorGradient(ColorGradient gradient) => MapValue({
  'stops': ListValue([
    for (final s in gradient.stops)
      MapValue({
        't': DoubleValue(s.t),
        'color': ColorValue(s.color.x, s.color.y, s.color.z, s.color.w),
      }),
  ]),
});

/// Decodes a [ColorGradient] from [value]; an empty or absent stop list yields
/// the gradient's opaque-white default.
ColorGradient decodeColorGradient(PropertyValue? value) {
  final stops = <ColorStop>[];
  if (value is MapValue && value.values['stops'] is ListValue) {
    for (final entry in (value.values['stops']! as ListValue).values) {
      if (entry is MapValue) {
        final c = entry.values['color'];
        final color = c is ColorValue
            ? Vector4(c.r, c.g, c.b, c.a)
            : Vector4(1, 1, 1, 1);
        stops.add(ColorStop(readDouble(entry.values, 't', 0), color));
      }
    }
  }
  return ColorGradient(stops);
}

// --- FloatDistribution ---

/// Encodes [distribution] as a tagged map keyed on its variant.
MapValue encodeFloatDistribution(FloatDistribution distribution) {
  return switch (distribution) {
    ConstantFloat(:final value) => MapValue({
      'kind': const StringValue('constant'),
      'value': DoubleValue(value),
    }),
    UniformFloat(:final min, :final max) => MapValue({
      'kind': const StringValue('uniform'),
      'min': DoubleValue(min),
      'max': DoubleValue(max),
    }),
    CurveFloat(:final curve, :final scale) => MapValue({
      'kind': const StringValue('curve'),
      'curve': encodeParticleCurve(curve),
      'scale': DoubleValue(scale),
    }),
    UniformCurveFloat(:final min, :final max) => MapValue({
      'kind': const StringValue('uniformCurve'),
      'min': encodeParticleCurve(min),
      'max': encodeParticleCurve(max),
    }),
  };
}

/// Decodes a [FloatDistribution] from [value]; an unrecognized or absent value
/// yields `ConstantFloat(fallback)`.
FloatDistribution decodeFloatDistribution(
  PropertyValue? value, {
  double fallback = 0.0,
}) {
  if (value is! MapValue) return ConstantFloat(fallback);
  final m = value.values;
  final kind = m['kind'] is StringValue
      ? (m['kind']! as StringValue).value
      : 'constant';
  return switch (kind) {
    'uniform' => UniformFloat(
      readDouble(m, 'min', fallback),
      readDouble(m, 'max', fallback),
    ),
    'curve' => CurveFloat(
      decodeParticleCurve(m['curve']),
      scale: readDouble(m, 'scale', 1.0),
    ),
    'uniformCurve' => UniformCurveFloat(
      decodeParticleCurve(m['min']),
      decodeParticleCurve(m['max']),
    ),
    _ => ConstantFloat(readDouble(m, 'value', fallback)),
  };
}

// --- ColorDistribution ---

/// Encodes [distribution] as a tagged map keyed on its variant.
MapValue encodeColorDistribution(ColorDistribution distribution) {
  return switch (distribution) {
    ConstantColor(:final color) => MapValue({
      'kind': const StringValue('constant'),
      'color': ColorValue(color.x, color.y, color.z, color.w),
    }),
    GradientColor(:final gradient) => MapValue({
      'kind': const StringValue('gradient'),
      'gradient': encodeColorGradient(gradient),
    }),
    UniformColor(:final a, :final b) => MapValue({
      'kind': const StringValue('uniform'),
      'a': ColorValue(a.x, a.y, a.z, a.w),
      'b': ColorValue(b.x, b.y, b.z, b.w),
    }),
  };
}

/// Decodes a [ColorDistribution] from [value]; an unrecognized or absent value
/// yields a [ConstantColor] of [fallback] (opaque white when omitted).
ColorDistribution decodeColorDistribution(
  PropertyValue? value, {
  Vector4? fallback,
}) {
  final fallbackColor = fallback ?? Vector4(1, 1, 1, 1);
  if (value is! MapValue) return ConstantColor(fallbackColor);
  final m = value.values;
  final kind = m['kind'] is StringValue
      ? (m['kind']! as StringValue).value
      : 'constant';
  return switch (kind) {
    'gradient' => GradientColor(decodeColorGradient(m['gradient'])),
    'uniform' => UniformColor(
      _c(m['a'], fallbackColor),
      _c(m['b'], fallbackColor),
    ),
    _ => ConstantColor(_c(m['color'], fallbackColor)),
  };
}

Vector4 _c(PropertyValue? v, Vector4 fallback) =>
    v is ColorValue ? Vector4(v.r, v.g, v.b, v.a) : fallback.clone();
