import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// Context handed to a [ComponentCodec] when realizing a [ComponentSpec] into
/// a live [Component]. Carries the source [document] and a [resources]
/// realizer so a codec (for example a mesh) can resolve referenced geometry
/// and materials.
class RealizeContext {
  /// Creates a realize context over [document], optionally with a [resources]
  /// realizer.
  RealizeContext(this.document, {this.resources});

  /// The document being realized.
  final SceneDocument document;

  /// Realizes referenced geometry/material resources, or null when resource
  /// realization is unavailable (a codec needing it should return null).
  final ResourceRealizer? resources;
}

/// Context handed to a [ComponentCodec] when serializing a live [Component]
/// into a [ComponentSpec]. Carries the destination [document] so a codec can
/// register resources or mint ids.
class SerializeContext {
  /// Creates a serialize context over [document].
  SerializeContext(this.document);

  /// The document being written into.
  final SceneDocument document;

  /// Live hand-built resources already serialized into [document] this pass,
  /// keyed by instance, so a geometry or material shared by several nodes is
  /// emitted once and referenced everywhere.
  final Map<Object, LocalId> serializedResources = <Object, LocalId>{};
}

/// Translates between a serialized [ComponentSpec] and a live [Component] of
/// one type.
///
/// Codecs are registered in a [FsceneComponentRegistry]; the realizer and
/// serializer dispatch through it. This is the seam that lets the format
/// carry component types the core does not know about.
abstract class ComponentCodec {
  /// The serialized component type name this codec handles (for example
  /// `directionalLight`).
  String get type;

  /// The component's editable properties, in display order. Drives the
  /// inspector, agent discovery, default-filling on [realize], and the derived
  /// [serialize]. Empty for codecs that do not declare a schema.
  List<ComponentPropertyDef> get propertySchema => const [];

  /// Whether [component] is an instance this codec serializes. Used by the
  /// derived [serialize]; a codec that overrides [serialize] need not implement
  /// this.
  bool claims(Component component) => false;

  /// Builds a live component from [spec], or returns null when it cannot be
  /// realized in the given context (for example a mesh with no resource
  /// realizer).
  Component? realize(ComponentSpec spec, RealizeContext context);

  /// Serializes [component] to a [ComponentSpec], or returns null if this codec
  /// does not handle that component instance.
  ///
  /// The default implementation derives the spec from [propertySchema]: when
  /// [claims] accepts the component, each property's value is read through its
  /// [ComponentPropertyDef.read]. Codecs whose serialization is not a flat
  /// field read (a mesh recovering resource ids) override this.
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (!claims(component)) return null;
    return ComponentSpec(
      type,
      properties: {
        for (final def in propertySchema) def.name: def.read!(component),
      },
    );
  }

  /// The declared default for property [name], or null when the property has no
  /// default (throws when [name] is undeclared).
  PropertyValue? defaultOf(String name) =>
      propertySchema.firstWhere((d) => d.name == name).defaultValue;

  /// The declared default for a [ComponentPropertyKind.number] (or integer)
  /// property [name], as a double.
  double numberDefault(String name) {
    final v = defaultOf(name);
    return v is IntValue ? v.value.toDouble() : (v as DoubleValue).value;
  }

  /// The declared default for an [ComponentPropertyKind.integer] property.
  int intDefault(String name) => (defaultOf(name) as IntValue).value;

  /// The declared default for a [ComponentPropertyKind.boolean] property.
  bool boolDefault(String name) => (defaultOf(name) as BoolValue).value;

  /// The declared default for a [ComponentPropertyKind.vec3] property (cloned).
  Vector3 vec3Default(String name) =>
      (defaultOf(name) as Vec3Value).value.clone();

  /// The declared default for a [ComponentPropertyKind.string] property.
  String stringDefault(String name) => (defaultOf(name) as StringValue).value;
}

/// A registry of [ComponentCodec]s, keyed by component type name.
///
/// Realization looks a codec up by [ComponentSpec.type]; serialization tries
/// each codec until one claims the component. Unknown components are skipped
/// (with the caller deciding how to report it) rather than failing the load.
class FsceneComponentRegistry {
  final Map<String, ComponentCodec> _byType = {};

  /// Registers [codec], replacing any existing codec for its type.
  void register(ComponentCodec codec) => _byType[codec.type] = codec;

  /// The registered component type names, in registration order.
  Iterable<String> get types => _byType.keys;

  /// The codec for [type], or null when none is registered.
  ComponentCodec? codecFor(String type) => _byType[type];

  /// Realizes [spec] into a live component, or returns null when no codec is
  /// registered for its type.
  Component? realize(ComponentSpec spec, RealizeContext context) =>
      _byType[spec.type]?.realize(spec, context);

  /// Serializes [component] using the first codec that claims it, or returns
  /// null when none does.
  ComponentSpec? serialize(Component component, SerializeContext context) {
    for (final codec in _byType.values) {
      final spec = codec.serialize(component, context);
      if (spec != null) return spec;
    }
    return null;
  }
}
