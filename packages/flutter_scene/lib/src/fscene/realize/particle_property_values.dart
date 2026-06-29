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
///
/// Decoding is tolerant: missing or malformed entries fall back to sensible
/// defaults rather than throwing, so a hand-edited document still loads.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/particles/distribution.dart';

double _d(PropertyValue? v, [double fallback = 0.0]) => switch (v) {
  DoubleValue(:final value) => value,
  IntValue(:final value) => value.toDouble(),
  _ => fallback,
};

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
          ParticleKeyframe(_d(entry.values['t']), _d(entry.values['v'])),
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
        stops.add(ColorStop(_d(entry.values['t']), color));
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
    'uniform' => UniformFloat(_d(m['min'], fallback), _d(m['max'], fallback)),
    'curve' => CurveFloat(
      decodeParticleCurve(m['curve']),
      scale: _d(m['scale'], 1.0),
    ),
    'uniformCurve' => UniformCurveFloat(
      decodeParticleCurve(m['min']),
      decodeParticleCurve(m['max']),
    ),
    _ => ConstantFloat(_d(m['value'], fallback)),
  };
}
