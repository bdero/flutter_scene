// Driving a character from a graph. A script says what is true -- speed is
// four, jump was pressed -- and the machine decides what plays; a graph that
// named clips directly would be a second state machine disagreeing with the
// first.

import 'package:flutter_scene/flow.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

AnimatorComponent _walkRun() => AnimatorComponent(
  Animator(
    states: const [
      AnimatorState('Idle', ClipMotion('idle')),
      AnimatorState('Run', ClipMotion('run')),
    ],
    transitions: const [
      AnimatorTransition(
        from: 'Idle',
        to: 'Run',
        conditions: [
          AnimatorCondition('speed', AnimatorComparison.greater, threshold: 1),
        ],
      ),
      AnimatorTransition(
        to: 'Hit',
        conditions: [AnimatorCondition('hit', AnimatorComparison.triggered)],
      ),
    ],
    initial: 'Idle',
  ),
);

void main() {
  test('the palette carries the animator nodes', () {
    final registry = sceneFlowRegistry();
    expect(registry['animator.setNumber'], isNotNull);
    expect(registry['animator.setFlag'], isNotNull);
    expect(registry['animator.trigger'], isNotNull);
    expect(registry['animator.state'], isNotNull);
  });

  test('setting a number moves the machine on its next tick', () {
    final node = Node(name: 'hero');
    final animator = _walkRun();
    node.addComponent(animator);
    final host = SceneFlowHost(node);

    expect(
      host.invoke('setAnimatorNumber', {'name': 'speed', 'value': 4.0}),
      isTrue,
    );
    expect(animator.animator.parameters.number('speed'), 4.0);
    // The machine, not the graph, decides what that means.
    animator.animator.evaluate(0.016);
    expect(animator.animator.current, 'Run');
  });

  test('a flag holds and a trigger is consumed once', () {
    final node = Node(name: 'hero');
    final animator = _walkRun();
    node.addComponent(animator);
    final host = SceneFlowHost(node);

    host.invoke('setAnimatorFlag', {'name': 'armed', 'value': true});
    expect(animator.animator.parameters.flag('armed'), isTrue);

    host.invoke('animatorTrigger', {'name': 'hit'});
    expect(animator.animator.parameters.isTriggered('hit'), isTrue);
    expect(animator.animator.parameters.consumeTrigger('hit'), isTrue);
    expect(animator.animator.parameters.consumeTrigger('hit'), isFalse);
  });

  test('reading the state names the state', () {
    final node = Node(name: 'hero');
    node.addComponent(_walkRun());
    final host = SceneFlowHost(node);
    expect(host.invoke('animatorState', {'layer': ''}), 'Idle');
  });

  test('a node with no animator reports it rather than throwing', () {
    // A graph is attached to a node, and there is nothing stopping it being a
    // node that is not a character.
    final log = <String>[];
    final host = SceneFlowHost(Node(name: 'crate'), onLog: log.add);
    expect(
      host.invoke('setAnimatorNumber', {'name': 'speed', 'value': 1.0}),
      isFalse,
    );
    expect(host.invoke('animatorState', {'layer': ''}), '');
    expect(log, hasLength(2));
  });

  test('an unknown layer is reported rather than guessed at', () {
    final node = Node(name: 'hero');
    node.addComponent(_walkRun());
    final log = <String>[];
    final host = SceneFlowHost(node, onLog: log.add);
    expect(host.invoke('animatorState', {'layer': 'nonsense'}), '');
    expect(log.single, contains('nonsense'));
  });
}
