/// Reading typed values out of a decoded property map.
///
/// A [MapValue] is how the document carries anything with internal structure —
/// a tagged union's variant, a nested object, one entry of a list — and every
/// codec that has one ends up needing the same five readers: a number that
/// accepts an int, an int that accepts a number, a bool, a string, a vector,
/// each with a fallback for absent or wrong-typed entries.
///
/// The fallback is the point. A document can be older than the code reading it,
/// hand-edited, or written by a tool that got a type wrong, and none of those
/// should be a crash: the reader takes what it understands and leaves the rest
/// at its default.
library;

import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Typed reads with fallbacks, over the `values` of a [MapValue].
extension PropertyMapRead on Map<String, PropertyValue> {
  /// The number at [key], accepting an int, or [fallback].
  double numberAt(String key, double fallback) => switch (this[key]) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => fallback,
  };

  /// The integer at [key], rounding a number, or [fallback].
  int intAt(String key, int fallback) => switch (this[key]) {
    IntValue(value: final v) => v,
    DoubleValue(value: final v) => v.round(),
    _ => fallback,
  };

  /// The bool at [key], or [fallback].
  bool boolAt(String key, bool fallback) => switch (this[key]) {
    BoolValue(value: final v) => v,
    _ => fallback,
  };

  /// The string at [key], or [fallback].
  String stringAt(String key, String fallback) => switch (this[key]) {
    StringValue(value: final v) => v,
    _ => fallback,
  };

  /// A copy of the vector at [key], or [fallback].
  ///
  /// A copy because the caller almost always stores it on a live component,
  /// and handing out the document's own vector makes edits to that component
  /// mutate the document behind the editor's back.
  Vector3 vec3At(String key, Vector3 fallback) => switch (this[key]) {
    Vec3Value(value: final v) => v.clone(),
    _ => fallback,
  };

  /// A copy of the quaternion at [key] (carried as xyzw), normalized, or
  /// [fallback].
  Quaternion quaternionAt(String key, Quaternion fallback) =>
      switch (this[key]) {
        Vec4Value(value: final v) when v.length2 > 1e-12 => Quaternion(
          v.x,
          v.y,
          v.z,
          v.w,
        )..normalize(),
        _ => fallback,
      };
}

/// The values of [value] when it is a [MapValue], else an empty map.
///
/// The entry point for decoding a union or object property: one call that
/// turns "whatever the document had here" into something the readers above
/// can be used on unconditionally.
Map<String, PropertyValue> propertyMapOf(PropertyValue? value) =>
    value is MapValue ? value.values : const <String, PropertyValue>{};
