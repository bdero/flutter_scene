import 'dart:typed_data';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

final class _Pawn extends TransformReplica {
  _Pawn();

  @override
  String get typeKey => 'pawn';
}

ReplicaRegistry _registry() => ReplicaRegistry()..register(_Pawn.new);

// A trivial 1D controller, hold a constant +X velocity, integrated the same
// way on the server so prediction converges.
const double _testSpeed = 5;

Uint8List _encodeVel(double v) => (ByteWriter(4)..writeF32(v)).toBytes();
double _decodeVel(Uint8List b) => ByteReader(b).readF32();

class _ConstantController implements PredictedController {
  @override
  Uint8List sampleInput() => _encodeVel(1);

  @override
  (vm.Vector3, vm.Quaternion) step(
    vm.Vector3 position,
    vm.Quaternion rotation,
    Uint8List input,
    double dt,
  ) => (
    vm.Vector3(position.x + _decodeVel(input) * _testSpeed * dt, 0, 0),
    rotation,
  );
}

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

  test('resuming after an idle gap eases in instead of snapping', () {
    var nowMicros = 1000000;
    final pawn = _Pawn()..position.value = (0.0, 0.0, 0.0);
    final component = NetworkTransformComponent(
      pawn,
      delay: const Duration(milliseconds: 100),
      now: () => nowMicros,
    );

    // Sit idle well past the delay, then start moving.
    nowMicros += 2000000;
    pawn.position.value = (10.0, 0.0, 0.0);

    // Without re-anchoring this would snap toward 10; the held pose is
    // anchored at now - delay, so the resume still renders near the origin.
    final (atResume, _) = component.sampleAt(nowMicros - 100000);
    expect(atResume.x, closeTo(0, 0.01));
    // Halfway through the delay it has eased about halfway in.
    final (mid, _) = component.sampleAt(nowMicros - 50000);
    expect(mid.x, greaterThan(2));
    expect(mid.x, lessThan(8));
  });

  test('an owned player is predicted from local input and converges', () async {
    const tickRate = 30;
    const dt = 1 / tickRate;

    late final Room room;
    final players = <int, _Pawn>{};
    room = Room(
      registry: _registry(),
      tickRate: tickRate,
      onJoin: (session) {
        final pawn = _Pawn();
        room.host.spawn(pawn, owner: session.peerId);
        players[session.peerId] = pawn;
      },
      onTick: (tick) {
        for (final entry in players.entries) {
          final command = room.input(entry.key, tick);
          final vx = command == null ? 0.0 : _decodeVel(command);
          final (x, _, _) = entry.value.position.value;
          entry.value.position.value = (x + vx * _testSpeed * dt, 0, 0);
        }
      },
    );

    final (clientEnd, serverEnd) = LoopbackConnection.pair();
    final admitted = room.admit(serverEnd);
    final session = await connectSession(
      clientEnd,
      schemaHash: _registry().schemaHash,
      pingInterval: const Duration(milliseconds: 20),
    );
    await admitted;

    final replication = SceneReplication(
      registry: _registry(),
      session: session,
      root: Node(),
      builders: {'pawn': (replica) => Node()},
      localPrediction: (replica) => _ConstantController(),
    );

    final sw = Stopwatch()..start();
    while (replication.replicas.isEmpty && sw.elapsedMilliseconds < 2000) {
      room.advance(dt);
      await _pump(1);
    }
    final pawn = replication.replicas.whereType<_Pawn>().first;
    final component = replication
        .nodeFor(pawn.id!)!
        .getComponent<PredictedTransformComponent>()!;

    // Drive the client render loop and the server tick over real time.
    final run = Stopwatch()..start();
    while (run.elapsedMilliseconds < 800) {
      component.update(1 / 60);
      room.advance(dt);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    final predictedX = replication
        .nodeFor(pawn.id!)!
        .localTransform
        .getTranslation()
        .x;
    // Local input moved the predicted node right immediately, not stuck at 0.
    expect(predictedX, greaterThan(1));
    // And it stays near the server's authoritative position (reconciled), the
    // prediction leads by roughly the send-ahead, never diverging.
    expect((predictedX - pawn.position.value.$1).abs(), lessThan(3));

    await replication.close();
    await room.stop();
  });
}
