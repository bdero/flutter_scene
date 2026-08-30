/// Replicating a component's declared properties.
///
/// A networked object in this engine already describes itself: every component
/// has a codec, and every codec declares its properties with a name, a kind, a
/// default, and — the part that matters here — a `read` that gets the value off
/// the live component and a `write` that puts one back. That is exactly the
/// pair a replicated field needs.
///
/// So nothing here re-declares anything. You name a component type and the
/// properties on it that should replicate, and the replica is built from the
/// schema that was already there. The alternative — a hand-written `Replica`
/// subclass per networked type, with its own field list — is the same
/// information written twice, and the second copy is the one that goes stale
/// when someone renames a property.
///
/// **What can replicate.** The kinds with an unambiguous wire form: numbers,
/// integers, booleans, strings, vectors, quaternions, and colours. A property
/// of any other kind is *refused*, loudly, when the replica is built. A
/// property somebody marked as replicated that silently does not replicate is
/// the worst outcome available: it looks right on the machine that changed it
/// and is wrong everywhere else.
library;

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart' show Component, Node;
import 'package:vector_math/vector_math.dart';

/// A component property that replicates.
class SyncedProperty {
  /// Replicates [property] of the component of [componentType].
  const SyncedProperty(
    this.componentType,
    this.property, {
    this.authority = Authority.server,
    this.mode = SendMode.stream,
    this.resolution,
  });

  /// The component's document type, as its codec names it.
  final String componentType;

  /// The declared property on that component.
  final String property;

  /// Who is allowed to change it. Server by default: a client that could
  /// write its own health is a client that never dies.
  final Authority authority;

  /// How often it goes out. Position streams; a name or a team changes rarely
  /// and must not be missed, so [SendMode.onChange] suits it better.
  final SendMode mode;

  /// Quantization step for numeric kinds, or null for full precision.
  ///
  /// A position to the nearest centimetre costs a fraction of a float and is
  /// indistinguishable on screen. Whether that trade is right depends on what
  /// the number is, which is why it is named here rather than assumed.
  final double? resolution;
}

/// A property whose kind has no wire form.
class UnsyncableProperty implements Exception {
  UnsyncableProperty(this.componentType, this.property, this.kind);

  final String componentType;
  final String property;
  final ComponentPropertyKind kind;

  @override
  String toString() =>
      'flutter_scene_net: $componentType.$property is a ${kind.name}, which '
      'has no wire form. Replicate the parts of it that do, or drive it from '
      'a property that replicates. Leaving it in the list would mean it '
      'silently did not replicate, which looks correct on whichever machine '
      'changed it and is wrong on every other one.';
}

/// A property that is not declared on the component named.
class UnknownSyncedProperty implements Exception {
  UnknownSyncedProperty(this.componentType, this.property, this.available);

  final String componentType;
  final String property;
  final List<String> available;

  @override
  String toString() =>
      'flutter_scene_net: $componentType has no property "$property". It '
      'declares: ${available.join(', ')}.';
}

/// A component type with no codec registered.
class UnknownSyncedComponent implements Exception {
  UnknownSyncedComponent(this.componentType);

  final String componentType;

  @override
  String toString() =>
      'flutter_scene_net: no codec is registered for component type '
      '"$componentType", so its properties cannot be read or written. '
      'Register its codec before building the replica.';
}

/// The wire form of one property kind: how to carry it, and how to convert
/// between the wire's value and the codec's [PropertyValue].
///
/// Deliberately a small, closed set. Every entry is a kind whose meaning
/// survives being quantized and sent; the kinds left out are left out because
/// there is no single right answer for them, not because nobody got to them.
sealed class PropertyWire<T> {
  const PropertyWire();

  Codec<T> codec(double? resolution);

  /// The value read off the component, as the wire carries it.
  T from(PropertyValue value);

  /// The wire value, as the component's codec takes it.
  PropertyValue to(T value);

  T get zero;
}

class _NumberWire extends PropertyWire<double> {
  const _NumberWire();

  @override
  Codec<double> codec(double? resolution) =>
      resolution == null ? Codecs.f32 : Codecs.quantized(resolution);

  @override
  double from(PropertyValue value) => switch (value) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => 0,
  };

  @override
  PropertyValue to(double value) => DoubleValue(value);

  @override
  double get zero => 0;
}

class _IntWire extends PropertyWire<int> {
  const _IntWire();

  @override
  Codec<int> codec(double? resolution) => Codecs.i32;

  @override
  int from(PropertyValue value) => switch (value) {
    IntValue(value: final v) => v,
    DoubleValue(value: final v) => v.round(),
    _ => 0,
  };

  @override
  PropertyValue to(int value) => IntValue(value);

  @override
  int get zero => 0;
}

class _BoolWire extends PropertyWire<bool> {
  const _BoolWire();

  @override
  Codec<bool> codec(double? resolution) => Codecs.boolean;

  @override
  bool from(PropertyValue value) => value is BoolValue ? value.value : false;

  @override
  PropertyValue to(bool value) => BoolValue(value);

  @override
  bool get zero => false;
}

class _StringWire extends PropertyWire<String> {
  const _StringWire();

  @override
  Codec<String> codec(double? resolution) => Codecs.string;

  @override
  String from(PropertyValue value) => value is StringValue ? value.value : '';

  @override
  PropertyValue to(String value) => StringValue(value);

  @override
  String get zero => '';
}

class _Vec3Wire extends PropertyWire<Vec3> {
  const _Vec3Wire();

  /// A centimetre by default: below what a player can see at a metre, and a
  /// third the bytes of three floats.
  @override
  Codec<Vec3> codec(double? resolution) => Codecs.vec3(resolution ?? 0.01);

  @override
  Vec3 from(PropertyValue value) => switch (value) {
    Vec3Value(value: final v) => (v.x, v.y, v.z),
    _ => (0.0, 0.0, 0.0),
  };

  @override
  PropertyValue to(Vec3 value) =>
      Vec3Value(Vector3(value.$1, value.$2, value.$3));

  @override
  Vec3 get zero => (0.0, 0.0, 0.0);
}

class _QuatWire extends PropertyWire<Quat> {
  const _QuatWire();

  @override
  Codec<Quat> codec(double? resolution) => Codecs.quat;

  @override
  Quat from(PropertyValue value) => switch (value) {
    QuaternionValue(value: final q) => (q.x, q.y, q.z, q.w),
    Vec4Value(value: final v) => (v.x, v.y, v.z, v.w),
    _ => (0.0, 0.0, 0.0, 1.0),
  };

  @override
  PropertyValue to(Quat value) =>
      QuaternionValue(Quaternion(value.$1, value.$2, value.$3, value.$4));

  @override
  Quat get zero => (0.0, 0.0, 0.0, 1.0);
}

/// The wire form for [kind], or null when it has none.
PropertyWire<Object?>? wireFor(ComponentPropertyKind kind) => switch (kind) {
  ComponentPropertyKind.number => const _NumberWire(),
  ComponentPropertyKind.integer => const _IntWire(),
  ComponentPropertyKind.boolean => const _BoolWire(),
  ComponentPropertyKind.string => const _StringWire(),
  ComponentPropertyKind.vec3 => const _Vec3Wire(),
  ComponentPropertyKind.quaternion => const _QuatWire(),
  _ => null,
};

/// Whether [kind] can replicate.
bool canSync(ComponentPropertyKind kind) => wireFor(kind) != null;

/// One property, resolved against a live registry: where to read it, where to
/// write it, and how it goes over the wire.
class _Bound {
  _Bound(this.spec, this.def, this.wire, this.codec, this.rep);

  final SyncedProperty spec;
  final ComponentPropertyDef def;
  final PropertyWire<Object?> wire;
  final ComponentCodec codec;
  final Rep<Object?> rep;
}

/// A replica whose fields are a node's component properties.
///
/// Built from the component schemas rather than declared: name the properties
/// that replicate and this reads them off the live components each tick on the
/// authority, and writes them back into the live components on everyone else.
///
/// The order of [properties] is the wire order, on both ends. That is
/// dashwire's contract, not a detail of this class — a replica's fields are
/// matched by position, so the two ends must build the list the same way. In
/// practice that means the list comes from the document, which is the one
/// description both ends load.
final class ComponentReplica extends Replica {
  /// Binds [properties] on [node], resolving them through [registry].
  ///
  /// Throws [UnknownSyncedComponent], [UnknownSyncedProperty] or
  /// [UnsyncableProperty] rather than skipping anything it cannot handle: a
  /// replica that quietly drops a field is a replica whose wire layout no
  /// longer matches the other end's.
  ComponentReplica({
    required this.typeKey,
    required List<SyncedProperty> properties,
    required FsceneComponentRegistry registry,
    Node? node,
  }) : _node = node {
    for (final spec in properties) {
      final codec = registry.codecFor(spec.componentType);
      if (codec == null) throw UnknownSyncedComponent(spec.componentType);

      final schema = codec.propertySchema;
      final def = schema.where((p) => p.name == spec.property).firstOrNull;
      if (def == null) {
        throw UnknownSyncedProperty(spec.componentType, spec.property, [
          for (final p in schema) p.name,
        ]);
      }

      final wire = wireFor(def.kind);
      if (wire == null) {
        throw UnsyncableProperty(spec.componentType, spec.property, def.kind);
      }

      _bound.add(
        _Bound(
          spec,
          def,
          wire,
          codec,
          rep<Object?>(
            '${spec.componentType}.${spec.property}',
            wire.zero,
            codec: wire.codec(spec.resolution),
            mode: spec.mode,
            write: spec.authority,
          ),
        ),
      );
    }
  }

  @override
  final String typeKey;

  Node? _node;

  /// The node whose components this replicates, or null before one exists.
  ///
  /// A client learns a replica exists before it has anywhere to put it: the
  /// spawn message arrives, the replica is built from the registry, and only
  /// then is the node created for it. The fields are declared from the
  /// property list alone, so the replica is complete without a node — it just
  /// has nothing to read from or write to until [bind].
  Node? get node => _node;

  /// Attaches this replica to [node].
  void bind(Node node) => _node = node;

  /// Detaches it, on despawn.
  void unbind() => _node = null;

  final List<_Bound> _bound = [];

  /// The declared properties, in wire order.
  Iterable<SyncedProperty> get properties => _bound.map((b) => b.spec);

  /// How many fields this replica carries.
  int get fieldCount => _bound.length;

  /// The current value of the field at [index], in its wire form.
  ///
  /// Numbers come back as doubles, vectors as records; the shapes
  /// [PropertyWire] converts to. For inspecting what a replica currently
  /// holds — a debug overlay, a test standing in for the wire — without
  /// reaching into dashwire's internals.
  Object? valueAt(int index) => _bound[index].rep.value;

  /// Sets the field at [index], as a snapshot landing does.
  ///
  /// Whether the change is allowed to go anywhere is dashwire's business:
  /// a field the server owns, written on a client, is not sent. This is the
  /// same door a snapshot comes through.
  void setValueAt(int index, Object? value) => _bound[index].rep.value = value;

  /// Reads the live components into the replicated fields.
  ///
  /// Called on whichever end has authority, once a tick. Only fields whose
  /// value actually changed go out: dashwire tracks that per field, so a
  /// property that sits still costs nothing after the first send.
  void pull() {
    if (_node == null) return;
    final context = SerializeContext(_scratchDocument);
    for (final bound in _bound) {
      final component = _componentFor(bound);
      if (component == null) continue;
      final spec = bound.codec.serialize(component, context);
      // Components serialize as a delta from their schema defaults, so a
      // property sitting at its default is absent rather than present-and-
      // default. Reading the default here is what keeps the two ends agreeing
      // about a value nobody has changed.
      final value = spec?.properties[bound.def.name] ?? bound.def.defaultValue;
      if (value == null) continue;
      bound.rep.value = bound.wire.from(value);
    }
  }

  /// Writes the replicated fields back into the live components.
  ///
  /// Called on the ends without authority, after a snapshot lands.
  void push() {
    if (_node == null) return;
    final context = RealizeContext(_scratchDocument);
    for (final bound in _bound) {
      final component = _componentFor(bound);
      if (component == null) continue;
      bound.codec.applyProperty(
        component,
        bound.def.name,
        bound.wire.to(bound.rep.value),
        context,
      );
    }
  }

  Component? _componentFor(_Bound bound) {
    final node = _node;
    if (node == null) return null;
    for (final component in node.getComponents<Component>()) {
      if (bound.codec.claims(component)) return component;
    }
    return null;
  }
}

/// A document the read and write paths need but never actually consult.
///
/// Serialize and realize contexts exist to resolve cross-references — a
/// texture id, a node id — and the properties that replicate are the ones with
/// no references in them. One empty document shared by every replica is
/// cheaper than one per replica per tick, and it stays empty.
final SceneDocument _scratchDocument = SceneDocument();
