/// Const annotations that mark component classes and fields for the
/// `flutter_scene_codegen` extractor, which lowers them to portable
/// `ComponentSchema` descriptors and generated codecs.
///
/// The extractor is syntax-only, so annotation arguments must be literals
/// (numbers, strings, bools, list literals, and const constraint
/// constructors from `package:scene/schema.dart`).
library;

import 'package:scene/schema.dart';

/// Marks a class extending `Component` as a serializable scene component
/// carrying document type tag [type].
/// {@category Scene graph}
class SceneComponent {
  const SceneComponent(
    this.type, {
    this.doc,
    this.icon,
    this.category,
    this.formerTypes = const [],
  });

  /// The component type tag used in documents.
  final String type;

  /// A short description shown in editors; the class doc comment when null.
  final String? doc;

  /// An optional editor icon hint (an emoji or a named glyph).
  final String? icon;

  /// The group this component is filed under in the editor's component
  /// picker. Null files it under "Scripts", with the rest of the project's
  /// own components.
  final String? category;

  /// Prior type tags, accepted when loading older documents.
  final List<String> formerTypes;
}

/// Attaches a declarative editor gizmo to a `@SceneComponent` class: the
/// ordered [primitives] the editor draws in its viewport for components of
/// this type. Primitives must be const constructors from
/// `package:scene/schema.dart` ([GizmoIcon], [GizmoArrow], wire shapes...),
/// with scalar and color parameters either literal or bound to a property by
/// dotted path ([GizmoScalar.bind], [GizmoColor.bind]).
/// {@category Scene graph}
class SceneGizmo {
  const SceneGizmo(this.primitives);

  /// The gizmo's primitives, in draw order.
  final List<GizmoPrimitive> primitives;
}

/// Marks a field as an editable component property.
///
/// The bare form derives the property kind from the field's declared type;
/// the typed variants pin the kind and add kind-appropriate options.
/// {@category Scene graph}
class SceneProperty {
  const SceneProperty({
    this.group,
    this.formerNames = const [],
    this.transient = false,
  });

  /// The collapsible inspector section this property belongs to.
  final String? group;

  /// Prior names of this property, accepted when loading older documents.
  final List<String> formerNames;

  /// Schema-visible but never persisted (runtime state, or code-provided).
  final bool transient;
}

/// A boolean property.
/// {@category Scene graph}
class BoolProperty extends SceneProperty {
  const BoolProperty({
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<bool>> extra;
}

/// An integer property. [min] and [max] lower to an [IntRange].
/// {@category Scene graph}
class IntProperty extends SceneProperty {
  const IntProperty({
    this.min,
    this.max,
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// The hard inclusive lower bound.
  final int? min;

  /// The hard inclusive upper bound.
  final int? max;

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<int>> extra;
}

/// A floating-point property. [min]/[max] lower to a [Range],
/// [softMin]/[softMax] to a [SoftRange], and [step] to a [Step].
/// {@category Scene graph}
class NumberProperty extends SceneProperty {
  const NumberProperty({
    this.min,
    this.max,
    this.softMin,
    this.softMax,
    this.step,
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// The hard inclusive lower bound.
  final double? min;

  /// The hard inclusive upper bound.
  final double? max;

  /// The slider lower bound (presentation only).
  final double? softMin;

  /// The slider upper bound (presentation only).
  final double? softMax;

  /// The scrub/step increment.
  final double? step;

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<num>> extra;
}

/// A string property. [multiline] lowers to a [Multiline] constraint and
/// [pattern] to a [TextPattern].
/// {@category Scene graph}
class StringProperty extends SceneProperty {
  const StringProperty({
    this.multiline = false,
    this.pattern,
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Edit with a multi-line text field.
  final bool multiline;

  /// A soft-validated regular expression.
  final String? pattern;

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<String>> extra;
}

/// An enum property, carried as the value name string with the enum's
/// values as options.
/// {@category Scene graph}
class EnumProperty extends SceneProperty {
  const EnumProperty({
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<String>> extra;
}

/// A 2-component vector property.
/// {@category Scene graph}
class Vec2Property extends SceneProperty {
  const Vec2Property({
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// A 3-component vector property. [rgbColor] lowers to an [RgbColor]
/// constraint and [normalized] to a [Normalized].
/// {@category Scene graph}
class Vec3Property extends SceneProperty {
  const Vec3Property({
    this.rgbColor = false,
    this.normalized = false,
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Edit as a linear RGB color while staying vector-encoded.
  final bool rgbColor;

  /// Normalize the vector on write.
  final bool normalized;

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// A 4-component vector property.
/// {@category Scene graph}
class Vec4Property extends SceneProperty {
  const Vec4Property({
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// A rotation quaternion property.
/// {@category Scene graph}
class QuaternionProperty extends SceneProperty {
  const QuaternionProperty({
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// An RGBA color property.
/// {@category Scene graph}
class ColorProperty extends SceneProperty {
  const ColorProperty({
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// A source-path asset reference property, carried as the asset key string.
/// [extensions] lowers to an [AssetExtensions] constraint.
/// {@category Scene graph}
class AssetProperty extends SceneProperty {
  const AssetProperty({
    this.extensions = const [],
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Picker file extensions (with leading dots).
  final List<String> extensions;

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// A document resource reference property (`geometry`, `material`,
/// `texture`, `environment`).
/// {@category Scene graph}
class ResourceProperty extends SceneProperty {
  const ResourceProperty({
    required this.resourceKind,
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// The referenced resource kind, so an editor can filter the picker.
  final String resourceKind;

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// A document node reference property.
/// {@category Scene graph}
class NodeProperty extends SceneProperty {
  const NodeProperty({
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<Object>> extra;
}

/// A number stored in radians and edited in degrees, lowering to an
/// [AngleRadians] constraint plus a [Range] when [min] or [max] is given.
/// {@category Scene graph}
class AngleProperty extends SceneProperty {
  const AngleProperty({
    this.min,
    this.max,
    super.group,
    super.formerNames,
    super.transient,
    this.extra = const [],
  });

  /// The hard inclusive lower bound, in radians.
  final double? min;

  /// The hard inclusive upper bound, in radians.
  final double? max;

  /// Additional declared constraints beyond the named arguments.
  final List<PropertyConstraint<num>> extra;
}
