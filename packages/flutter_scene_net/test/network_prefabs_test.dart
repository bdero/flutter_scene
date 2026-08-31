// The spawn table. Its job is to keep the two halves of a replicated object in
// step — what the server sends and what the client builds — and the reason it
// can is that both come from the same declaration.

import 'package:dashwire/dashwire.dart' show fnv1a32;
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late FsceneComponentRegistry components;

  setUp(() {
    components = FsceneComponentRegistry()
      ..register(_PawnCodec())
      ..register(NetworkIdentityCodec());
  });

  Node buildPawn() => Node(name: 'pawn')..addComponent(_Pawn());

  NetworkPrefab pawnPrefab({
    String typeKey = 'pawn',
    List<SyncedProperty> synced = const [
      SyncedProperty('pawn', 'health'),
      SyncedProperty('pawn', 'label'),
    ],
  }) => NetworkPrefab(typeKey: typeKey, synced: synced, build: buildPawn);

  NetworkPrefabs tableOf(List<NetworkPrefab> prefabs) =>
      NetworkPrefabs(prefabs: prefabs, registry: components);

  group('building the table', () {
    test('it holds what it was given', () {
      final table = tableOf([pawnPrefab()]);
      expect(table.typeKeys, ['pawn']);
      expect(table.prefabFor('pawn'), isNotNull);
      expect(table.prefabFor('ghost'), isNull);
    });

    test('a prefab can come from an authored identity', () {
      // What the designer marked as replicated is exactly what goes over the
      // wire; there is no second list to keep in step with the first.
      final identity = NetworkIdentityComponent(
        typeKey: 'pawn',
        synced: const [SyncedProperty('pawn', 'health')],
      );
      final prefab = NetworkPrefab.of(identity, build: buildPawn);
      expect(prefab.typeKey, 'pawn');
      expect(prefab.synced.single.property, 'health');
    });

    test('a bad declaration is refused at startup, not at the first spawn', () {
      // A spawn table is built once at startup; a spawn happens mid-match.
      expect(
        () => tableOf([
          pawnPrefab(synced: const [SyncedProperty('pawn', 'stamina')]),
        ]),
        throwsA(isA<UnknownSyncedProperty>()),
      );
    });

    test('two prefabs claiming one type key are refused', () {
      // A type key is how the ends agree what a spawn is, so it has to name
      // exactly one thing.
      expect(
        () => tableOf([pawnPrefab(), pawnPrefab()]),
        throwsA(isA<DuplicateNetworkPrefab>()),
      );
    });
  });

  group('the replica registry', () {
    test('every prefab becomes a spawnable type', () {
      final registry = tableOf([
        pawnPrefab(),
        pawnPrefab(typeKey: 'turret'),
      ]).toRegistry();
      expect(registry.typeKeyFor(fnv1a32('pawn')), 'pawn');
      expect(registry.typeKeyFor(fnv1a32('turret')), 'turret');
    });

    test('the factory produces a declared replica with no node yet', () {
      // A client learns a replica exists before it has anywhere to put it.
      final registry = tableOf([pawnPrefab()]).toRegistry();
      final replica = registry.instantiate(fnv1a32('pawn'))!;
      expect(replica, isA<ComponentReplica>());
      expect((replica as ComponentReplica).node, isNull);
      expect(replica.fieldCount, 2);
    });

    test('an unbound replica pulls and pushes without throwing', () {
      final registry = tableOf([pawnPrefab()]).toRegistry();
      final replica =
          registry.instantiate(fnv1a32('pawn'))! as ComponentReplica;
      expect(replica.pull, returnsNormally);
      expect(replica.push, returnsNormally);
    });

    test('the schema hash catches two builds that disagree', () {
      // dashwire exchanges this at handshake. A server and a client that
      // loaded different versions of the document are refused at connect,
      // rather than agreeing to run and reading each other's fields wrong.
      final server = tableOf([pawnPrefab()]).toRegistry();
      final sameDocument = tableOf([pawnPrefab()]).toRegistry();
      final staleClient = tableOf([
        pawnPrefab(synced: const [SyncedProperty('pawn', 'health')]),
      ]).toRegistry();

      expect(server.schemaHash, sameDocument.schemaHash);
      expect(server.schemaHash, isNot(staleClient.schemaHash));
    });

    test('and catches a property whose authority was changed', () {
      // Who may write a field is part of the contract, not a local setting.
      final server = tableOf([pawnPrefab()]).toRegistry();
      final client = tableOf([
        pawnPrefab(
          synced: const [
            SyncedProperty('pawn', 'health', authority: Authority.owner),
            SyncedProperty('pawn', 'label'),
          ],
        ),
      ]).toRegistry();
      expect(server.schemaHash, isNot(client.schemaHash));
    });

    test('and catches the same fields declared in a different order', () {
      // Fields match by position on the wire.
      final a = tableOf([pawnPrefab()]).toRegistry();
      final b = tableOf([
        pawnPrefab(
          synced: const [
            SyncedProperty('pawn', 'label'),
            SyncedProperty('pawn', 'health'),
          ],
        ),
      ]).toRegistry();
      expect(a.schemaHash, isNot(b.schemaHash));
    });
  });

  group('spawning', () {
    test('builds the node and binds the replica to it', () {
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica;
      final node = table.spawn(replica)!;
      expect(replica.node, same(node));
    });

    test('the node starts at the state the server sent', () {
      // The spawn payload has landed by now, so pushing it here is what stops
      // a frame of the prefab's defaults before the first snapshot.
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica;
      replica.setValueAt(0, 17.0);
      replica.setValueAt(1, 'red');

      final node = table.spawn(replica)!;
      final pawn = node.getComponents<_Pawn>().single;
      expect(pawn.health, 17);
      expect(pawn.label, 'red');
    });

    test('a type this build has never heard of builds nothing', () {
      // What a stale client sees when the server spawns something new.
      final table = tableOf([pawnPrefab()]);
      final stranger =
          tableOf([
                pawnPrefab(typeKey: 'turret'),
              ]).toRegistry().instantiate(fnv1a32('turret'))!
              as ComponentReplica;
      expect(table.spawn(stranger), isNull);
    });

    test('the builders map covers every registered type', () {
      final table = tableOf([pawnPrefab(), pawnPrefab(typeKey: 'turret')]);
      expect(table.builders.keys.toSet(), {'pawn', 'turret'});
    });

    test('unbinding lets a despawned node go', () {
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica;
      table.spawn(replica);
      replica.unbind();
      expect(replica.node, isNull);
      expect(replica.pull, returnsNormally);
    });
  });

  test('a server-side replica reads the node it was spawned from', () {
    // The other direction: the host builds the node itself and binds a replica
    // to it, and pull is what puts its state on the wire.
    final table = tableOf([pawnPrefab()]);
    final node = buildPawn();
    node.getComponents<_Pawn>().single
      ..health = 55
      ..label = 'blue';
    final replica =
        table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica
          ..bind(node)
          ..pull();
    expect(replica.valueAt(0), 55);
    expect(replica.valueAt(1), 'blue');
  });

  group('the spawn lifecycle', () {
    test('a replica is not spawned until it has a node', () {
      // It exists from the moment the spawn message arrives; there is nothing
      // to read or write until it is attached.
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica;
      expect(replica.isSpawned, isFalse);
      table.spawn(replica);
      expect(replica.isSpawned, isTrue);
    });

    test('the spawn callback sees the authority’s state, not the defaults', () {
      // A handler that reads a replicated value on spawn should read the real
      // one rather than a prefab default it is about to be corrected from.
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica;
      replica.setValueAt(0, 33.0);

      double? seen;
      replica.onSpawn = (node) =>
          seen = node.getComponents<_Pawn>().single.health;
      table.spawn(replica);
      expect(seen, 33);
    });

    test('the despawn callback runs while there is still a node', () {
      // The matching place to stop what spawn started; it needs something to
      // clean up against.
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica;
      table.spawn(replica);

      var attached = false;
      replica.onDespawn = (node) => attached = replica.isSpawned;
      replica.unbind();
      expect(attached, isTrue);
      expect(replica.isSpawned, isFalse);
    });

    test('unbinding twice does not fire despawn twice', () {
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica;
      table.spawn(replica);
      var calls = 0;
      replica.onDespawn = (_) => calls++;
      replica
        ..unbind()
        ..unbind();
      expect(calls, 1);
    });

    test('ownership is asked, not assumed', () {
      // The object you spawned may not be yours by the time you next look.
      final table = tableOf([pawnPrefab()]);
      final replica =
          table.toRegistry().instantiate(fnv1a32('pawn'))! as ComponentReplica
            ..owner = 4;
      expect(replica.isOwnedBy(4), isTrue);
      expect(replica.isOwnedBy(5), isFalse);
      replica.owner = 5;
      expect(replica.isOwnedBy(5), isTrue);
    });
  });
}
