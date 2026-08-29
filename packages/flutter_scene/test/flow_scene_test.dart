// A graph running on a scene node: what the scene-facing nodes do, how the
// component drives them, and that a script survives the document.
//
// GPU-free: nothing here builds geometry, and the host reaches the scene
// through plain Node properties.

import 'package:flutter_scene/flow.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A node with a graph on it, ticked by hand.
({Node node, FlowComponent flow, List<String> log}) rig({
  FlowGraph? graph,
  Object? Function(String, Map<String, Object?>)? onAction,
}) {
  final log = <String>[];
  final node = Node(name: 'actor');
  final flow = FlowComponent(
    graph: graph ?? FlowGraph(),
    onAction: onAction,
    onLog: log.add,
  );
  node.addComponent(flow);
  return (node: node, flow: flow, log: log);
}

void main() {
  group('SceneFlowHost paths', () {
    test('a bare path is the owning node', () {
      final node = Node(name: 'actor')..position = Vector3(1, 2, 3);
      final host = SceneFlowHost(node);
      expect(host.read('position'), Vector3(1, 2, 3));
      expect(host.read('position.y'), 2.0);
      expect(host.write('position.y', 9.0), isTrue);
      expect(node.position.y, 9.0);
    });

    test('a prefixed path is a descendant by name', () {
      final turret = Node(name: 'turret')..position = Vector3(0, 5, 0);
      final node = Node(name: 'tank')..add(turret);
      final host = SceneFlowHost(node);
      expect(host.read('turret/position.y'), 5.0);
      expect(host.write('turret/position.y', 7.0), isTrue);
      expect(turret.position.y, 7.0);
    });

    test('a path to nothing reports failure rather than doing nothing', () {
      final host = SceneFlowHost(Node(name: 'actor'));
      expect(host.read('ghost/position'), isNull);
      expect(host.write('ghost/position', Vector3.zero()), isFalse);
      expect(
        host.write('notAProperty', 1.0),
        isFalse,
        reason: 'an unknown property on a real node fails too',
      );
    });

    test('visibility and the world transform are readable', () {
      final child = Node(name: 'child')..position = Vector3(1, 0, 0);
      final node = Node(name: 'root')
        ..position = Vector3(10, 0, 0)
        ..add(child);
      final host = SceneFlowHost(node);
      expect(host.read('visible'), isTrue);
      expect(host.read('child/worldPosition'), Vector3(11, 0, 0));
      expect(host.write('child/visible', false), isTrue);
      expect(child.visible, isFalse);
    });
  });

  group('scene nodes', () {
    test('Set Position writes through the graph', () {
      final graph = FlowGraph();
      final start = graph.add('event.start');
      final make = graph.add('vector.make')
        ..literals['x'] = 4.0
        ..literals['y'] = 5.0;
      final set = graph.add('scene.setPosition');
      graph
        ..connect(
          FlowLink(
            fromNode: start.id,
            fromPin: 'then',
            toNode: set.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          FlowLink(
            fromNode: make.id,
            fromPin: 'value',
            toNode: set.id,
            toPin: 'value',
          ),
        );

      final r = rig(graph: graph);
      r.flow.update(1 / 60);
      expect(r.node.position, Vector3(4, 5, 0));
    });

    test('Translate accumulates over ticks', () {
      final graph = FlowGraph();
      final tick = graph.add('event.tick');
      final step = graph.add('vector.make')..literals['x'] = 1.0;
      final move = graph.add('scene.translate');
      graph
        ..connect(
          FlowLink(
            fromNode: tick.id,
            fromPin: 'then',
            toNode: move.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          FlowLink(
            fromNode: step.id,
            fromPin: 'value',
            toNode: move.id,
            toPin: 'by',
          ),
        );

      final r = rig(graph: graph);
      for (var i = 0; i < 3; i++) {
        r.flow.update(1 / 60);
      }
      expect(r.node.position.x, 3.0);
    });

    test('a write to a missing target says so instead of silently failing', () {
      final graph = FlowGraph();
      final start = graph.add('event.start');
      final set = graph.add('scene.setPosition')..literals['target'] = 'ghost';
      graph.connect(
        FlowLink(
          fromNode: start.id,
          fromPin: 'then',
          toNode: set.id,
          toPin: 'exec',
        ),
      );

      final r = rig(graph: graph);
      r.flow.update(1 / 60);
      expect(r.log.single, contains('ghost/position'));
    });

    test('Call Action reaches the application', () {
      final calls = <String>[];
      final graph = FlowGraph();
      final start = graph.add('event.start');
      final call = graph.add('scene.call')
        ..literals['action'] = 'openDoor'
        ..literals['value'] = 3;
      graph.connect(
        FlowLink(
          fromNode: start.id,
          fromPin: 'then',
          toNode: call.id,
          toPin: 'exec',
        ),
      );

      final r = rig(
        graph: graph,
        onAction: (action, arguments) {
          calls.add('$action(${arguments['value']})');
          return true;
        },
      );
      r.flow.update(1 / 60);
      expect(calls, ['openDoor(3)']);
    });

    test('Play Animation reports a name the node does not have', () {
      final graph = FlowGraph();
      final start = graph.add('event.start');
      final play = graph.add('scene.playAnimation')..literals['name'] = 'wave';
      graph.connect(
        FlowLink(
          fromNode: start.id,
          fromPin: 'then',
          toNode: play.id,
          toPin: 'exec',
        ),
      );

      final r = rig(graph: graph);
      r.flow.update(1 / 60);
      expect(r.log.single, contains('No animation named "wave"'));
    });

    test('every scene node declares a doc and unique pin ids', () {
      for (final type in sceneFlowNodes) {
        expect(type.doc, isNotEmpty, reason: type.id);
        final ids = <String>{};
        for (final pin in type.pins) {
          expect(ids.add(pin.id), isTrue, reason: '${type.id}.${pin.id}');
        }
      }
    });

    test('the scene registry holds the standard nodes too', () {
      final registry = sceneFlowRegistry();
      expect(registry[onTick.id], isNotNull);
      expect(registry[setPosition.id], isNotNull);
      expect(
        registry.all,
        hasLength(standardFlowNodes.length + sceneFlowNodes.length),
      );
    });
  });

  group('FlowComponent', () {
    test('On Start fires once and On Tick every frame', () {
      final graph = FlowGraph();
      final start = graph.add('event.start');
      final tick = graph.add('event.tick');
      final onceMessage = graph.add('debug.print')..literals['value'] = 'start';
      final everyMessage = graph.add('debug.print')..literals['value'] = 'tick';
      graph
        ..connect(
          FlowLink(
            fromNode: start.id,
            fromPin: 'then',
            toNode: onceMessage.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          FlowLink(
            fromNode: tick.id,
            fromPin: 'then',
            toNode: everyMessage.id,
            toPin: 'exec',
          ),
        );

      final r = rig(graph: graph);
      for (var i = 0; i < 3; i++) {
        r.flow.update(1 / 60);
      }
      expect(r.log, ['start', 'tick', 'tick', 'tick']);
    });

    test('a raised signal reaches its event on the next tick', () {
      final graph = FlowGraph();
      final signal = graph.add('event.signal')..literals['name'] = 'open';
      final print = graph.add('debug.print')..literals['value'] = 'opened';
      graph.connect(
        FlowLink(
          fromNode: signal.id,
          fromPin: 'then',
          toNode: print.id,
          toPin: 'exec',
        ),
      );

      final r = rig(graph: graph);
      r.flow.update(1 / 60);
      expect(r.log, isEmpty, reason: 'nothing raised yet');

      r.flow.raise('open');
      r.flow.update(1 / 60);
      expect(r.log, ['opened']);

      r.flow.update(1 / 60);
      expect(r.log, ['opened'], reason: 'a signal fires once');
    });

    test('a signal by another name is not picked up', () {
      final graph = FlowGraph();
      final signal = graph.add('event.signal')..literals['name'] = 'open';
      final print = graph.add('debug.print')..literals['value'] = 'opened';
      graph.connect(
        FlowLink(
          fromNode: signal.id,
          fromPin: 'then',
          toNode: print.id,
          toPin: 'exec',
        ),
      );

      final r = rig(graph: graph);
      r.flow.raise('close');
      r.flow.update(1 / 60);
      expect(r.log, isEmpty);
    });

    test('running false pauses without losing state', () {
      final graph = FlowGraph();
      graph.variables.add(
        FlowVariable(name: 'n', type: FlowType.number, initial: 0.0),
      );
      final tick = graph.add('event.tick');
      final read = graph.add('var.get')..literals['name'] = 'n';
      final add = graph.add('math.add')..literals['b'] = 1.0;
      final write = graph.add('var.set')..literals['name'] = 'n';
      graph
        ..connect(
          FlowLink(
            fromNode: tick.id,
            fromPin: 'then',
            toNode: write.id,
            toPin: 'exec',
          ),
        )
        ..connect(
          FlowLink(
            fromNode: read.id,
            fromPin: 'value',
            toNode: add.id,
            toPin: 'a',
          ),
        )
        ..connect(
          FlowLink(
            fromNode: add.id,
            fromPin: 'value',
            toNode: write.id,
            toPin: 'value',
          ),
        );

      final r = rig(graph: graph);
      r.flow.update(1 / 60);
      r.flow.running = false;
      r.flow.update(1 / 60);
      expect(r.flow.variables!['n'], 1.0, reason: 'paused, not reset');

      r.flow.running = true;
      r.flow.update(1 / 60);
      expect(r.flow.variables!['n'], 2.0);
    });

    test('restart puts the state back', () {
      final graph = FlowGraph();
      graph.variables.add(
        FlowVariable(name: 'n', type: FlowType.number, initial: 5.0),
      );
      final tick = graph.add('event.tick');
      final write = graph.add('var.set')
        ..literals['name'] = 'n'
        ..literals['value'] = 99.0;
      graph.connect(
        FlowLink(
          fromNode: tick.id,
          fromPin: 'then',
          toNode: write.id,
          toPin: 'exec',
        ),
      );

      final r = rig(graph: graph);
      r.flow.update(1 / 60);
      expect(r.flow.variables!['n'], 99.0);
      r.flow.restart();
      expect(r.flow.variables!['n'], 5.0);
    });

    test('a broken graph is reported once, not every frame', () {
      final graph = FlowGraph();
      final start = graph.add('event.start');
      final bogus = graph.add('does.not.exist');
      graph.connect(
        FlowLink(
          fromNode: start.id,
          fromPin: 'then',
          toNode: bogus.id,
          toPin: 'exec',
        ),
      );

      final r = rig(graph: graph);
      for (var i = 0; i < 5; i++) {
        r.flow.update(1 / 60);
      }
      expect(r.log, hasLength(1));
      expect(r.log.single, contains('does.not.exist'));
      expect(r.flow.error, isNotNull);
    });

    test('a clone gets its own copy of the script and its state', () {
      final graph = FlowGraph();
      graph.variables.add(
        FlowVariable(name: 'n', type: FlowType.number, initial: 0.0),
      );
      graph.add('event.tick');
      final r = rig(graph: graph);

      final clone = r.flow.cloneFor(Node())! as FlowComponent;
      expect(identical(clone.graph, r.flow.graph), isFalse);
      clone.graph.add('debug.print');
      expect(r.flow.graph.nodes, hasLength(1));
    });

    test('replacing the graph restarts it', () {
      final r = rig();
      r.flow.update(1 / 60);

      final replacement = FlowGraph();
      final tick = replacement.add('event.tick');
      final print = replacement.add('debug.print')..literals['value'] = 'new';
      replacement.connect(
        FlowLink(
          fromNode: tick.id,
          fromPin: 'then',
          toNode: print.id,
          toPin: 'exec',
        ),
      );

      r.flow.graph = replacement;
      r.flow.update(1 / 60);
      expect(r.log, ['new']);
    });
  });

  group('the document', () {
    test('a graph round-trips through a component spec', () {
      final graph = FlowGraph();
      final tick = graph.add('event.tick');
      final move = graph.add('scene.translate');
      graph.connect(
        FlowLink(
          fromNode: tick.id,
          fromPin: 'then',
          toNode: move.id,
          toPin: 'exec',
        ),
      );

      final registry = defaultComponentRegistry();
      final codec = registry.codecFor('flow')!;
      final document = SceneDocument();
      final spec = codec.serialize(
        FlowComponent(graph: graph),
        SerializeContext(document),
      )!;
      final restored =
          codec.realize(spec, RealizeContext(document))! as FlowComponent;

      expect(restored.graph.nodes, hasLength(2));
      expect(restored.graph.links, hasLength(1));
      expect(restored.graph.node(move.id)!.type, 'scene.translate');
    });

    test('an empty graph writes nothing, so a plain component stays plain', () {
      final registry = defaultComponentRegistry();
      final codec = registry.codecFor('flow')!;
      final document = SceneDocument();
      final spec = codec.serialize(
        FlowComponent(),
        SerializeContext(document),
      )!;
      expect(spec.properties, isNot(contains('graph')));
    });

    test('an unparsable graph is reported, not thrown', () {
      final registry = defaultComponentRegistry();
      final codec = registry.codecFor('flow')!;
      final component = codec.realize(
        ComponentSpec('flow', properties: {'graph': const StringValue('{{')}),
        RealizeContext(SceneDocument()),
      );
      expect(component, isA<FlowComponent>());
      expect((component! as FlowComponent).graph.nodes, isEmpty);
    });
  });
}
