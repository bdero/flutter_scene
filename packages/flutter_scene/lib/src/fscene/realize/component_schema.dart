import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';

/// The editable type of one component property, used by the inspector to pick a
/// widget, by tooling to validate input, and by the format to know how a value
/// is carried.
enum ComponentPropertyKind {
  /// A boolean ([BoolValue]).
  boolean,

  /// An integer ([IntValue]).
  integer,

  /// A floating-point number ([DoubleValue]).
  number,

  /// A string ([StringValue]); see [ComponentPropertyDef.options] for enums.
  string,

  /// A 2-component vector ([Vec2Value]).
  vec2,

  /// A 3-component vector ([Vec3Value]).
  vec3,

  /// A 4-component vector ([Vec4Value]).
  vec4,

  /// A rotation quaternion ([QuaternionValue]).
  quaternion,

  /// A linear RGBA color ([ColorValue]).
  color,

  /// A reference to a document resource ([ResourceRefValue]); see
  /// [ComponentPropertyDef.resourceKind].
  resourceRef,

  /// A reference to a document node ([NodeRefValue]).
  nodeRef,

  /// An ordered list ([ListValue]).
  list,

  /// A string-keyed map ([MapValue]).
  map,
}

/// A declared, editable property of a component type.
///
/// A component's [ComponentCodec.propertySchema] lists these in display order.
/// Each entry is the single description of one property: its [name] (the key in
/// the [ComponentSpec.properties] bag), its [kind], its [defaultValue] (also the
/// value used when the key is absent), and optional metadata for editors and
/// tooling. When [read] is given, the base [ComponentCodec.serialize] derives
/// the serialized value from a live component, so a codec never hand-writes
/// both a schema and a serializer for the same field.
class ComponentPropertyDef {
  /// Declares property [name] of [kind] with [defaultValue].
  const ComponentPropertyDef(
    this.name,
    this.kind,
    this.defaultValue, {
    this.doc,
    this.resourceKind,
    this.options,
    this.min,
    this.max,
    this.read,
  });

  /// The property key in the [ComponentSpec.properties] bag.
  final String name;

  /// The property's editable type.
  final ComponentPropertyKind kind;

  /// The value used when the property is absent from a spec, or null for a
  /// required property with no default (a mesh's geometry/material reference).
  final PropertyValue? defaultValue;

  /// A short human/agent-readable description of the property.
  final String? doc;

  /// For [ComponentPropertyKind.resourceRef], the kind of resource referenced
  /// (`geometry`, `material`, or `texture`), so an editor can filter the picker.
  final String? resourceKind;

  /// For [ComponentPropertyKind.string] enums, the allowed values.
  final List<String>? options;

  /// An optional inclusive lower bound for numeric kinds.
  final double? min;

  /// An optional inclusive upper bound for numeric kinds.
  final double? max;

  /// Reads this property's value from a live [component], used by the derived
  /// [ComponentCodec.serialize]. Null for codecs that serialize by hand.
  final PropertyValue Function(Component component)? read;
}
