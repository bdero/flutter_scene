/// The component schema descriptor model, pure data describing a component
/// type's editable properties (kinds, defaults, constraints, docs).
///
/// Descriptors are deliberately closure-free and JSON-round-trippable so a
/// schema can leave the process that authored it, an editor renders
/// inspectors for component types it was never compiled with, agents get the
/// same description over MCP, and packages ship schemas in a manifest.
/// Runtime bindings (how a property reads from and writes to a live
/// component) live with the component codecs, not here.
library;

import 'package:scene/src/json/property_json.dart';
import 'package:scene/src/property_value.dart';
import 'package:scene/src/schema/gizmo_spec.dart';
import 'package:scene/src/schema/property_constraints.dart';

/// The editable type of one component property, used by the inspector to
/// pick a widget, by tooling to validate input, and by the format to know
/// how a value is carried.
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

  /// A 4x4 matrix ([Matrix4Value]).
  matrix4,

  /// A linear RGBA color ([ColorValue]).
  color,

  /// A reference to a document resource ([ResourceRefValue]); see
  /// [ComponentPropertyDef.resourceKind].
  resourceRef,

  /// A reference to a document node ([NodeRefValue]).
  nodeRef,

  /// A source-path asset reference, carried as a [StringValue] key; see
  /// [AssetExtensions] for picker filtering.
  assetRef,

  /// An ordered list ([ListValue]); [ComponentPropertyDef.itemDef] describes
  /// the entries when they are homogeneous.
  list,

  /// An open string-keyed map ([MapValue]) with undeclared keys.
  map,

  /// A closed nested object, carried as a [MapValue] whose keys are declared
  /// by [ComponentPropertyDef.objectFields].
  object,

  /// A tagged union, carried as a [MapValue] holding a
  /// [ComponentPropertyDef.unionTag] string plus the selected variant's
  /// fields ([ComponentPropertyDef.unionVariants]).
  union,

  /// A scalar value generator (constant, random range, or curve-over-life),
  /// carried as a tagged [MapValue]. See the particle distribution helpers.
  distribution,

  /// A keyframed scalar curve over normalized time, carried as a [MapValue]
  /// holding its control points.
  curve,

  /// A keyframed RGBA color gradient over normalized time, carried as a
  /// [MapValue] holding its color stops.
  gradient,
}

/// A declared, editable property of a component type: the single source of
/// truth for its name, carried kind, default, constraints, and docs.
class ComponentPropertyDef {
  /// Declares property [name] of [kind].
  const ComponentPropertyDef(
    this.name,
    this.kind, {
    this.defaultValue,
    this.doc,
    this.group,
    this.resourceKind,
    this.options,
    this.constraints = const [],
    this.formerNames = const [],
    this.transient = false,
    this.itemDef,
    this.objectFields,
    this.unionTag = 'kind',
    this.unionVariants,
  });

  /// The property key in the component spec's properties bag.
  final String name;

  /// The property's editable type.
  final ComponentPropertyKind kind;

  /// The value used when the property is absent from a spec, or null for a
  /// required property with no default (a mesh's geometry reference).
  final PropertyValue? defaultValue;

  /// A short human/agent-readable description, rendered as a tooltip.
  final String? doc;

  /// The collapsible inspector section this property belongs to.
  final String? group;

  /// For [ComponentPropertyKind.resourceRef], the referenced resource kind
  /// (`geometry`, `material`, `texture`, `environment`), so an editor can
  /// filter the picker.
  final String? resourceKind;

  /// For [ComponentPropertyKind.string] enums, the allowed values.
  final List<String>? options;

  /// Declared value constraints; see [PropertyConstraint].
  final List<PropertyConstraint<Object?>> constraints;

  /// Prior names of this property, accepted when loading older documents.
  final List<String> formerNames;

  /// Schema-visible but never persisted (runtime state, or code-provided).
  final bool transient;

  /// For [ComponentPropertyKind.list], the entry descriptor (name unused).
  final ComponentPropertyDef? itemDef;

  /// For [ComponentPropertyKind.object], the nested field descriptors.
  final List<ComponentPropertyDef>? objectFields;

  /// For [ComponentPropertyKind.union], the map key holding the variant tag.
  final String unionTag;

  /// For [ComponentPropertyKind.union], the field descriptors per variant.
  final Map<String, List<ComponentPropertyDef>>? unionVariants;

  /// The first constraint of type [C], or null.
  C? constraint<C extends PropertyConstraint<Object?>>() {
    for (final candidate in constraints) {
      if (candidate is C) return candidate;
    }
    return null;
  }

  /// The hard inclusive lower bound, from [Range]/[IntRange], or null.
  double? get hardMin =>
      constraint<Range>()?.min ?? constraint<IntRange>()?.min?.toDouble();

  /// The hard inclusive upper bound, from [Range]/[IntRange], or null.
  double? get hardMax =>
      constraint<Range>()?.max ?? constraint<IntRange>()?.max?.toDouble();

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    if (defaultValue != null)
      'default': encodePropertyValue(defaultValue!, (id) => id.toToken()),
    if (doc != null) 'doc': doc,
    if (group != null) 'group': group,
    if (resourceKind != null) 'resourceKind': resourceKind,
    if (options != null) 'options': options,
    if (constraints.isNotEmpty)
      'constraints': [
        for (final constraint in constraints) constraint.toJson(),
      ],
    if (formerNames.isNotEmpty) 'formerNames': formerNames,
    if (transient) 'transient': true,
    if (itemDef != null) 'item': itemDef!.toJson(),
    if (objectFields != null)
      'fields': [for (final field in objectFields!) field.toJson()],
    if (unionVariants != null) ...{
      if (unionTag != 'kind') 'unionTag': unionTag,
      'variants': {
        for (final entry in unionVariants!.entries)
          entry.key: [for (final field in entry.value) field.toJson()],
      },
    },
  };

  static ComponentPropertyDef fromJson(Map<String, Object?> json) {
    final kindName = json['kind'];
    final kind = ComponentPropertyKind.values.asNameMap()[kindName];
    if (json['name'] is! String || kind == null) {
      throw FormatException('Malformed property descriptor: $json');
    }
    return ComponentPropertyDef(
      json['name'] as String,
      kind,
      defaultValue: json['default'] == null
          ? null
          : decodePropertyValue(json['default']),
      doc: json['doc'] as String?,
      group: json['group'] as String?,
      resourceKind: json['resourceKind'] as String?,
      // Materialize eagerly; a lazy cast view defers its element TypeError
      // to whoever iterates it (the inspector, at render time).
      options: json['options'] is List
          ? [for (final option in json['options'] as List) option as String]
          : null,
      constraints: [
        if (json['constraints'] is List)
          for (final entry in json['constraints'] as List)
            if (entry is Map)
              PropertyConstraint.fromJson(entry.cast<String, Object?>()),
      ],
      formerNames: json['formerNames'] is List
          ? [for (final name in json['formerNames'] as List) name as String]
          : const [],
      transient: json['transient'] == true,
      itemDef: json['item'] is Map
          ? fromJson((json['item'] as Map).cast<String, Object?>())
          : null,
      objectFields: json['fields'] is List
          ? [
              for (final entry in json['fields'] as List)
                if (entry is Map) fromJson(entry.cast<String, Object?>()),
            ]
          : null,
      unionTag: json['unionTag'] as String? ?? 'kind',
      unionVariants: json['variants'] is Map
          ? {
              for (final entry in (json['variants'] as Map).entries)
                entry.key as String: [
                  if (entry.value is List)
                    for (final field in entry.value as List)
                      if (field is Map) fromJson(field.cast<String, Object?>()),
                ],
            }
          : null,
    );
  }
}

/// A component type's full schema, the unit that travels (dev channel,
/// project cache, package manifests, MCP).
class ComponentSchema {
  const ComponentSchema(
    this.type, {
    this.doc,
    this.icon,
    this.category,
    this.version = 1,
    this.formerTypes = const [],
    this.properties = const [],
    this.gizmo,
  });

  /// The component type tag used in documents.
  final String type;

  /// A short description of the component.
  final String? doc;

  /// An optional editor icon hint (an emoji or a named glyph).
  final String? icon;

  /// The group this type is filed under in an editor's component picker
  /// ("Rendering", "Physics", "Cameras"). Null files it under a catch-all,
  /// which is where a project's own components land until they say otherwise.
  final String? category;

  /// The schema revision, for future migrations.
  final int version;

  /// Prior type tags, accepted when loading older documents.
  final List<String> formerTypes;

  /// The declared properties, in display order.
  final List<ComponentPropertyDef> properties;

  /// The optional editor gizmo block; see [GizmoSpec].
  final GizmoSpec? gizmo;

  /// The descriptor for [name], accepting [ComponentPropertyDef.formerNames].
  ComponentPropertyDef? property(String name) {
    for (final def in properties) {
      if (def.name == name || def.formerNames.contains(name)) return def;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'type': type,
    if (doc != null) 'doc': doc,
    if (icon != null) 'icon': icon,
    if (category != null) 'category': category,
    if (version != 1) 'version': version,
    if (formerTypes.isNotEmpty) 'formerTypes': formerTypes,
    'properties': [for (final def in properties) def.toJson()],
    if (gizmo != null) 'gizmo': gizmo!.toJson(),
  };

  static ComponentSchema fromJson(Map<String, Object?> json) {
    if (json['type'] is! String) {
      throw FormatException('Malformed component schema: $json');
    }
    return ComponentSchema(
      json['type'] as String,
      doc: json['doc'] as String?,
      icon: json['icon'] as String?,
      category: json['category'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
      formerTypes: json['formerTypes'] is List
          ? [for (final type in json['formerTypes'] as List) type as String]
          : const [],
      properties: [
        if (json['properties'] is List)
          for (final entry in json['properties'] as List)
            if (entry is Map)
              ComponentPropertyDef.fromJson(entry.cast<String, Object?>()),
      ],
      gizmo: GizmoSpec.fromJson(json['gizmo']),
    );
  }
}

/// Encodes a schema list (a manifest or cache payload).
List<Object?> encodeComponentSchemas(Iterable<ComponentSchema> schemas) => [
  for (final schema in schemas) schema.toJson(),
];

/// Decodes a schema list, skipping malformed entries.
List<ComponentSchema> decodeComponentSchemas(Object? json) {
  final schemas = <ComponentSchema>[];
  if (json is! List) return schemas;
  for (final entry in json) {
    if (entry is! Map) continue;
    try {
      schemas.add(ComponentSchema.fromJson(entry.cast<String, Object?>()));
    } on FormatException {
      // A malformed entry (or a future format) never breaks the readable
      // ones; schema lists come from caches and manifests of varying age.
    } on TypeError {
      // Same skip for shape mismatches fromJson's casts surface (a string
      // where a map was expected, a non-string list element).
    }
  }
  return schemas;
}
