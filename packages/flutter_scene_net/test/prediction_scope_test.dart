// Bounding what a retained prediction tick costs. A rollback rewinds and
// replays, so a tick has to keep everything the replay can read: the whole
// serialized world is always enough and always costs the whole world.
// Declaring the bodies that can matter bounds it by the set instead.

import 'dart:typed_data';

import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A simulation of independent 1D bodies, counting what is asked of it.
final class _Sim extends PhysicsSimulation {
  final List<double> x = [0, 0, 0];
  final List<double> v = [0, 0, 0];

  int snapshots = 0;
  int restores = 0;

  @override
  String get backendName => 'bodies1d';

  @override
  bool get supportsSnapshot => true;

  @override
  Uint8List snapshot() {
    snapshots++;
    return Float64List.fromList([...x, ...v]).buffer.asUint8List().sublist(0);
  }

  @override
  bool restore(Uint8List snapshot) {
    restores++;
    final data = Uint8List.fromList(snapshot).buffer.asFloat64List();
    for (var i = 0; i < x.length; i++) {
      x[i] = data[i];
      v[i] = data[x.length + i];
    }
    return true;
  }

  @override
  void step(double fixedDt) {
    for (var i = 0; i < x.length; i++) {
      x[i] += v[i] * fixedDt;
    }
  }

  @override
  void setBodyPose(int h, vm.Vector3 translation, vm.Quaternion rotation) =>
      x[h] = translation.x;

  @override
  (vm.Vector3, vm.Quaternion) readBodyPose(int h) =>
      (vm.Vector3(x[h], 0, 0), vm.Quaternion.identity());

  @override
  vm.Vector3 readBodyLinearVelocity(int h) => vm.Vector3(v[h], 0, 0);

  @override
  vm.Vector3 readBodyAngularVelocity(int h) => vm.Vector3.zero();

  @override
  void setBodyLinearVelocity(int h, vm.Vector3 velocity) => v[h] = velocity.x;

  @override
  void setBodyAngularVelocity(int h, vm.Vector3 velocity) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A controller that keeps the whole world, the way one always has.
class _WorldController implements PredictedPhysicsController {
  _WorldController(this.simulation);

  @override
  final _Sim simulation;

  @override
  int get bodyHandle => 0;

  @override
  void onWorldRestored() {}

  @override
  Uint8List sampleInput() => Uint8List(0);

  @override
  void applyInput(Uint8List input, double dt) {}

  @override
  vm.Vector3? get authoritativeLinearVelocity => null;

  @override
  vm.Vector3? get authoritativeAngularVelocity => null;
}

/// The same, opting into a declared set.
class _ScopedController extends _WorldController implements PredictedBodyScope {
  _ScopedController(super.simulation, this.predictedBodies);

  @override
  List<int> predictedBodies;
}

void main() {
  group('what a controller declares', () {
    test('a plain controller is not scoped', () {
      // Opting in is implementing an extra interface, so nothing that exists
      // today changes behaviour by upgrading.
      expect(_WorldController(_Sim()), isNot(isA<PredictedBodyScope>()));
    });

    test('a scoped one is', () {
      expect(_ScopedController(_Sim(), const [0]), isA<PredictedBodyScope>());
    });
  });

  group('the declared set carries what a replay needs', () {
    test('pose and both velocities survive a round trip', () {
      // Thirteen floats a body: if any of them is dropped, a rollback puts
      // the world back subtly wrong and the correction never converges.
      final sim = _Sim();
      final scope = _ScopedController(sim, const [0, 1]);

      sim
        ..setBodyPose(0, vm.Vector3(3, 0, 0), vm.Quaternion.identity())
        ..setBodyLinearVelocity(0, vm.Vector3(7, 0, 0))
        ..setBodyPose(1, vm.Vector3(-2, 0, 0), vm.Quaternion.identity())
        ..setBodyLinearVelocity(1, vm.Vector3(4, 0, 0));

      final captured = capturePredictedBodies(sim, scope.predictedBodies);

      // Move everything, then put it back.
      sim
        ..setBodyPose(0, vm.Vector3(99, 0, 0), vm.Quaternion.identity())
        ..setBodyLinearVelocity(0, vm.Vector3(0, 0, 0))
        ..setBodyPose(1, vm.Vector3(99, 0, 0), vm.Quaternion.identity())
        ..setBodyLinearVelocity(1, vm.Vector3(0, 0, 0));
      restorePredictedBodies(sim, scope.predictedBodies, captured);

      expect(sim.x[0], 3);
      expect(sim.v[0], 7);
      expect(sim.x[1], -2);
      expect(sim.v[1], 4);
    });

    test('a body outside the set is not restored', () {
      // The whole bargain, stated: what you leave out stays where the replay
      // left it, which is why the set has to be closed under interaction.
      final sim = _Sim();
      final scope = _ScopedController(sim, const [0]);
      sim.setBodyPose(1, vm.Vector3(5, 0, 0), vm.Quaternion.identity());

      final captured = capturePredictedBodies(sim, scope.predictedBodies);
      sim.setBodyPose(1, vm.Vector3(50, 0, 0), vm.Quaternion.identity());
      restorePredictedBodies(sim, scope.predictedBodies, captured);

      expect(sim.x[1], 50, reason: 'untouched, not rewound');
    });

    test('it costs the set, not the world', () {
      // The point of the whole thing: a retained tick is thirteen floats a
      // body rather than a serialization of everything.
      final sim = _Sim();
      final scope = _ScopedController(sim, const [0]);
      final captured = capturePredictedBodies(sim, scope.predictedBodies);
      expect(captured.length, floatsPerPredictedBody);
      expect(sim.snapshots, 0, reason: 'the world was never serialized');
    });

    test('a set that changed underneath a retained tick is refused', () {
      // Restoring what both agree on and leaving the rest is a divergence the
      // correction cannot fix, so it is better found here than in a game.
      final sim = _Sim();
      final scope = _ScopedController(sim, [0, 1]);
      final captured = capturePredictedBodies(sim, scope.predictedBodies);
      scope.predictedBodies = [0];
      expect(
        () => restorePredictedBodies(sim, scope.predictedBodies, captured),
        throwsA(isA<StateError>()),
      );
    });
  });
}
