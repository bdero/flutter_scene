// Starting a session and letting people into it. The decisions here are the
// ones a NetworkManager makes, and none of them need a socket to be true.

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
  late FsceneComponentRegistry components;
  late Node root;

  setUp(() {
    components = FsceneComponentRegistry()..register(_PawnCodec());
    root = Node(name: 'scene');
  });

  NetworkPrefabs table({List<String> types = const ['player']}) =>
      NetworkPrefabs(
        prefabs: [
          for (final type in types)
            NetworkPrefab(
              typeKey: type,
              synced: const [SyncedProperty('pawn', 'health')],
              build: () {
                final node = Node(name: type)..addComponent(_Pawn());
                root.add(node);
                return node;
              },
            ),
        ],
        registry: components,
      );

  NetworkSession session({
    NetworkRole role = NetworkRole.host,
    ConnectionApprover? approve,
    List<String> types = const ['player'],
  }) => NetworkSession(
    role: role,
    prefabs: table(types: types),
    playerPrefab: 'player',
    approve: approve,
  );

  group('roles', () {
    test('a host simulates and plays; a server only simulates', () {
      expect(NetworkRole.host.isAuthority, isTrue);
      expect(NetworkRole.host.hasLocalPlayer, isTrue);
      expect(NetworkRole.server.isAuthority, isTrue);
      expect(NetworkRole.server.hasLocalPlayer, isFalse);
    });

    test('a client believes what it is told', () {
      expect(NetworkRole.client.isAuthority, isFalse);
      expect(NetworkRole.client.hasLocalPlayer, isTrue);
    });
  });

  group('starting', () {
    test('a session is not running until it is started', () {
      final s = session();
      expect(s.isRunning, isFalse);
      s.start();
      expect(s.isRunning, isTrue);
    });

    test('starting twice is refused', () {
      // Two sessions in one process would both claim to be authoritative, and
      // the scene can only be one of them.
      final s = session()..start();
      expect(s.start, throwsA(isA<SessionAlreadyRunning>()));
    });

    test('a player prefab that is not in the table is refused up front', () {
      // Letting someone in and having nothing to give them is a worse failure,
      // and it happens to the player rather than to the developer.
      expect(
        () => NetworkSession(
          role: NetworkRole.host,
          prefabs: table(),
          playerPrefab: 'ghost',
        ),
        throwsA(isA<UnknownPlayerPrefab>()),
      );
    });

    test('and the refusal says what the table does hold', () {
      try {
        NetworkSession(
          role: NetworkRole.host,
          prefabs: table(),
          playerPrefab: 'ghost',
        );
        fail('expected a refusal');
      } on UnknownPlayerPrefab catch (error) {
        expect(error.toString(), contains('player'));
      }
    });
  });

  group('approval', () {
    test('no approver means an open session', () async {
      final s = session()..start();
      expect((await s.vet('')).approved, isTrue);
    });

    test('the game gets whatever the joiner presented', () async {
      String? seen;
      final s = session(
        approve: (payload) {
          seen = payload;
          return const ConnectionApproval.approve();
        },
      )..start();
      await s.vet('build=42');
      expect(seen, 'build=42');
    });

    test('a refusal carries a reason', () async {
      // "Could not connect" is the least useful sentence in multiplayer.
      final s = session(
        approve: (_) => const ConnectionApproval.reject('Wrong build'),
      )..start();
      final decision = await s.vet('');
      expect(decision.approved, isFalse);
      expect(decision.reason, 'Wrong build');
    });

    test('a client does not get to decide who joins', () async {
      final s = session(role: NetworkRole.client)..start();
      final decision = await s.vet('');
      expect(decision.approved, isFalse);
      expect(decision.reason, contains('server'));
    });

    test('a session that is not running admits nobody', () async {
      final decision = await session().vet('');
      expect(decision.approved, isFalse);
    });

    test('an async approver is awaited', () async {
      // Checking a ticket means asking a service, which takes time.
      final s = session(
        approve: (_) async => const ConnectionApproval.reject('Banned'),
      )..start();
      expect((await s.vet('')).reason, 'Banned');
    });
  });

  group('admitting', () {
    test('an approved peer gets a player, owned by them', () {
      final s = session()..start();
      final client = s.admit(7, const ConnectionApproval.approve())!;
      expect(client.peerId, 7);
      expect(client.player, isNotNull);
      expect(client.replica!.owner, 7);
      expect(root.children, hasLength(1));
    });

    test('a refusal spawns nothing', () {
      final s = session()..start();
      expect(s.admit(7, const ConnectionApproval.reject('no')), isNull);
      expect(s.clients, isEmpty);
      expect(root.children, isEmpty);
    });

    test('a spectator is connected and given nothing to drive', () {
      final s = session()..start();
      final client = s.admit(
        7,
        const ConnectionApproval.approve(spawnPlayer: false),
      )!;
      expect(client.player, isNull);
      expect(s.peerIds, [7]);
      expect(root.children, isEmpty);
    });

    test('the approval may choose a different prefab', () {
      final s = NetworkSession(
        role: NetworkRole.host,
        prefabs: table(types: ['player', 'spectatorCam']),
        playerPrefab: 'player',
      )..start();
      final client = s.admit(
        7,
        const ConnectionApproval.approve(playerType: 'spectatorCam'),
      )!;
      expect(client.player!.name, 'spectatorCam');
    });

    test('a prefab the approval names but the table lacks is refused', () {
      final s = session()..start();
      expect(
        () => s.admit(7, const ConnectionApproval.approve(playerType: 'ghost')),
        throwsA(isA<UnknownPlayerPrefab>()),
      );
    });

    test('admitting the same peer twice does not give them two bodies', () {
      // A reconnect that raced the drop, or a duplicated message.
      final s = session()..start();
      final first = s.admit(7, const ConnectionApproval.approve());
      final second = s.admit(7, const ConnectionApproval.approve());
      expect(identical(first, second), isTrue);
      expect(root.children, hasLength(1));
    });

    test('the spawn hook fires with the client', () {
      final s = session()..start();
      NetworkClient? seen;
      s.onPlayerSpawned = (client) => seen = client;
      s.admit(7, const ConnectionApproval.approve());
      expect(seen?.peerId, 7);
    });
  });

  group('leaving', () {
    test('dropping takes the body with it', () {
      // A player that left and whose body stayed is the bug people report as
      // ghosts.
      final s = session()..start();
      s.admit(7, const ConnectionApproval.approve());
      s.drop(7);
      expect(s.clients, isEmpty);
      expect(root.children, isEmpty);
    });

    test('and unbinds the replica so it stops reading a detached node', () {
      final s = session()..start();
      final client = s.admit(7, const ConnectionApproval.approve())!;
      s.drop(7);
      expect(client.replica!.node, isNull);
    });

    test('the despawn hook fires before the body goes', () {
      final s = session()..start();
      Node? seen;
      s.onPlayerDespawned = (client) => seen = client.player;
      s.admit(7, const ConnectionApproval.approve());
      s.drop(7);
      expect(seen, isNotNull);
    });

    test('dropping someone who is not here does nothing', () {
      final s = session()..start();
      expect(() => s.drop(99), returnsNormally);
    });

    test('stopping drops everyone, including the host', () {
      // Leaving a body behind would leave a node nothing owns and no snapshot
      // will ever update again.
      final s = session()..start();
      s.admit(1, const ConnectionApproval.approve());
      s.admit(2, const ConnectionApproval.approve());
      s.stop();
      expect(s.isRunning, isFalse);
      expect(s.clients, isEmpty);
      expect(root.children, isEmpty);
    });

    test('a stopped session can be started again', () {
      final s = session()..start();
      s.stop();
      expect(s.start, returnsNormally);
    });
  });
}
