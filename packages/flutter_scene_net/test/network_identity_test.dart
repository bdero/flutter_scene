// Making an object networked from the document. The declaration is what both
// ends load, so what matters is that it round-trips exactly and that it
// produces the same wire layout wherever it is read.

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/schema.dart';

class _Pawn extends Component {
  double health = 100;
  String label = '';
}

class _PawnCodec extends DeclarativeComponentCodec<_Pawn> {
  @override
  String get type => 'pawn';

  @override
  ComponentSchema get schema =>
      ComponentSchema(type, properties: propertySchema);

  @override
  List<ComponentField<_Pawn>> get fields => [
    ComponentField.number(
      'health',
      defaultValue: 100,
      get: (c) => c.health,
      set: (c, v) => c.health = v,
    ),
    ComponentField.string(
      'label',
      defaultValue: '',
      get: (c) => c.label,
      set: (c, v) => c.label = v,
    ),
  ];

  @override
  _Pawn create(PropertyReader props) => _Pawn();
}

void main() {
  late FsceneComponentRegistry registry;
  final document = SceneDocument();

  setUp(() {
    registry = FsceneComponentRegistry()
      ..register(_PawnCodec())
      ..register(NetworkIdentityCodec());
  });

  NetworkIdentityComponent realize(Map<String, PropertyValue> properties) =>
      registry
              .codecFor('networkIdentity')!
              .realize(
                ComponentSpec('networkIdentity', properties: properties),
                RealizeContext(document),
              )!
          as NetworkIdentityComponent;

  Map<String, PropertyValue> serialize(Component component) => registry
      .codecFor('networkIdentity')!
      .serialize(component, SerializeContext(document))!
      .properties;

  test('it shows up under Networking in the picker', () {
    expect(registry.codecFor('networkIdentity')!.schema.category, 'Networking');
  });

  test('an untouched identity writes nothing', () {
    expect(serialize(NetworkIdentityComponent()), isEmpty);
  });

  group('the declaration', () {
    test('round trips the type key and every synced property', () {
      final before = NetworkIdentityComponent(
        typeKey: 'pawn',
        synced: const [
          SyncedProperty('pawn', 'health'),
          SyncedProperty(
            'pawn',
            'label',
            authority: Authority.owner,
            mode: SendMode.onChange,
            resolution: 0.25,
          ),
        ],
      );
      final after = realize(serialize(before));

      expect(after.typeKey, 'pawn');
      expect(after.synced.length, 2);
      expect(after.synced[0].componentType, 'pawn');
      expect(after.synced[0].property, 'health');
      expect(after.synced[0].authority, Authority.server);
      expect(after.synced[0].resolution, isNull);
      expect(after.synced[1].authority, Authority.owner);
      expect(after.synced[1].mode, SendMode.onChange);
      expect(after.synced[1].resolution, 0.25);
    });

    test('the order survives, because the order is the wire layout', () {
      // Both ends load this list and match fields by position, so a document
      // that reordered on load would have the two ends reading each other's
      // fields as the wrong ones.
      final before = NetworkIdentityComponent(
        typeKey: 'pawn',
        synced: const [
          SyncedProperty('pawn', 'label'),
          SyncedProperty('pawn', 'health'),
        ],
      );
      expect(
        realize(serialize(before)).synced.map((p) => p.property).toList(),
        ['label', 'health'],
      );
    });

    test('a half-filled row is dropped rather than failing the load', () {
      // Which is what a row looks like the moment it is added in the
      // inspector, before anything is typed into it.
      final identity = realize({
        'synced': ListValue([
          MapValue({'component': const StringValue('pawn')}),
          encodeSyncedProperty(const SyncedProperty('pawn', 'health')),
        ]),
      });
      expect(identity.synced.length, 1);
      expect(identity.synced.single.property, 'health');
    });

    test('an unrecognized authority is the safe one', () {
      final property = decodeSyncedProperty(
        MapValue({
          'component': const StringValue('pawn'),
          'property': const StringValue('health'),
          'authority': const StringValue('anyone'),
        }),
      )!;
      expect(property.authority, Authority.server);
    });

    test('zero resolution means full precision, not a zero step', () {
      final property = decodeSyncedProperty(
        MapValue({
          'component': const StringValue('pawn'),
          'property': const StringValue('health'),
          'resolution': const DoubleValue(0),
        }),
      )!;
      expect(property.resolution, isNull);
    });
  });

  group('building the replica from it', () {
    test('the declaration produces the replica', () {
      final identity = NetworkIdentityComponent(
        typeKey: 'pawn',
        synced: const [
          SyncedProperty('pawn', 'health'),
          SyncedProperty('pawn', 'label'),
        ],
      );
      final pawn = _Pawn()..health = 30;
      final node = Node(name: 'pawn')
        ..addComponent(pawn)
        ..addComponent(identity);

      final replica = identity.replicaFor(node, registry: registry)..pull();
      expect(replica.typeKey, 'pawn');
      expect((replica.fields[0] as Rep).value, 30);
    });

    test('a document naming a property that no longer exists is refused', () {
      // Loud, where someone can see it. Quietly replicating one field fewer
      // than the other end expects is the failure that shows up as entities
      // reading each other's values.
      final identity = NetworkIdentityComponent(
        typeKey: 'pawn',
        synced: const [SyncedProperty('pawn', 'stamina')],
      );
      final node = Node(name: 'pawn')..addComponent(_Pawn());
      expect(
        () => identity.replicaFor(node, registry: registry),
        throwsA(isA<UnknownSyncedProperty>()),
      );
    });
  });

  test('registering the net codecs registers this one too', () {
    final fresh = FsceneComponentRegistry();
    registerNetComponentCodecs(fresh);
    expect(fresh.codecFor('networkIdentity'), isNotNull);
  });
}
