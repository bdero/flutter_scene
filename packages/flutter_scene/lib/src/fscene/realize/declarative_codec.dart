/// The declarative component codec: one field declaration per property
/// drives the schema, realization, and delta serialization, replacing the
/// hand-written triplication (schema entry + realize read + serialize read)
/// flat codecs used to carry.
library;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';

/// One declared property, the const descriptor plus the runtime bindings
/// that connect it to a live component. The descriptor travels (schemas,
/// manifests, MCP); the bindings stay in-process.
/// {@category Assets and loading}
final class ComponentField<C extends Component> {
  const ComponentField(this.def, {this.read, this.write});

  /// The portable descriptor (name, kind, default, constraints, docs).
  final ComponentPropertyDef def;

  /// Reads the property from a live component, or null for a property that
  /// only flows through [DeclarativeComponentCodec.create] (constructor-only
  /// configuration) or is provided by code.
  final PropertyValue? Function(C component, SerializeContext context)? read;

  /// Applies the property to a live component after [create], or null for
  /// constructor-only configuration.
  final void Function(C component, PropertyValue value, RealizeContext context)?
  write;

  /// A boolean property.
  static ComponentField<C> boolean<C extends Component>(
    String name, {
    required bool defaultValue,
    bool Function(C component)? get,
    void Function(C component, bool value)? set,
    String? doc,
    String? group,
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.boolean,
      defaultValue: BoolValue(defaultValue),
      doc: doc,
      group: group,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => BoolValue(get(c)),
    write: set == null
        ? null
        : (c, v, _) {
            if (v is BoolValue) set(c, v.value);
          },
  );

  /// An integer property.
  static ComponentField<C> integer<C extends Component>(
    String name, {
    required int defaultValue,
    int Function(C component)? get,
    void Function(C component, int value)? set,
    String? doc,
    String? group,
    List<PropertyConstraint<int>> constraints = const [],
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.integer,
      defaultValue: IntValue(defaultValue),
      doc: doc,
      group: group,
      constraints: constraints,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => IntValue(get(c)),
    // Authored values apply verbatim; constraints describe the editing UI
    // (the editor clamps on edit) and must not mutate legal documents on a
    // load/save round trip.
    write: set == null
        ? null
        : (c, v, _) {
            if (v is IntValue) set(c, v.value);
          },
  );

  /// A floating-point property.
  static ComponentField<C> number<C extends Component>(
    String name, {
    required double defaultValue,
    double Function(C component)? get,
    void Function(C component, double value)? set,
    String? doc,
    String? group,
    List<PropertyConstraint<num>> constraints = const [],
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(defaultValue),
      doc: doc,
      group: group,
      constraints: constraints,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => DoubleValue(get(c)),
    write: set == null
        ? null
        : (c, v, _) {
            final number = switch (v) {
              DoubleValue(:final value) => value,
              IntValue(:final value) => value.toDouble(),
              _ => null,
            };
            if (number != null) set(c, number);
          },
  );

  /// A floating-point property that can be absent.
  ///
  /// Unlike [number] there is no default: a null [get] result omits the key
  /// entirely, and an absent key leaves the component's own null in place.
  /// That distinction is the point for a value whose meaning is "unset" and
  /// not "zero" -- a pinned bound that otherwise falls back to an automatic
  /// scheme, say -- which a defaulted number cannot express.
  static ComponentField<C> optionalNumber<C extends Component>(
    String name, {
    double? Function(C component)? get,
    void Function(C component, double? value)? set,
    String? doc,
    String? group,
    List<PropertyConstraint<num>> constraints = const [],
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.number,
      doc: doc,
      group: group,
      constraints: constraints,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null
        ? null
        : (c, _) {
            final value = get(c);
            return value == null ? null : DoubleValue(value);
          },
    write: set == null
        ? null
        : (c, v, _) {
            set(c, switch (v) {
              DoubleValue(:final value) => value,
              IntValue(:final value) => value.toDouble(),
              _ => null,
            });
          },
  );

  /// A free-form string property.
  static ComponentField<C> string<C extends Component>(
    String name, {
    required String defaultValue,
    String Function(C component)? get,
    void Function(C component, String value)? set,
    String? doc,
    String? group,
    List<PropertyConstraint<String>> constraints = const [],
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.string,
      defaultValue: StringValue(defaultValue),
      doc: doc,
      group: group,
      constraints: constraints,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => StringValue(get(c)),
    write: set == null
        ? null
        : (c, v, _) {
            if (v is StringValue) set(c, v.value);
          },
  );

  /// An enum property carried as its value name string.
  static ComponentField<C> enumString<C extends Component, T extends Enum>(
    String name, {
    required List<T> values,
    required T defaultValue,
    T Function(C component)? get,
    void Function(C component, T value)? set,
    String? doc,
    String? group,
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.string,
      defaultValue: StringValue(defaultValue.name),
      doc: doc,
      group: group,
      options: [for (final value in values) value.name],
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => StringValue(get(c).name),
    write: set == null
        ? null
        : (c, v, _) {
            if (v is! StringValue) return;
            for (final value in values) {
              if (value.name == v.value) {
                set(c, value);
                return;
              }
            }
            debugPrint(
              'fscene: unrecognized $name value "${v.value}" on '
              '${c.runtimeType}; keeping ${get?.call(c).name ?? defaultValue.name}.',
            );
          },
  );

  /// A [Vector2] property.
  static ComponentField<C> vec2<C extends Component>(
    String name, {
    required Vector2 Function() defaultValue,
    Vector2 Function(C component)? get,
    void Function(C component, Vector2 value)? set,
    String? doc,
    String? group,
    List<PropertyConstraint<Object>> constraints = const [],
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.vec2,
      defaultValue: Vec2Value(defaultValue()),
      doc: doc,
      group: group,
      constraints: constraints,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => Vec2Value(get(c).clone()),
    write: set == null
        ? null
        : (c, v, _) {
            if (v is Vec2Value) set(c, v.value.clone());
          },
  );

  /// A [Vector3] property. Add an [RgbColor] constraint for linear RGB
  /// colors carried as vectors (byte-compatible with existing documents).
  static ComponentField<C> vec3<C extends Component>(
    String name, {
    required Vector3 Function() defaultValue,
    Vector3 Function(C component)? get,
    void Function(C component, Vector3 value)? set,
    String? doc,
    String? group,
    List<PropertyConstraint<Object>> constraints = const [],
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.vec3,
      defaultValue: Vec3Value(defaultValue()),
      doc: doc,
      group: group,
      constraints: constraints,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => Vec3Value(get(c).clone()),
    write: set == null
        ? null
        : (c, v, _) {
            if (v is! Vec3Value) return;
            final vector = v.value.clone();
            if (constraints.any((constraint) => constraint is Normalized) &&
                vector.length2 > 0) {
              vector.normalize();
            }
            set(c, vector);
          },
  );

  /// A [Vector4] property.
  static ComponentField<C> vec4<C extends Component>(
    String name, {
    required Vector4 Function() defaultValue,
    Vector4 Function(C component)? get,
    void Function(C component, Vector4 value)? set,
    String? doc,
    String? group,
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.vec4,
      defaultValue: Vec4Value(defaultValue()),
      doc: doc,
      group: group,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null ? null : (c, _) => Vec4Value(get(c).clone()),
    write: set == null
        ? null
        : (c, v, _) {
            if (v is Vec4Value) set(c, v.value.clone());
          },
  );

  /// A resource reference property. [get] recovers the source resource id
  /// from the live object it was realized into (see `resourceOrigin`).
  static ComponentField<C> resourceRef<C extends Component>(
    String name, {
    required String resourceKind,
    LocalId? Function(C component, SerializeContext context)? get,
    void Function(C component, LocalId id, RealizeContext context)? set,
    String? doc,
    String? group,
    List<String> formerNames = const [],
    bool transient = false,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.resourceRef,
      doc: doc,
      group: group,
      resourceKind: resourceKind,
      formerNames: formerNames,
      transient: transient,
    ),
    read: get == null
        ? null
        : (c, context) {
            final id = get(c, context);
            return id == null ? null : ResourceRefValue(id);
          },
    write: set == null
        ? null
        : (c, v, context) {
            if (v is ResourceRefValue) set(c, v.id, context);
          },
  );
}

/// Typed access to a component spec's property bag during [realize], with
/// schema defaults as fallbacks and former names resolved.
/// {@category Assets and loading}
final class PropertyReader {
  PropertyReader(this._spec, this._codec, this.context);

  final ComponentSpec _spec;
  final ComponentCodec _codec;

  /// The realize context (resource realizer, node resolution, afterRealize).
  final RealizeContext context;

  /// The raw property bag, for codecs handling legacy shapes directly.
  Map<String, PropertyValue> get properties => _spec.properties;

  /// The raw value for [name], accepting the descriptor's former names.
  PropertyValue? value(String name) {
    final direct = _spec.properties[name];
    if (direct != null) return direct;
    for (final def in _codec.propertySchema) {
      if (def.name != name) continue;
      for (final former in def.formerNames) {
        final legacy = _spec.properties[former];
        if (legacy != null) return legacy;
      }
    }
    return null;
  }

  PropertyValue? _defaultOf(String name) {
    for (final def in _codec.propertySchema) {
      if (def.name == name) return def.defaultValue;
    }
    return null;
  }

  double number(String name) => switch (value(name)) {
    DoubleValue(:final value) => value,
    IntValue(:final value) => value.toDouble(),
    _ => switch (_defaultOf(name)) {
      DoubleValue(:final value) => value,
      IntValue(:final value) => value.toDouble(),
      _ => 0,
    },
  };

  int integer(String name) => switch (value(name)) {
    IntValue(:final value) => value,
    _ => switch (_defaultOf(name)) {
      IntValue(:final value) => value,
      _ => 0,
    },
  };

  bool boolean(String name) => switch (value(name)) {
    BoolValue(:final value) => value,
    _ => switch (_defaultOf(name)) {
      BoolValue(:final value) => value,
      _ => false,
    },
  };

  String string(String name) => switch (value(name)) {
    StringValue(:final value) => value,
    _ => switch (_defaultOf(name)) {
      StringValue(:final value) => value,
      _ => '',
    },
  };

  Vector2 vec2(String name) => switch (value(name)) {
    Vec2Value(:final value) => value.clone(),
    _ => switch (_defaultOf(name)) {
      Vec2Value(:final value) => value.clone(),
      _ => Vector2.zero(),
    },
  };

  Vector3 vec3(String name) => switch (value(name)) {
    Vec3Value(:final value) => value.clone(),
    _ => switch (_defaultOf(name)) {
      Vec3Value(:final value) => value.clone(),
      _ => Vector3.zero(),
    },
  };

  Vector4 vec4(String name) => switch (value(name)) {
    Vec4Value(:final value) => value.clone(),
    _ => switch (_defaultOf(name)) {
      Vec4Value(:final value) => value.clone(),
      _ => Vector4.zero(),
    },
  };

  /// The enum value named by string property [name], or the declared default
  /// (then the first value) when absent or unrecognized. An unrecognized
  /// name (a newer writer or a typo) is reported, since serialize rebuilds
  /// from the live value and a save would silently replace it.
  T enumValue<T extends Enum>(String name, List<T> values) {
    final raw = string(name);
    for (final candidate in values) {
      if (candidate.name == raw) return candidate;
    }
    debugPrint(
      'fscene: unrecognized $name value "$raw" on ${_spec.type}; '
      'using ${values.first.name}.',
    );
    return values.first;
  }

  /// The referenced resource id for [name], or null.
  LocalId? resourceId(String name) => switch (value(name)) {
    ResourceRefValue(:final id) => id,
    _ => null,
  };

  /// The referenced node id for [name], or null.
  LocalId? nodeId(String name) => switch (value(name)) {
    NodeRefValue(:final id) => id,
    _ => null,
  };
}

/// A codec derived from one list of [fields]: the schema, realization
/// (construct via [create], then apply writable fields), and delta
/// serialization (read fields, omit values equal to their defaults) all come
/// from the same declarations.
/// {@category Assets and loading}
abstract class DeclarativeComponentCodec<C extends Component>
    extends ComponentCodec {
  /// The declared properties, in display and serialize order. Read once per
  /// codec (see [resolvedFields]); the getter typically builds a fresh list.
  List<ComponentField<C>> get fields;

  /// Constructs the component. Constructor-only configuration reads from
  /// [props]; everything with a `set` binding is applied after.
  C create(PropertyReader props);

  @override
  Type get componentType => C;

  List<ComponentField<C>>? _fields;
  List<ComponentPropertyDef>? _schema;

  /// The memoized [fields], so realize/serialize do not rebuild every
  /// descriptor and closure per call.
  List<ComponentField<C>> get resolvedFields =>
      _fields ??= List.unmodifiable(fields);

  @override
  List<ComponentPropertyDef> get propertySchema => _schema ??=
      List.unmodifiable([for (final field in resolvedFields) field.def]);

  @override
  bool claims(Component component) => component is C;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final props = PropertyReader(spec, this, context);
    final component = create(props);
    for (final field in resolvedFields) {
      final write = field.write;
      if (write == null) continue;
      final value = props.value(field.def.name);
      if (value == null) continue;
      write(component, value, context);
    }
    return component;
  }

  @override
  bool applyProperty(
    Component component,
    String name,
    PropertyValue value,
    RealizeContext context,
  ) {
    if (component is! C) return false;
    for (final field in resolvedFields) {
      if (field.def.name != name) continue;
      final write = field.write;
      // A property with no write binding is constructor-only: the controller
      // pose fields, the machine a state graph was built from. Saying so is
      // better than appearing to set it.
      if (write == null) return false;
      write(component, value, context);
      return true;
    }
    return false;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! C) return null;
    final properties = <String, PropertyValue>{};
    for (final field in resolvedFields) {
      final read = field.read;
      if (read == null || field.def.transient) continue;
      final value = read(component, context);
      if (value == null) continue;
      // Delta persistence: a value equal to the schema default is implied.
      if (propertyValuesEqual(value, field.def.defaultValue)) continue;
      properties[field.def.name] = value;
    }
    return ComponentSpec(type, properties: properties);
  }
}
