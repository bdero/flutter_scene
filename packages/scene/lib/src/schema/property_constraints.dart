/// Value constraints a component property declares, an open taxonomy of
/// const objects with tagged JSON forms so constraint lists travel with
/// schemas across process boundaries.
///
/// Every constraint type defines behavior at three enforcement points, the
/// inspector (widget affordance), command coercion (clamp or reject), and
/// realization (clamp with a diagnostic; documents come from anywhere).
/// Tags a consumer does not recognize decode to [UnknownConstraint] and
/// re-encode unchanged, so older editors ignore newer constraints without
/// losing them.
library;

/// A single declared constraint on a property value.
///
/// The type parameter binds a constraint to the value domain it applies to
/// (numbers, strings, lists...), which lets typed authoring surfaces reject
/// inapplicable constraints at compile time.
sealed class PropertyConstraint<T> {
  const PropertyConstraint();

  /// The tagged JSON form, a single-key map (`{'range': {...}}`).
  Map<String, Object?> toJson();

  /// Decodes one tagged constraint, or an [UnknownConstraint] for tags this
  /// build does not know.
  static PropertyConstraint<Object?> fromJson(Map<String, Object?> json) {
    if (json.length != 1) return UnknownConstraint(json);
    final tag = json.keys.single;
    final value = json[tag];
    double? d(Object? v, String key) =>
        v is Map ? (v[key] as num?)?.toDouble() : null;
    int? i(Object? v, String key) =>
        v is Map ? (v[key] as num?)?.toInt() : null;
    switch (tag) {
      case 'range':
        return Range(d(value, 'min'), d(value, 'max'));
      case 'softRange':
        return SoftRange(d(value, 'min') ?? 0, d(value, 'max') ?? 1);
      case 'intRange':
        return IntRange(i(value, 'min'), i(value, 'max'));
      case 'step':
        return Step((value as num?)?.toDouble() ?? 1);
      case 'powerOfTwo':
        return PowerOfTwo(min: i(value, 'min') ?? 1, max: i(value, 'max'));
      case 'angleRadians':
        return const AngleRadians();
      case 'rgbColor':
        return const RgbColor();
      case 'normalized':
        return const Normalized();
      case 'layerMask32':
        return const LayerMask32();
      case 'multiline':
        return const Multiline();
      case 'readOnly':
        return const ReadOnly();
      case 'pattern':
        return TextPattern(value is String ? value : '');
      case 'assetExtensions':
        return AssetExtensions([
          if (value is List)
            for (final extension in value)
              if (extension is String) extension,
        ]);
      case 'minCount':
        return MinCount((value as num?)?.toInt() ?? 0);
      case 'sortedDescending':
        return SortedDescending(value is String ? value : '');
      default:
        return UnknownConstraint(json);
    }
  }
}

/// A hard inclusive clamp on a numeric value; a null bound is open.
/// Inspector, clamped field. Coercion and realize clamp into range.
final class Range extends PropertyConstraint<num> {
  const Range(this.min, this.max);

  /// Shorthand for the common `Range(0, null)`.
  const Range.nonNegative() : min = 0, max = null;

  final double? min;
  final double? max;

  @override
  Map<String, Object?> toJson() => {
    'range': {if (min != null) 'min': min, if (max != null) 'max': max},
  };
}

/// The slider range for a numeric value, presentation only; values outside
/// it remain valid, unlike [Range].
final class SoftRange extends PropertyConstraint<num> {
  const SoftRange(this.min, this.max);

  final double min;
  final double max;

  @override
  Map<String, Object?> toJson() => {
    'softRange': {'min': min, 'max': max},
  };
}

/// A hard inclusive clamp on an integer value; a null bound is open.
/// Inspector, stepper or slider when both bounds are present.
final class IntRange extends PropertyConstraint<int> {
  const IntRange(this.min, this.max);

  final int? min;
  final int? max;

  @override
  Map<String, Object?> toJson() => {
    'intRange': {if (min != null) 'min': min, if (max != null) 'max': max},
  };
}

/// The scrub/step increment for a numeric field.
final class Step extends PropertyConstraint<num> {
  const Step(this.step);

  final double step;

  @override
  Map<String, Object?> toJson() => {'step': step};
}

/// An integer constrained to powers of two within [min]..[max] (shadow map
/// resolutions). Inspector, a dropdown of the powers in range.
final class PowerOfTwo extends PropertyConstraint<int> {
  const PowerOfTwo({this.min = 1, this.max});

  final int min;
  final int? max;

  @override
  Map<String, Object?> toJson() => {
    'powerOfTwo': {'min': min, if (max != null) 'max': max},
  };
}

/// A number stored in radians, displayed and edited in degrees.
final class AngleRadians extends PropertyConstraint<num> {
  const AngleRadians();

  @override
  Map<String, Object?> toJson() => const {'angleRadians': true};
}

/// A vec3 that carries a linear RGB color (light colors), edited with a
/// color picker while staying vector-encoded for document compatibility.
final class RgbColor extends PropertyConstraint<Object> {
  const RgbColor();

  @override
  Map<String, Object?> toJson() => const {'rgbColor': true};
}

/// A vector normalized on write (joint axes).
final class Normalized extends PropertyConstraint<Object> {
  const Normalized();

  @override
  Map<String, Object?> toJson() => const {'normalized': true};
}

/// A 32-bit bitmask (collision layers/masks, render layers). Inspector, a
/// bitmask editor.
final class LayerMask32 extends PropertyConstraint<int> {
  const LayerMask32();

  @override
  Map<String, Object?> toJson() => const {'layerMask32': true};
}

/// Written by a tool, not by hand: the inspector shows the value and offers
/// no editor for it.
///
/// For a property that is real document state -- so not transient -- but
/// whose value is derived: a payload token naming a baked blob, a cached
/// count, a checksum. Hand-editing one of those cannot produce anything
/// meaningful, and can silently break the thing it points at.
final class ReadOnly extends PropertyConstraint<Object?> {
  const ReadOnly();

  @override
  Map<String, Object?> toJson() => const {'readOnly': true};
}

/// A multi-line text field.
final class Multiline extends PropertyConstraint<String> {
  const Multiline();

  @override
  Map<String, Object?> toJson() => const {'multiline': true};
}

/// A soft-validated regular expression on a string (diagnostic, not a
/// rejection).
final class TextPattern extends PropertyConstraint<String> {
  const TextPattern(this.pattern);

  final String pattern;

  @override
  Map<String, Object?> toJson() => {'pattern': pattern};
}

/// Filters an asset picker to the given file extensions (with leading dots).
final class AssetExtensions extends PropertyConstraint<Object> {
  const AssetExtensions(this.extensions);

  final List<String> extensions;

  @override
  Map<String, Object?> toJson() => {'assetExtensions': extensions};
}

/// A list must hold at least [count] entries.
final class MinCount extends PropertyConstraint<List<Object?>> {
  const MinCount(this.count);

  final int count;

  @override
  Map<String, Object?> toJson() => {'minCount': count};
}

/// A list of objects must stay sorted by strictly descending [fieldName]
/// (LOD levels by screen size).
final class SortedDescending extends PropertyConstraint<List<Object?>> {
  const SortedDescending(this.fieldName);

  final String fieldName;

  @override
  Map<String, Object?> toJson() => {'sortedDescending': fieldName};
}

/// A constraint tag this build does not recognize, preserved verbatim so a
/// re-encode never drops newer metadata.
final class UnknownConstraint extends PropertyConstraint<Object?> {
  const UnknownConstraint(this.json);

  final Map<String, Object?> json;

  @override
  Map<String, Object?> toJson() => json;
}
