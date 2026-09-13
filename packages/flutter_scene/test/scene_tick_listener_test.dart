// Covers SceneTickListener dispatch: order, idempotent registration, mutation
// during dispatch, and running ahead of every fixed step. Scene itself needs a
// GPU context, so the registry it delegates to is exercised directly, with
// Scene.advancePhysics standing in for the fixed-step loop.

import 'package:flutter_scene/physics.dart' show PhysicsWorld;
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/scene_tick_listener.dart';
import 'package:flutter_test/flutter_test.dart';

import 'physics_test.dart' show FakeSimulation;

class _Recorder extends SceneTickListener {
  _Recorder(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  void beforeTick(double deltaSeconds) => log.add('$name tick $deltaSeconds');

  @override
  void beforeFixedStep(double fixedDt) => log.add('$name step $fixedDt');
}

void main() {
  test('listeners run in the order added', () {
    final log = <String>[];
    final listeners = SceneTickListeners()
      ..add(_Recorder('a', log))
      ..add(_Recorder('b', log));
    listeners.beforeTick(0.5);
    expect(log, ['a tick 0.5', 'b tick 0.5']);
  });

  test('adding twice registers once and removal reports presence', () {
    final log = <String>[];
    final listener = _Recorder('a', log);
    final listeners = SceneTickListeners();
    expect(listeners.add(listener), isTrue);
    expect(listeners.add(listener), isFalse);
    listeners.beforeTick(1);
    expect(log, hasLength(1));
    expect(listeners.remove(listener), isTrue);
    expect(listeners.remove(listener), isFalse);
    listeners.beforeTick(1);
    expect(log, hasLength(1));
  });

  test('a listener may change the registry during dispatch', () {
    final log = <String>[];
    final listeners = SceneTickListeners();
    final late = _Recorder('late', log);
    late final _Recorder first;
    first = _SelfRemoving(
      log,
      onTick: () {
        listeners
          ..remove(first)
          ..add(late);
      },
    );
    listeners.add(first);

    listeners.beforeTick(1);
    // The dispatch in progress is unaffected; the change applies next tick.
    expect(log, ['self tick 1.0']);
    listeners.beforeTick(2);
    expect(log, ['self tick 1.0', 'late tick 2.0']);
  });

  test('beforeFixedStep precedes every component fixed walk', () {
    final log = <String>[];
    final listeners = SceneTickListeners()..add(_Recorder('input', log));
    final world = PhysicsWorld(FakeSimulation())..fixedTimestep = 0.25;

    Scene.advancePhysics(
      world: world,
      fixedUpdateWalk: (dt) {
        listeners.beforeFixedStep(dt);
        log.add('walk $dt');
      },
      accumulator: 0,
      frameDt: 0.5,
    );

    expect(log, [
      'input step 0.25',
      'walk 0.25',
      'input step 0.25',
      'walk 0.25',
    ]);
  });

  test('both callbacks default to doing nothing', () {
    const listener = _Silent();
    expect(() => listener.beforeTick(1), returnsNormally);
    expect(() => listener.beforeFixedStep(1), returnsNormally);
  });
}

class _SelfRemoving extends _Recorder {
  _SelfRemoving(List<String> log, {required this.onTick}) : super('self', log);

  final void Function() onTick;

  @override
  void beforeTick(double deltaSeconds) {
    super.beforeTick(deltaSeconds);
    onTick();
  }
}

class _Silent extends SceneTickListener {
  const _Silent();
}
