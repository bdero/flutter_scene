// Naming a replica in a document. A replica belongs to a running session
// rather than to a file, so the document names a slot and the app says what
// each name means -- otherwise a scene carrying a networked node cannot be
// loaded at all.

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Pawn extends TransformReplica {
  @override
  String get typeKey => 'pawn';
}

void main() {
  late FsceneComponentRegistry registry;
  final document = SceneDocument();

  setUp(() {
    registry = FsceneComponentRegistry();
    registerNetComponentCodecs(registry);
  });

  tearDown(ReplicaSlots.clear);

  Component? realize(Map<String, PropertyValue> properties) => registry
      .codecFor('networkTransform')!
      .realize(
        ComponentSpec('networkTransform', properties: properties),
        RealizeContext(document),
      );

  group('resolving', () {
    test('nothing is registered until an app says so', () {
      expect(ReplicaSlots.hasResolver, isFalse);
      expect(ReplicaSlots.resolve('player'), isNull);
    });

    test('a registered resolver answers by name', () {
      final pawn = _Pawn();
      ReplicaSlots.resolveWith((slot) => slot == 'player' ? pawn : null);
      expect(ReplicaSlots.resolve('player'), same(pawn));
      expect(ReplicaSlots.resolve('turret'), isNull);
    });

    test('an empty slot resolves to nothing without asking', () {
      // Naming no slot is different from naming one nobody supplies, and the
      // resolver should not have to tell them apart.
      var asked = 0;
      ReplicaSlots.resolveWith((slot) {
        asked++;
        return null;
      });
      expect(ReplicaSlots.resolve(''), isNull);
      expect(asked, 0);
    });

    test('clearing forgets it', () {
      // A resolver left over from one test answering another test's lookups
      // is the kind of failure that only appears in a particular order.
      ReplicaSlots.resolveWith((_) => _Pawn());
      ReplicaSlots.clear();
      expect(ReplicaSlots.hasResolver, isFalse);
    });
  });

  group('realizing from a document', () {
    test('a named slot with a replica drives the node', () {
      final pawn = _Pawn();
      ReplicaSlots.resolveWith((slot) => slot == 'player' ? pawn : null);

      final component = realize({'slot': const StringValue('player')});
      expect(component, isA<NetworkTransformComponent>());
      expect((component! as NetworkTransformComponent).replica, same(pawn));
    });

    test('and carries the delay the document asked for', () {
      ReplicaSlots.resolveWith((_) => _Pawn());
      final component =
          realize({
                'slot': const StringValue('player'),
                'delayMilliseconds': const IntValue(40),
              })!
              as NetworkTransformComponent;
      expect(component.delay, const Duration(milliseconds: 40));
    });

    test('a slot nobody supplies leaves the node undriven, not broken', () {
      // A scene can be loaded before the session that fills it exists. That
      // is not an error, and failing the load over it would make a networked
      // scene unopenable offline.
      ReplicaSlots.resolveWith((_) => null);
      expect(realize({'slot': const StringValue('player')}), isNull);
    });

    test('and so does a document that names no slot at all', () {
      expect(realize(const {}), isNull);
    });

    test('with no resolver registered, loading still succeeds', () {
      expect(
        () => realize({'slot': const StringValue('player')}),
        returnsNormally,
      );
    });
  });

  group('serializing', () {
    Map<String, PropertyValue>? serialize(Component component) => registry
        .codecFor('networkTransform')!
        .serialize(component, SerializeContext(document))
        ?.properties;

    test('a component realized from a slot writes that slot back', () {
      ReplicaSlots.resolveWith((_) => _Pawn());
      final component =
          realize({'slot': const StringValue('player')})!
              as NetworkTransformComponent;
      final written = serialize(component)!['slot']! as StringValue;
      expect(written.value, 'player');
    });

    test('one built in code writes no slot', () {
      // It has no name to write, and inventing one would put a slot in the
      // document that nobody registered -- reported as missing on next load.
      final component = NetworkTransformComponent(_Pawn());
      expect(serialize(component)?.containsKey('slot'), isFalse);
    });

    test('a default delay is not written', () {
      final component = NetworkTransformComponent(_Pawn());
      expect(serialize(component), isEmpty);
    });

    test('it round trips through the document', () {
      final pawn = _Pawn();
      ReplicaSlots.resolveWith((_) => pawn);
      final first =
          realize({
                'slot': const StringValue('player'),
                'delayMilliseconds': const IntValue(25),
              })!
              as NetworkTransformComponent;
      final second = realize(serialize(first)!)! as NetworkTransformComponent;
      expect(second.slot, 'player');
      expect(second.delay, const Duration(milliseconds: 25));
      expect(second.replica, same(pawn));
    });
  });
}
