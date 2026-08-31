// Events, as opposed to state. Properties carry what is continuously true;
// events carry what happened once, and a property that flickered to record one
// would be a property you could miss between two snapshots.

import 'package:dashwire/dashwire.dart' show fnv1a32;
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pawn extends Component {
  double health = 100;
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

  ComponentReplica replicaWith(List<NetworkEvent> events) => ComponentReplica(
    typeKey: 'pawn',
    properties: const [SyncedProperty('pawn', 'health')],
    events: events,
    registry: registry,
  );

  group('declaring', () {
    test('an event becomes a named endpoint', () {
      final replica = replicaWith(const [NetworkEvent('fire')]);
      expect(replica.eventNames, ['fire']);
    });

    test('events default to asking the server, from the owner only', () {
      // The direction is the security boundary: a client asks, the server
      // decides. Anything else is a client writing its own health.
      const event = NetworkEvent('fire');
      expect(event.to, RpcTarget.server);
      expect(event.requireOwner, isTrue);
      expect(event.delivery, Delivery.reliable);
    });

    test('two events with one name are refused', () {
      // They are matched by name across the two ends, so a name has to mean
      // one thing.
      expect(
        () => replicaWith(const [NetworkEvent('fire'), NetworkEvent('fire')]),
        throwsA(isA<DuplicateNetworkEvent>()),
      );
    });

    test('sending one nobody declared throws rather than vanishing', () {
      // A message that silently goes nowhere is the hardest kind of bug to
      // see: everything looks fine on the machine that sent it.
      final replica = replicaWith(const [NetworkEvent('fire')]);
      expect(() => replica.send('reload'), throwsA(isA<UnknownNetworkEvent>()));
    });

    test('the refusal says what was available', () {
      final replica = replicaWith(const [NetworkEvent('fire')]);
      try {
        replica.send('reolad');
        fail('expected a refusal');
      } on UnknownNetworkEvent catch (error) {
        expect(error.toString(), contains('fire'));
      }
    });

    test('an object with no events says so rather than listing nothing', () {
      final replica = replicaWith(const []);
      try {
        replica.send('fire');
        fail('expected a refusal');
      } on UnknownNetworkEvent catch (error) {
        expect(error.toString(), contains('(none)'));
      }
    });
  });

  NetworkIdentityComponent realizeIdentity(
    Map<String, PropertyValue> properties,
  ) =>
      registry
              .codecFor('networkIdentity')!
              .realize(
                ComponentSpec('networkIdentity', properties: properties),
                RealizeContext(document),
              )!
          as NetworkIdentityComponent;

  Map<String, PropertyValue> serializeIdentity(Component component) => registry
      .codecFor('networkIdentity')!
      .serialize(component, SerializeContext(document))!
      .properties;

  group('the document form', () {
    test('an event round trips with every setting', () {
      final before = NetworkIdentityComponent(
        typeKey: 'pawn',
        events: const [
          NetworkEvent('fire'),
          NetworkEvent(
            'explode',
            to: RpcTarget.all,
            delivery: Delivery.unreliable,
            requireOwner: false,
          ),
        ],
      );
      final after = realizeIdentity(serializeIdentity(before));
      expect(after.events.map((e) => e.name).toList(), ['fire', 'explode']);
      expect(after.events[0].to, RpcTarget.server);
      expect(after.events[1].to, RpcTarget.all);
      expect(after.events[1].delivery, Delivery.unreliable);
      expect(after.events[1].requireOwner, isFalse);
    });

    test('an identity with no events writes nothing', () {
      expect(serializeIdentity(NetworkIdentityComponent()), isEmpty);
    });

    test('a half-filled row is dropped rather than failing the load', () {
      // What a row looks like the moment it is added in the inspector.
      final identity = realizeIdentity({
        'events': ListValue([
          MapValue({'to': const StringValue('all')}),
          encodeNetworkEvent(const NetworkEvent('fire')),
        ]),
      });
      expect(identity.events.map((e) => e.name).toList(), ['fire']);
    });

    test('an unrecognized target is the safe one', () {
      // Server: a request the server decides on, rather than something a
      // client gets to broadcast.
      final event = decodeNetworkEvent(
        MapValue({
          'name': const StringValue('fire'),
          'to': const StringValue('everybody'),
        }),
      )!;
      expect(event.to, RpcTarget.server);
    });

    test('the order survives, because the order is the wire layout', () {
      final before = NetworkIdentityComponent(
        typeKey: 'pawn',
        events: const [NetworkEvent('b'), NetworkEvent('a')],
      );
      expect(
        realizeIdentity(
          serializeIdentity(before),
        ).events.map((e) => e.name).toList(),
        ['b', 'a'],
      );
    });
  });

  group('the schema hash', () {
    NetworkPrefabs table(List<NetworkEvent> events) => NetworkPrefabs(
      prefabs: [
        NetworkPrefab(
          typeKey: 'pawn',
          synced: const [SyncedProperty('pawn', 'health')],
          events: events,
          build: () => Node(name: 'pawn')..addComponent(_Pawn()),
        ),
      ],
      registry: registry,
    );

    test('two builds declaring the same events agree', () {
      expect(
        table(const [NetworkEvent('fire')]).toRegistry().schemaHash,
        table(const [NetworkEvent('fire')]).toRegistry().schemaHash,
      );
    });

    test('and disagree when one adds an event', () {
      // Caught at connect, rather than a client calling an endpoint index the
      // server means something else by.
      expect(
        table(const [NetworkEvent('fire')]).toRegistry().schemaHash,
        isNot(
          table(const [
            NetworkEvent('fire'),
            NetworkEvent('reload'),
          ]).toRegistry().schemaHash,
        ),
      );
    });

    test('and when one changes an event to a different direction', () {
      // Who runs an event is part of the contract, not a local setting.
      expect(
        table(const [NetworkEvent('fire')]).toRegistry().schemaHash,
        isNot(
          table(const [
            NetworkEvent('fire', to: RpcTarget.all),
          ]).toRegistry().schemaHash,
        ),
      );
    });

    test('a spawned replica carries the prefab’s events', () {
      final prefabs = table(const [NetworkEvent('fire')]);
      final replica =
          prefabs.toRegistry().instantiate(fnv1a32('pawn'))!
              as ComponentReplica;
      expect(replica.eventNames, ['fire']);
    });
  });

  group('who receives a property', () {
    test('everyone, unless it is somebody\'s business alone', () {
      const open = SyncedProperty('pawn', 'health');
      expect(open.readableBy, ReadScope.everyone);
    });

    test('owner-only is a real secret, not a hidden one', () {
      // The bytes are never sent, so there is nothing in another client to
      // read -- which is the difference between private and merely not shown.
      const secret = SyncedProperty(
        'pawn',
        'health',
        readableBy: ReadScope.ownerOnly,
      );
      expect(secret.readableBy, ReadScope.ownerOnly);
    });

    test('it round trips through the document', () {
      final before = NetworkIdentityComponent(
        typeKey: 'pawn',
        synced: const [
          SyncedProperty('pawn', 'health', readableBy: ReadScope.ownerOnly),
          SyncedProperty('pawn', 'health', readableBy: ReadScope.skipOwner),
        ],
      );
      final after = realizeIdentity(serializeIdentity(before));
      expect(after.synced[0].readableBy, ReadScope.ownerOnly);
      expect(after.synced[1].readableBy, ReadScope.skipOwner);
    });

    test('an unrecognized scope is the one that hides nothing', () {
      // Defaulting to secret would make a client silently miss state it needs
      // to draw, which looks like a rendering bug rather than a config one.
      final property = decodeSyncedProperty(
        MapValue({
          'component': const StringValue('pawn'),
          'property': const StringValue('health'),
          'readableBy': const StringValue('nobody'),
        }),
      )!;
      expect(property.readableBy, ReadScope.everyone);
    });

    test('and it changes the schema hash, because it changes the wire', () {
      // Two builds disagreeing about who receives a field would disagree
      // about the shape of every snapshot carrying it.
      NetworkPrefabs table(ReadScope scope) => NetworkPrefabs(
        prefabs: [
          NetworkPrefab(
            typeKey: 'pawn',
            synced: [SyncedProperty('pawn', 'health', readableBy: scope)],
            build: () => Node(name: 'pawn')..addComponent(_Pawn()),
          ),
        ],
        registry: registry,
      );
      expect(
        table(ReadScope.everyone).toRegistry().schemaHash,
        isNot(table(ReadScope.ownerOnly).toRegistry().schemaHash),
      );
    });
  });
}
