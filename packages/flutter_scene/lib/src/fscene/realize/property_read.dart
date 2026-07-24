import 'package:vector_math/vector_math.dart';

import 'package:scene/scene.dart';

/// Typed readers over a component or material property bag, with fallbacks
/// for missing or mistyped values. Shared by component codecs and the
/// resource realizer.

/// Reads a `double` property, accepting an int too, or returns [fallback].
double readDouble(
  Map<String, PropertyValue> props,
  String key,
  double fallback,
) {
  final v = props[key];
  return switch (v) {
    DoubleValue(:final value) => value,
    IntValue(:final value) => value.toDouble(),
    _ => fallback,
  };
}

/// Reads an `int` property, or returns [fallback].
int readInt(Map<String, PropertyValue> props, String key, int fallback) {
  final v = props[key];
  return v is IntValue ? v.value : fallback;
}

/// Reads a `bool` property, or returns [fallback].
bool readBool(Map<String, PropertyValue> props, String key, bool fallback) {
  final v = props[key];
  return v is BoolValue ? v.value : fallback;
}

/// Reads a [Vector3] property (a copy), or returns a copy of [fallback].
Vector3 readVec3(
  Map<String, PropertyValue> props,
  String key,
  Vector3 fallback,
) {
  final v = props[key];
  return v is Vec3Value ? v.value.clone() : fallback.clone();
}

/// Reads a [ColorValue] as a [Vector4] (RGBA), or returns [fallback].
Vector4? readColor(Map<String, PropertyValue> props, String key) {
  final v = props[key];
  return v is ColorValue ? Vector4(v.r, v.g, v.b, v.a) : null;
}

/// Reads a string property, or returns [fallback].
String readString(
  Map<String, PropertyValue> props,
  String key,
  String fallback,
) {
  final v = props[key];
  return v is StringValue ? v.value : fallback;
}
