import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/node.dart';

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

  /// Resolves a document node id to its realized [Node]. Set by the realizer
  /// once its node map exists; null in contexts without one.
  Node? Function(LocalId id)? resolveNode;

  /// Callbacks the realizer runs after every node and component has been
  /// realized. A codec whose spec references other nodes' components (for
  /// example material variants binding into mesh primitives) registers its
  /// resolution here rather than resolving during its own realize call,
  /// when those components may not exist yet.
  final List<void Function()> afterRealize = [];

  /// Runs and clears [afterRealize]. The realizer calls this once per pass.
  void runAfterRealize() {
    for (final callback in afterRealize) {
      callback();
    }
    afterRealize.clear();
  }
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

/// The property every component carries regardless of type: the base
/// [Component.enabled] flag, applied and serialized by the registry so
/// individual codecs never re-declare it.
const List<ComponentPropertyDef> universalComponentProperties = [
  ComponentPropertyDef(
    'enabled',
    ComponentPropertyKind.boolean,
    defaultValue: BoolValue(true),
    doc: 'Whether this component updates.',
  ),
];

/// Translates between a serialized [ComponentSpec] and a live [Component] of
/// one type.
///
/// Codecs are registered in a [FsceneComponentRegistry]; the realizer and
/// serializer dispatch through it. This is the seam that lets the format
/// carry component types the core does not know about. Flat components are
/// better served by `DeclarativeComponentCodec`, which derives the schema,
/// realization, and delta serialization from one field list.
abstract class ComponentCodec {
  /// The serialized component type name this codec handles (for example
  /// `directionalLight`).
  String get type;

  /// The group an editor files this type under in its component picker
  /// ("Rendering", "Physics"). Null files it under the catch-all, which is
  /// where a project's own components land until they say otherwise.
  ///
  /// Declared here rather than only inside [schema] so a codec can be filed
  /// without having to restate its whole schema.
  String? get category => null;

  /// The component's full portable schema. The default wraps [type],
  /// [category] and [propertySchema]; override to add docs, an icon, or
  /// former type names.
  ComponentSchema get schema =>
      ComponentSchema(type, category: category, properties: propertySchema);

  /// The exact component runtime type this codec serializes, used for O(1)
  /// serialization dispatch. [Component] (the default) means "unknown, fall
  /// back to scanning [claims]".
  Type get componentType => Component;

  /// The component's editable properties, in display order. Drives the
  /// inspector, agent discovery, and default-filling on [realize]. Empty for
  /// codecs that do not declare a schema.
  List<ComponentPropertyDef> get propertySchema => const [];

  /// Whether [component] is an instance this codec serializes.
  bool claims(Component component) => false;

  /// Writes one declared property straight onto a live component, for editor
  /// previews during a slider drag. Returns false when this codec does not
  /// own [component] or the property has no live write binding.
  bool writeLiveProperty(
    Component component,
    String name,
    PropertyValue value,
    RealizeContext context,
  ) => false;

  /// Builds a live component from [spec], or returns null when it cannot be
  /// realized in the given context (for example a mesh with no resource
  /// realizer).
  Component? realize(ComponentSpec spec, RealizeContext context);

  /// Serializes [component] to a [ComponentSpec], or returns null if this
  /// codec does not handle that component instance.
  ///
  /// The returned spec must be freshly built (or a copy); the registry
  /// adjusts its properties in place, so a spec aliased by the live
  /// component (a retained placeholder spec) would see snapshots change
  /// retroactively.
  ComponentSpec? serialize(Component component, SerializeContext context);

  /// The declared default for property [name], or null when the property has no
  /// default (throws when [name] is undeclared).
  /// Writes one declared property onto a live [component], returning whether
  /// it landed.
  ///
  /// Realizing a component builds it from a whole spec; this changes one
  /// property on one that already exists, which is what a live edit is — an
  /// inspector drag, a value arriving over the network, a graph assigning to
  /// a field. Codecs that build their component wholesale have nothing to
  /// offer here and answer false.
  bool applyProperty(
    Component component,
    String name,
    PropertyValue value,
    RealizeContext context,
  ) => false;

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
/// Realization looks a codec up by [ComponentSpec.type] (accepting schema
/// former type names); serialization dispatches by the component's runtime
/// type, falling back to a [ComponentCodec.claims] scan for codecs that do
/// not declare one. Unknown components are skipped (with the caller deciding
/// how to report it) rather than failing the load. The registry applies the
/// [universalComponentProperties] (`enabled`) around every codec.
class FsceneComponentRegistry {
  final Map<String, ComponentCodec> _byType = {};
  final Map<Type, ComponentCodec> _byComponentType = {};

  /// Registers [codec], replacing any existing codec for its type.
  void register(ComponentCodec codec) {
    final previous = _byType[codec.type];
    if (previous != null &&
        identical(_byComponentType[previous.componentType], previous)) {
      _byComponentType.remove(previous.componentType);
    }
    _byType[codec.type] = codec;
    if (codec.componentType != Component) {
      _byComponentType[codec.componentType] = codec;
    }
  }

  /// Removes the codec registered for [type], returning it (null when
  /// absent). Documents carrying the type afterwards realize it as a
  /// lossless foreign placeholder, the same as any unknown type.
  ComponentCodec? unregister(String type) {
    final removed = _byType.remove(type);
    if (removed != null &&
        identical(_byComponentType[removed.componentType], removed)) {
      _byComponentType.remove(removed.componentType);
    }
    return removed;
  }

  /// The registered component type names, in registration order.
  Iterable<String> get types => _byType.keys;

  /// The registered component schemas, in registration order.
  Iterable<ComponentSchema> get schemas =>
      _byType.values.map((codec) => codec.schema);

  /// The codec for [type], accepting schemas' former type names.
  ComponentCodec? codecFor(String type) {
    final direct = _byType[type];
    if (direct != null) return direct;
    for (final codec in _byType.values) {
      if (codec.schema.formerTypes.contains(type)) return codec;
    }
    return null;
  }

  /// Realizes [spec] into a live component, or returns null when no codec is
  /// registered for its type.
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final component = codecFor(spec.type)?.realize(spec, context);
    if (component != null) {
      final enabled = spec.properties['enabled'];
      if (enabled is BoolValue) component.enabled = enabled.value;
    }
    return component;
  }

  /// Serializes [component], dispatching by its runtime type and falling
  /// back to the first codec that claims it. Returns null when none does.
  ComponentSpec? serialize(Component component, SerializeContext context) {
    final spec =
        _byComponentType[component.runtimeType]?.serialize(
          component,
          context,
        ) ??
        _serializeByScan(component, context);
    if (spec != null) {
      if (component.enabled) {
        // Retained specs (placeholders, deferred loads) can carry a stale
        // authored value; live state wins.
        spec.properties.remove('enabled');
      } else {
        spec.properties['enabled'] = const BoolValue(false);
      }
    }
    return spec;
  }

  ComponentSpec? _serializeByScan(
    Component component,
    SerializeContext context,
  ) {
    for (final codec in _byType.values) {
      final spec = codec.serialize(component, context);
      if (spec != null) return spec;
    }
    return null;
  }
}
