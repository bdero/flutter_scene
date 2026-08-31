// Rewinding between ticks. A client renders between two server ticks, so
// rewinding to the nearer one puts a target up to half a tick from where the
// shooter saw it -- at 30Hz and a running speed, most of a body width.

import 'dart:typed_data';

import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// One body moving along X, plus a rotation nothing else touches.
final class _Sim extends PhysicsSimulation {
  double x = 0;
  double v = 0;
  vm.Quaternion rotation = vm.Quaternion.identity();

  @override
  String get backendName => 'lag1d';

  @override
  bool get supportsSnapshot => true;

  @override
  Uint8List snapshot() => Float64List.fromList([
    x,
    v,
    rotation.x,
    rotation.y,
    rotation.z,
    rotation.w,
  ]).buffer.asUint8List().sublist(0);

  @override
  bool restore(Uint8List snapshot) {
    final d = Uint8List.fromList(snapshot).buffer.asFloat64List();
    x = d[0];
    v = d[1];
    rotation = vm.Quaternion(d[2], d[3], d[4], d[5]);
    return true;
  }

  @override
  void step(double fixedDt) => x += v * fixedDt;

  @override
  void setBodyPose(int h, vm.Vector3 translation, vm.Quaternion r) {
    x = translation.x;
    rotation = r.clone();
  }

  @override
  (vm.Vector3, vm.Quaternion) readBodyPose(int h) =>
      (vm.Vector3(x, 0, 0), rotation.clone());

  @override
  vm.Vector3 readBodyLinearVelocity(int h) => vm.Vector3(v, 0, 0);

  @override
  vm.Vector3 readBodyAngularVelocity(int h) => vm.Vector3.zero();

  @override
  void setBodyLinearVelocity(int h, vm.Vector3 velocity) => v = velocity.x;

  @override
  void setBodyAngularVelocity(int h, vm.Vector3 velocity) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  ({_Sim sim, PhysicsWorldHistory history}) recorded({
    List<int> tracked = const [0],
    int ticks = 6,
  }) {
    final sim = _Sim()..v = 1;
    final history = PhysicsWorldHistory(sim, tracked: tracked);
    for (var tick = 1; tick <= ticks; tick++) {
      sim.step(1);
      history.record(tick);
    }
    return (sim: sim, history: history);
  }

  group('landing between two ticks', () {
    test('halfway is halfway', () {
      // The whole point: the target is where the shooter saw it, not where it
      // happened to be on the nearest tick.
      final r = recorded();
      final out = r.history.rewindBetween(3, 0.5, (s) => (s as _Sim).x);
      expect(out.rewound, isTrue);
      expect(out.result, closeTo(3.5, 1e-5));
    });

    test('zero is the earlier tick and one is the later', () {
      final r = recorded();
      expect(
        r.history.rewindBetween(3, 0, (s) => (s as _Sim).x).result,
        closeTo(3, 1e-5),
      );
      expect(
        r.history.rewindBetween(3, 1, (s) => (s as _Sim).x).result,
        closeTo(4, 1e-5),
      );
    });

    test('a fraction outside the interval is clamped, not extrapolated', () {
      // Extrapolating would put a target somewhere neither end of the
      // interval says it was, which is a hit registered against nothing.
      final r = recorded();
      expect(
        r.history.rewindBetween(3, 5, (s) => (s as _Sim).x).result,
        closeTo(4, 1e-5),
      );
      expect(
        r.history.rewindBetween(3, -5, (s) => (s as _Sim).x).result,
        closeTo(3, 1e-5),
      );
    });

    test('the present is restored afterwards', () {
      final r = recorded();
      r.history.rewindBetween(3, 0.5, (s) => null);
      expect(r.sim.x, 6);
      expect(r.sim.v, 1);
    });

    test('the world is the earlier tick, only tracked bodies move', () {
      // The trade lag compensation makes everywhere: the targets are
      // reconstructed exactly and the rest to the nearest tick.
      final r = recorded();
      final seen = r.history.rewindBetween(3, 0.5, (s) => (s as _Sim).v);
      expect(seen.result, 1, reason: 'the world is tick 3, not blended');
    });
  });

  group('when it cannot', () {
    test('an interval past the retained window reports itself', () {
      // Distinguishable from a query that legitimately found nothing.
      final r = recorded();
      expect(r.history.rewindBetween(99, 0.5, (s) => 0).rewound, isFalse);
    });

    test('the newest tick has no tick after it', () {
      final r = recorded();
      expect(r.history.rewindBetween(6, 0.5, (s) => 0).rewound, isFalse);
    });

    test('but landing exactly on the newest tick still works', () {
      // Asking for a whole tick through this door should not fail merely
      // because the tick after it has not happened yet.
      final r = recorded();
      final out = r.history.rewindBetween(6, 0, (s) => (s as _Sim).x);
      expect(out.rewound, isTrue);
      expect(out.result, closeTo(6, 1e-5));
    });

    test('tracking nothing is refused rather than silently exact', () {
      // There is nothing to interpolate, and answering as though there were
      // would hide that the caller never named the bodies it cares about.
      final r = recorded(tracked: const []);
      expect(r.history.rewindBetween(3, 0.5, (s) => 0).rewound, isFalse);
      // The whole-tick rewind still works without tracking.
      expect(r.history.rewind(3, (s) => 0).rewound, isTrue);
    });
  });

  group('rotations', () {
    test('blend the short way round', () {
      // Two orientations either side of half a turn would otherwise blend the
      // long way and face a target backwards at the moment it is shot at.
      final sim = _Sim();
      final history = PhysicsWorldHistory(sim, tracked: const [0]);

      final near = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 3.0);
      // The same rotation written with every component negated, which is what
      // a solver hands back either side of the double cover.
      final far = vm.Quaternion(-near.x, -near.y, -near.z, -near.w);

      sim.rotation = near;
      history.record(1);
      sim.rotation = far;
      history.record(2);

      final blended = history
          .rewindBetween(1, 0.5, (s) => (s as _Sim).rotation.clone())
          .result!;
      // The two ends are the same orientation, so every point between them
      // must be too.
      final dot =
          blended.x * near.x +
          blended.y * near.y +
          blended.z * near.z +
          blended.w * near.w;
      expect(dot.abs(), closeTo(1, 1e-4));
    });

    test('stay unit length', () {
      final sim = _Sim();
      final history = PhysicsWorldHistory(sim, tracked: const [0]);
      sim.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.2);
      history.record(1);
      sim.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 1.4);
      history.record(2);

      final blended = history
          .rewindBetween(1, 0.5, (s) => (s as _Sim).rotation.clone())
          .result!;
      expect(blended.length, closeTo(1, 1e-5));
    });
  });
}
