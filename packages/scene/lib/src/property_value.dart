import 'package:vector_math/vector_math.dart';

import 'package:scene/src/id.dart';

/// A reference to an external asset by its source-path key.
///
/// The path is the same stable key the build hook and the hot-reload
/// coordinator use (for example `assets/dash.glb` or `assets/toon.fmat`),
/// resolved at load time. Wrapping it gives the format a single seam to
/// later swap filesystem paths for content-addressed or uid-backed
/// resolution.
class AssetRef {
  /// References the asset at the given source-path [key].
  const AssetRef(this.key);

  /// The source-path key, relative to the owning package's root.
  final String key;

  @override
  bool operator ==(Object other) => other is AssetRef && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'AssetRef($key)';
}

/// A typed value carried by a component field, a material parameter, or a
/// prefab override.
///
/// The taxonomy is closed (a `sealed` hierarchy) so encoders, the component
/// codec registry, and the prefab composer can exhaustively switch over it.
/// References to other document entities are first-class:
/// [ResourceRefValue] points at a resource, [NodeRefValue] at a node.
sealed class PropertyValue {
  const PropertyValue();
}

/// A boolean value.
class BoolValue extends PropertyValue {
  const BoolValue(this.value);
  final bool value;
}

/// An integer value.
class IntValue extends PropertyValue {
  const IntValue(this.value);
  final int value;
}

/// A floating-point scalar value.
class DoubleValue extends PropertyValue {
  const DoubleValue(this.value);
  final double value;
}

/// A string value.
class StringValue extends PropertyValue {
  const StringValue(this.value);
  final String value;
}

/// A 2-component vector.
class Vec2Value extends PropertyValue {
  Vec2Value(this.value);
  final Vector2 value;
}

/// A 3-component vector.
class Vec3Value extends PropertyValue {
  Vec3Value(this.value);
  final Vector3 value;
}

/// A 4-component vector.
class Vec4Value extends PropertyValue {
  Vec4Value(this.value);
  final Vector4 value;
}

/// A rotation quaternion (`x, y, z, w`).
class QuaternionValue extends PropertyValue {
  QuaternionValue(this.value);
  final Quaternion value;
}

/// A 4x4 matrix.
class Matrix4Value extends PropertyValue {
  Matrix4Value(this.value);
  final Matrix4 value;
}

/// A linear RGBA color.
class ColorValue extends PropertyValue {
  const ColorValue(this.r, this.g, this.b, this.a);
  final double r;
  final double g;
  final double b;
  final double a;
}

/// A reference to a resource (geometry, material, texture, ...) in the same
/// document, by its [LocalId].
class ResourceRefValue extends PropertyValue {
  const ResourceRefValue(this.id);
  final LocalId id;
}

/// A reference to another node in the same document, by its [LocalId].
class NodeRefValue extends PropertyValue {
  const NodeRefValue(this.id);
  final LocalId id;
}

/// An ordered list of values.
class ListValue extends PropertyValue {
  ListValue(this.values);
  final List<PropertyValue> values;
}

/// A string-keyed map of values (a nested property bag).
class MapValue extends PropertyValue {
  MapValue(this.values);
  final Map<String, PropertyValue> values;
}
