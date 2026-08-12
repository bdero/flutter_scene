/// Structural equality over [PropertyValue]s, used by delta serialization
/// (omit values equal to the schema default) and by tooling comparing specs.
library;

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/property_value.dart';

/// Whether [a] and [b] carry the same value, comparing structurally (vectors
/// by components, lists and maps element-wise, refs by id).
bool propertyValuesEqual(PropertyValue? a, PropertyValue? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return switch (a) {
    BoolValue(:final value) => b is BoolValue && b.value == value,
    IntValue(:final value) => b is IntValue && b.value == value,
    DoubleValue(:final value) => b is DoubleValue && b.value == value,
    StringValue(:final value) => b is StringValue && b.value == value,
    Vec2Value(:final value) => b is Vec2Value && _vec2(value, b.value),
    Vec3Value(:final value) => b is Vec3Value && _vec3(value, b.value),
    Vec4Value(:final value) => b is Vec4Value && _vec4(value, b.value),
    QuaternionValue(:final value) =>
      b is QuaternionValue && _quat(value, b.value),
    Matrix4Value(:final value) => b is Matrix4Value && _mat4(value, b.value),
    ColorValue() =>
      b is ColorValue && a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a,
    ResourceRefValue(:final id) => b is ResourceRefValue && b.id == id,
    NodeRefValue(:final id) => b is NodeRefValue && b.id == id,
    ListValue(:final values) => b is ListValue && _list(values, b.values),
    MapValue(:final values) => b is MapValue && _map(values, b.values),
  };
}

bool _vec2(Vector2 a, Vector2 b) => a.x == b.x && a.y == b.y;
bool _vec3(Vector3 a, Vector3 b) => a.x == b.x && a.y == b.y && a.z == b.z;
bool _vec4(Vector4 a, Vector4 b) =>
    a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
bool _quat(Quaternion a, Quaternion b) =>
    a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;

bool _mat4(Matrix4 a, Matrix4 b) {
  for (var i = 0; i < 16; i++) {
    if (a.storage[i] != b.storage[i]) return false;
  }
  return true;
}

bool _list(List<PropertyValue> a, List<PropertyValue> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!propertyValuesEqual(a[i], b[i])) return false;
  }
  return true;
}

bool _map(Map<String, PropertyValue> a, Map<String, PropertyValue> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !propertyValuesEqual(entry.value, other)) {
      return false;
    }
  }
  return true;
}
