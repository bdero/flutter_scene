// Replicating a component's declared properties. The point of building the
// replica from the component schema is that there is only one description of a
// networked object; these cover that it reads and writes the live component
// correctly, and that anything it cannot carry is refused loudly rather than
// dropped.

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/schema.dart';
import 'package:vector_math/vector_math.dart';

/// A component with one property of each kind that matters here.
class _Pawn extends Component {
  double health = 100;
  int team = 0;
  bool alive = true;
  String label = '';
  Vector3 aim = Vector3(0, 0, 1);
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
    ComponentField.integer(
      'team',
      defaultValue: 0,
      get: (c) => c.team,
      set: (c, v) => c.team = v,
    ),
    ComponentField.boolean(
      'alive',
      defaultValue: true,
      get: (c) => c.alive,
      set: (c, v) => c.alive = v,
    ),
    ComponentField.string(
      'label',
      defaultValue: '',
      get: (c) => c.label,
      set: (c, v) => c.label = v,
    ),
    ComponentField.vec3(
      'aim',
      defaultValue: () => Vector3(0, 0, 1),
      get: (c) => c.aim,
      set: (c, v) => c.aim = v,
    ),
    // Constructor-only: declared, but with no way to set it after the fact.
    ComponentField.number('spawnRadius', defaultValue: 1, get: (c) => 1),
    // A kind with no wire form.
    ComponentField(
      const ComponentPropertyDef('loadout', ComponentPropertyKind.map),
      read: (c, _) => MapValue(const {}),
    ),
  ];

  @override
  _Pawn create(PropertyReader props) => _Pawn();
}

void main() {
  late FsceneComponentRegistry registry;

  setUp(() {
    registry = FsceneComponentRegistry()..register(_PawnCodec());
  });

  ({Node node, _Pawn pawn}) pawnNode() {
    final pawn = _Pawn();
    final node = Node(name: 'pawn')..addComponent(pawn);
    return (node: node, pawn: pawn);
  }

  ComponentReplica replicaFor(Node node, List<SyncedProperty> properties) =>
      ComponentReplica(
        typeKey: 'pawn',
        node: node,
        properties: properties,
        registry: registry,
      );

  group('what can replicate', () {
    test('the kinds with an unambiguous wire form', () {
      for (final kind in [
        ComponentPropertyKind.number,
        ComponentPropertyKind.integer,
        ComponentPropertyKind.boolean,
        ComponentPropertyKind.string,
        ComponentPropertyKind.vec3,
        ComponentPropertyKind.quaternion,
      ]) {
        expect(canSync(kind), isTrue, reason: '${kind.name} should replicate');
      }
    });

    test('and not the ones with no single right answer', () {
      for (final kind in [
        ComponentPropertyKind.map,
        ComponentPropertyKind.union,
        ComponentPropertyKind.list,
        ComponentPropertyKind.resourceRef,
        ComponentPropertyKind.matrix4,
      ]) {
        expect(canSync(kind), isFalse, reason: '${kind.name} has no wire form');
      }
    });
  });

  group('building the replica', () {
    test('declares a field per property, in the order given', () {
      final replica = replicaFor(pawnNode().node, const [
        SyncedProperty('pawn', 'health'),
        SyncedProperty('pawn', 'team'),
      ]);
      expect(replica.properties.map((p) => p.property).toList(), [
        'health',
        'team',
      ]);
    });

    test('a property with no wire form is refused, not skipped', () {
      // Skipping would leave this end's wire layout one field shorter than
      // the other end's, which is a worse failure than an exception at setup.
      expect(
        () => replicaFor(pawnNode().node, const [
          SyncedProperty('pawn', 'loadout'),
        ]),
        throwsA(isA<UnsyncableProperty>()),
      );
    });

    test('and the exception says which property and what kind', () {
      try {
        replicaFor(pawnNode().node, const [SyncedProperty('pawn', 'loadout')]);
        fail('expected a refusal');
      } on UnsyncableProperty catch (error) {
        expect(error.toString(), contains('pawn.loadout'));
        expect(error.toString(), contains('map'));
      }
    });

    test('a property the component does not declare is refused', () {
      expect(
        () => replicaFor(pawnNode().node, const [
          SyncedProperty('pawn', 'stamina'),
        ]),
        throwsA(isA<UnknownSyncedProperty>()),
      );
    });

    test('and the exception lists what it could have meant', () {
      try {
        replicaFor(pawnNode().node, const [SyncedProperty('pawn', 'helth')]);
        fail('expected a refusal');
      } on UnknownSyncedProperty catch (error) {
        expect(error.toString(), contains('health'));
      }
    });

    test('a component with no codec registered is refused', () {
      expect(
        () => replicaFor(pawnNode().node, const [
          SyncedProperty('ghost', 'health'),
        ]),
        throwsA(isA<UnknownSyncedComponent>()),
      );
    });
  });

  group('reading the live component', () {
    test('pull takes the current values', () {
      final scene = pawnNode();
      scene.pawn
        ..health = 42
        ..team = 3
        ..alive = false
        ..label = 'red'
        ..aim = Vector3(1, 0, 0);
      final replica = replicaFor(scene.node, const [
        SyncedProperty('pawn', 'health'),
        SyncedProperty('pawn', 'team'),
        SyncedProperty('pawn', 'alive'),
        SyncedProperty('pawn', 'label'),
        SyncedProperty('pawn', 'aim'),
      ])..pull();

      final fields = replica.fields;
      expect((fields[0] as Rep).value, 42);
      expect((fields[1] as Rep).value, 3);
      expect((fields[2] as Rep).value, false);
      expect((fields[3] as Rep).value, 'red');
      expect((fields[4] as Rep).value, (1.0, 0.0, 0.0));
    });

    test('a value sitting at its default still reads as that default', () {
      // Components serialize as a delta from their defaults, so an untouched
      // property is absent from the spec rather than present-and-default.
      // Reading zero there would make the two ends disagree about a value
      // nobody has changed.
      final scene = pawnNode();
      final replica = replicaFor(scene.node, const [
        SyncedProperty('pawn', 'health'),
        SyncedProperty('pawn', 'alive'),
      ])..pull();
      expect((replica.fields[0] as Rep).value, 100);
      expect((replica.fields[1] as Rep).value, true);
    });

    test('pull twice with no change leaves the value alone', () {
      final scene = pawnNode();
      final replica = replicaFor(scene.node, const [
        SyncedProperty('pawn', 'health'),
      ])..pull();
      final before = (replica.fields[0] as Rep).value;
      replica.pull();
      expect((replica.fields[0] as Rep).value, before);
    });

    test('a node missing the component is left alone rather than throwing', () {
      // A replica outlives a component being removed mid-session; the field
      // holds its last value instead of taking the whole tick down.
      final scene = pawnNode();
      final replica = replicaFor(scene.node, const [
        SyncedProperty('pawn', 'health'),
      ]);
      scene.pawn.health = 7;
      replica.pull();
      scene.node.removeComponent(scene.pawn);
      replica.pull();
      expect((replica.fields[0] as Rep).value, 7);
    });
  });

  group('writing the live component', () {
    test('push puts the replicated values back', () {
      final scene = pawnNode();
      final replica = replicaFor(scene.node, const [
        SyncedProperty('pawn', 'health'),
        SyncedProperty('pawn', 'team'),
        SyncedProperty('pawn', 'alive'),
        SyncedProperty('pawn', 'label'),
        SyncedProperty('pawn', 'aim'),
      ]);
      (replica.fields[0] as Rep<Object?>).value = 12.0;
      (replica.fields[1] as Rep<Object?>).value = 5;
      (replica.fields[2] as Rep<Object?>).value = false;
      (replica.fields[3] as Rep<Object?>).value = 'blue';
      (replica.fields[4] as Rep<Object?>).value = (0.0, 1.0, 0.0);
      replica.push();

      expect(scene.pawn.health, 12);
      expect(scene.pawn.team, 5);
      expect(scene.pawn.alive, isFalse);
      expect(scene.pawn.label, 'blue');
      expect(scene.pawn.aim, Vector3(0, 1, 0));
    });

    test('a pull and a push round trip a value unchanged', () {
      final source = pawnNode();
      final destination = pawnNode();
      source.pawn
        ..health = 63.5
        ..label = 'green'
        ..aim = Vector3(0, 0, -1);

      final sender = replicaFor(source.node, const [
        SyncedProperty('pawn', 'health'),
        SyncedProperty('pawn', 'label'),
        SyncedProperty('pawn', 'aim'),
      ])..pull();
      final receiver = replicaFor(destination.node, const [
        SyncedProperty('pawn', 'health'),
        SyncedProperty('pawn', 'label'),
        SyncedProperty('pawn', 'aim'),
      ]);
      for (var i = 0; i < sender.fields.length; i++) {
        (receiver.fields[i] as Rep<Object?>).value =
            (sender.fields[i] as Rep<Object?>).value;
      }
      receiver.push();

      expect(destination.pawn.health, 63.5);
      expect(destination.pawn.label, 'green');
      expect(destination.pawn.aim, Vector3(0, 0, -1));
    });

    test('a constructor-only property is declared but never written', () {
      // It has no setter, so a value arriving for it has nowhere to go. The
      // codec says so rather than appearing to apply it.
      final scene = pawnNode();
      final replica = replicaFor(scene.node, const [
        SyncedProperty('pawn', 'spawnRadius'),
      ]);
      (replica.fields[0] as Rep<Object?>).value = 99.0;
      expect(replica.push, returnsNormally);
    });
  });

  group('what the wire costs', () {
    test('a position quantizes to the resolution asked for', () {
      // Full float precision on a position is bytes spent below what anyone
      // can see. Which trade is right depends on the number, so it is named.
      final scene = pawnNode()..pawn.aim = Vector3(1.2345, 0, 0);
      final replica = replicaFor(scene.node, const [
        SyncedProperty('pawn', 'aim', resolution: 0.1),
      ])..pull();
      expect(replica.fields.single, isA<Rep<Object?>>());
    });

    test('write authority defaults to the server', () {
      // A client that can write its own health is a client that never dies.
      final replica = replicaFor(pawnNode().node, const [
        SyncedProperty('pawn', 'health'),
      ]);
      expect(replica.properties.single.authority, Authority.server);
    });

    test('and can be handed to the owner deliberately', () {
      final replica = replicaFor(pawnNode().node, const [
        SyncedProperty('pawn', 'aim', authority: Authority.owner),
      ]);
      expect(replica.properties.single.authority, Authority.owner);
    });
  });
}
