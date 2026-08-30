/// Marking an object as networked, in the document.
///
/// The replication layer underneath can already carry state and calls; what it
/// could not do was be *authored*. Making an object networked meant writing a
/// `Replica` subclass, listing its fields by hand, and wiring a builder — three
/// places in code for something a designer wants to express by dropping a
/// component on a thing and saying which of its values matter.
///
/// [NetworkIdentityComponent] is that component. It names the replica type, so
/// both ends agree on what this object is, and lists which component properties
/// replicate. Both ends load the same document, which is what makes the field
/// order match without either end being told: the wire layout is the list, and
/// the list is in the file.
library;

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart' show Component, Node;

import 'component_sync.dart';

/// Marks a node as replicated, and says what about it replicates.
///
/// Nothing here talks to the network. The component is a declaration; a
/// [ComponentReplica] is built from it when a session is running, and the same
/// declaration produces the same wire layout on the server and on every client.
class NetworkIdentityComponent extends Component {
  /// Creates an identity for replica type [typeKey].
  NetworkIdentityComponent({
    this.typeKey = 'entity',
    List<SyncedProperty> synced = const [],
  }) : synced = List.of(synced);

  /// The replica type both ends look this object up by.
  ///
  /// A stable string rather than a runtime type: the type name is minified on
  /// the web, so a client and a server built differently would disagree about
  /// what they were even talking about.
  String typeKey;

  /// Which component properties replicate, in wire order.
  final List<SyncedProperty> synced;

  /// Builds the replica for [node] from this declaration.
  ///
  /// Throws the same refusals [ComponentReplica] does — a property that cannot
  /// be carried, or one that is not declared — because a document naming a
  /// property that has since been renamed should fail where someone can see it
  /// rather than quietly replicate one field fewer than the other end expects.
  ComponentReplica replicaFor(
    Node? node, {
    required FsceneComponentRegistry registry,
  }) => ComponentReplica(
    typeKey: typeKey,
    node: node,
    properties: synced,
    registry: registry,
  );
}

/// The document form of one replicated property.
const List<ComponentPropertyDef> syncedPropertyFields = [
  ComponentPropertyDef(
    'component',
    ComponentPropertyKind.string,
    defaultValue: StringValue(''),
    doc: 'The component type the property is declared on.',
  ),
  ComponentPropertyDef(
    'property',
    ComponentPropertyKind.string,
    defaultValue: StringValue(''),
    doc: 'The declared property that replicates.',
  ),
  ComponentPropertyDef(
    'authority',
    ComponentPropertyKind.string,
    defaultValue: StringValue('server'),
    options: ['server', 'owner'],
    doc:
        'Who may change it. Server unless the owning client is the one that '
        'decides — a client that can write its own health is a client that '
        'never dies.',
  ),
  ComponentPropertyDef(
    'mode',
    ComponentPropertyKind.string,
    defaultValue: StringValue('stream'),
    options: ['stream', 'onChange', 'spawnOnly'],
    doc:
        'How often it goes out. Stream for something that moves; onChange for '
        'a name or a team, which changes rarely and must not be missed; '
        'spawnOnly for something fixed at spawn.',
  ),
  ComponentPropertyDef(
    'resolution',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc:
        'Quantization step for numbers and vectors, or 0 for full precision. '
        'A position to the nearest centimetre is indistinguishable on screen '
        'and a fraction of the bytes.',
    constraints: [Range.nonNegative()],
  ),
];

/// Encodes [property] as the document holds it.
MapValue encodeSyncedProperty(SyncedProperty property) => MapValue({
  'component': StringValue(property.componentType),
  'property': StringValue(property.property),
  'authority': StringValue(property.authority.name),
  'mode': StringValue(property.mode.name),
  'resolution': DoubleValue(property.resolution ?? 0),
});

/// Decodes one replicated property, or null when it names nothing.
///
/// A row with no component or no property is a half-filled row in the
/// inspector, which is what one looks like the moment it is added. Dropping it
/// is better than refusing to load the scene around it.
SyncedProperty? decodeSyncedProperty(PropertyValue? value) {
  if (value is! MapValue) return null;
  final map = value.values;
  String string(String key) =>
      map[key] is StringValue ? (map[key]! as StringValue).value : '';
  final component = string('component');
  final property = string('property');
  if (component.isEmpty || property.isEmpty) return null;
  final resolution = switch (map['resolution']) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => 0.0,
  };
  return SyncedProperty(
    component,
    property,
    authority: string('authority') == 'owner'
        ? Authority.owner
        : Authority.server,
    mode: switch (string('mode')) {
      'onChange' => SendMode.onChange,
      'spawnOnly' => SendMode.spawnOnly,
      _ => SendMode.stream,
    },
    resolution: resolution > 0 ? resolution : null,
  );
}

/// Codec for [NetworkIdentityComponent] (`networkIdentity`).
class NetworkIdentityCodec
    extends DeclarativeComponentCodec<NetworkIdentityComponent> {
  @override
  String get type => 'networkIdentity';

  @override
  String? get category => 'Networking';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'network',
    properties: propertySchema,
  );

  @override
  List<ComponentField<NetworkIdentityComponent>> get fields => [
    ComponentField.string(
      'typeKey',
      defaultValue: 'entity',
      doc:
          'The replica type both ends look this object up by. It has to match '
          'across the server and every client, so it is a string in the '
          'document rather than a Dart type name, which the web build '
          'minifies.',
      get: (c) => c.typeKey,
      set: (c, v) => c.typeKey = v,
    ),
    ComponentField(
      ComponentPropertyDef(
        'synced',
        ComponentPropertyKind.list,
        // An empty list, so an identity nobody has configured serializes as
        // nothing at all, the way every other component does.
        defaultValue: ListValue(const []),
        itemDef: const ComponentPropertyDef(
          'property',
          ComponentPropertyKind.object,
          objectFields: syncedPropertyFields,
        ),
        doc:
            'Which component properties replicate. The order is the wire '
            'order on both ends, which is why it lives in the document: both '
            'ends load the same list.',
      ),
      read: (c, _) =>
          ListValue([for (final p in c.synced) encodeSyncedProperty(p)]),
      write: (c, value, _) {
        if (value is! ListValue) return;
        c.synced
          ..clear()
          ..addAll([
            for (final entry in value.values)
              if (decodeSyncedProperty(entry) case final property?) property,
          ]);
      },
    ),
  ];

  @override
  NetworkIdentityComponent create(PropertyReader props) =>
      NetworkIdentityComponent(typeKey: props.string('typeKey'));
}
