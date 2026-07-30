import 'dart:typed_data';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/physics.dart';
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

const double _speed = 5;

Uint8List _encodeVel(double v) => (ByteWriter(4)..writeF32(v)).toBytes();
double _decodeVel(Uint8List b) => ByteReader(b).readF32();

/// A 1D world, one body with position x and velocity v, snapshot-round-trip
/// through two doubles. Deterministic stand-in for a physics backend.
final class _FakeSim extends PhysicsSimulation {
  double x = 0;
  double v = 0;

  @override
  String get backendName => 'fake1d';

  @override
  bool get supportsSnapshot => true;

  @override
  Uint8List snapshot() =>
      Float64List.fromList([x, v]).buffer.asUint8List().sublist(0);

  @override
  bool restore(Uint8List snapshot) {
    final data = Uint8List.fromList(snapshot).buffer.asFloat64List();
    x = data[0];
    v = data[1];
    return true;
  }

  @override
  void step(double fixedDt) => x += v * fixedDt;

  @override
  void setBodyPose(
    int bodyHandle,
    vm.Vector3 translation,
    vm.Quaternion rotation,
  ) => x = translation.x;

  @override
  (vm.Vector3, vm.Quaternion) readBodyPose(int bodyHandle) =>
      (vm.Vector3(x, 0, 0), vm.Quaternion.identity());

  @override
  vm.Vector3 readBodyLinearVelocity(int bodyHandle) => vm.Vector3(v, 0, 0);

  @override
  vm.Vector3 readBodyAngularVelocity(int bodyHandle) => vm.Vector3.zero();

  @override
  void setBodyLinearVelocity(int bodyHandle, vm.Vector3 velocity) =>
      v = velocity.x;

  @override
  void setBodyAngularVelocity(int bodyHandle, vm.Vector3 velocity) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeController implements PredictedPhysicsController {
  _FakeController(this.simulation);

  @override
  final _FakeSim simulation;

  @override
  int get bodyHandle => 0;

  @override
  Uint8List sampleInput() => _encodeVel(1);

  @override
  void applyInput(Uint8List input, double dt) => simulation
      .setBodyLinearVelocity(0, vm.Vector3(_decodeVel(input) * _speed, 0, 0));

  @override
  vm.Vector3? get authoritativeLinearVelocity => null;

  @override
  vm.Vector3? get authoritativeAngularVelocity => null;
}

Future<void> _pump([int rounds = 4]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
}

void main() {
  test(
    'an owned physics body is predicted and survives a server shove',
    () async {
      const tickRate = 30;
      const dt = 1 / tickRate;

      // The server runs the same 1D integration the fake sim predicts with,
      // plus one displacement the client cannot predict (a collision stand-in).
      late final Room room;
      final players = <int, _Pawn>{};
      final serverX = <int, double>{};
      var consumedTicks = 0;
      var shoved = false;
      room = Room(
        registry: _registry(),
        tickRate: tickRate,
        onJoin: (session) {
          final pawn = _Pawn();
          room.host.spawn(pawn, owner: session.peerId);
          players[session.peerId] = pawn;
          serverX[session.peerId] = 0;
        },
        onTick: (tick) {
          for (final entry in players.entries) {
            final command = room.input(entry.key, tick);
            if (command == null) continue;
            consumedTicks++;
            var x = serverX[entry.key]! + _decodeVel(command) * _speed * dt;
            if (consumedTicks == 10 && !shoved) {
              shoved = true;
              x += 3;
            }
            serverX[entry.key] = x;
            entry.value.position.value = (x, 0.0, 0.0);
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
        localPrediction: (replica) => _FakeController(_FakeSim()),
      );

      final sw = Stopwatch()..start();
      while (replication.replicas.isEmpty && sw.elapsedMilliseconds < 2000) {
        room.advance(dt);
        await _pump(1);
      }
      final pawn = replication.replicas.whereType<_Pawn>().first;
      final component = replication
          .nodeFor(pawn.id!)!
          .getComponent<PredictedPhysicsComponent>()!;

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
      // Local input moved the predicted body right immediately.
      expect(predictedX, greaterThan(1));
      // The unpredictable shove happened and the rollback correction adopted
      // it; the prediction tracks authority within the send-ahead lead.
      expect(shoved, isTrue);
      expect((predictedX - pawn.position.value.$1).abs(), lessThan(3));

      await replication.close();
      await room.stop();
    },
  );

  test('world history rewinds a query and restores the present', () {
    final sim = _FakeSim()..v = 1;
    final history = PhysicsWorldHistory(sim, maxRewindTicks: 8);

    for (var tick = 1; tick <= 12; tick++) {
      sim.step(1);
      history.record(tick);
    }
    expect(sim.x, 12);
    expect(history.depth, 9); // ticks 4..12 retained

    final rewound = history.rewind(9, (s) => (s as _FakeSim).x);
    expect(rewound, 9);
    expect(sim.x, 12); // present restored
    expect(sim.v, 1);

    expect(history.rewind(3, (s) => 0), isNull); // beyond the cap
    expect(history.rewind(99, (s) => 0), isNull); // never recorded
  });
}
