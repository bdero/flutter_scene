import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Pawn extends TransformReplica {
  _Pawn();

  @override
  String get typeKey => 'pawn';
}

ReplicaRegistry _registry() => ReplicaRegistry()..register(_Pawn.new);

Future<void> _pump([int rounds = 4]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
}

void main() {
  test('a room-replicated pose drives a scene node', () async {
    final room = Room(registry: _registry());
    final (clientEnd, serverEnd) = LoopbackConnection.pair();
    final admitted = room.admit(serverEnd);
    final session = await connectSession(
      clientEnd,
      schemaHash: _registry().schemaHash,
      pingInterval: const Duration(seconds: 10),
    );
    await admitted;

    final root = Node();
    final replication = SceneReplication(
      registry: _registry(),
      session: session,
      root: root,
      builders: {'pawn': (replica) => Node()},
      interpolationDelay: const Duration(milliseconds: 30),
    );

    final pawn = _Pawn();
    pawn.position.value = (1.0, 2.0, 3.0);
    final id = room.host.spawn(pawn);
    room.advance(1 / 30);
    await _pump();

    final node = replication.nodeFor(id);
    expect(node, isNotNull);
    expect(root.children, contains(node));
    // The spawn pose applies immediately.
    expect(node!.localTransform.getTranslation().x, closeTo(1, 0.01));

    pawn.position.value = (5.0, 2.0, 3.0);
    room.advance(1 / 30);
    await _pump();
    // Past the interpolation delay the buffer has settled on the new pose.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final transform = node.getComponent<NetworkTransformComponent>()!;
    transform.update(1 / 60);
    final translation = node.localTransform.getTranslation();
    expect(translation.x, closeTo(5, 0.01));
    expect(translation.y, closeTo(2, 0.01));
    expect(translation.z, closeTo(3, 0.01));

    room.host.despawn(id);
    room.advance(1 / 30);
    await _pump();
    expect(replication.nodeFor(id), isNull);
    expect(root.children, isEmpty);

    await replication.close();
    await room.stop();
  });

  test('SceneHost serves loopback and WebSocket joiners', () async {
    final room = Room(registry: _registry());
    final host = await SceneHost.start(room: room);
    room.host.spawn(_Pawn()..position.value = (7.0, 0.0, 0.0));

    final localSession = await connectSession(
      await host.connectLocal(),
      schemaHash: _registry().schemaHash,
    );
    final remoteSession = await connectSession(
      await connectWebSocket(Uri.parse('ws://127.0.0.1:${host.port}')),
      schemaHash: _registry().schemaHash,
    );
    final local = ReplicationClient(
      registry: _registry(),
      session: localSession,
    );
    final remote = ReplicationClient(
      registry: _registry(),
      session: remoteSession,
    );

    final sw = Stopwatch()..start();
    while ((local.replicas.isEmpty || remote.replicas.isEmpty) &&
        sw.elapsedMilliseconds < 3000) {
      await _pump(1);
    }
    expect(local.replicas.values.single, isA<_Pawn>());
    expect(remote.replicas.values.single, isA<_Pawn>());

    await localSession.close();
    await remoteSession.close();
    await host.stop();
  });

  test('interpolation samples between pushed poses', () async {
    final pawn = _Pawn();
    final component = NetworkTransformComponent(pawn);
    final start = defaultNowMicros();
    pawn.position.value = (0.0, 0.0, 0.0);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    pawn.position.value = (10.0, 0.0, 0.0);
    final end = defaultNowMicros();

    final (mid, _) = component.sampleAt((start + end) ~/ 2);
    expect(mid.x, greaterThan(0.5));
    expect(mid.x, lessThan(9.5));
    final (late_, _) = component.sampleAt(end + 1000);
    expect(late_.x, 10);
  });
}
