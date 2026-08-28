// The visual scripting runtime: how exec and data wires behave, what each
// standard node does, and that a graph survives its text form.

import 'package:scene/flow.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A graph plus the pieces needed to run it.
({FlowGraph graph, NullFlowHost host, FlowInterpreter runner}) rig() => (
  graph: FlowGraph(),
  host: NullFlowHost(),
  runner: FlowInterpreter(standardFlowRegistry()),
);

void main() {
  group('FlowType.connectsTo', () {
    test('exec only ever meets exec', () {
      expect(FlowType.exec.connectsTo(FlowType.exec), isTrue);
      expect(FlowType.exec.connectsTo(FlowType.number), isFalse);
      expect(FlowType.number.connectsTo(FlowType.exec), isFalse);
      expect(FlowType.any.connectsTo(FlowType.exec), isFalse);
    });

    test('any connects both ways', () {
      expect(FlowType.any.connectsTo(FlowType.vector3), isTrue);
      expect(FlowType.string.connectsTo(FlowType.any), isTrue);
    });

    test('an integer flows into a number, not the other way', () {
      expect(FlowType.integer.connectsTo(FlowType.number), isTrue);
      expect(
        FlowType.number.connectsTo(FlowType.integer),
        isFalse,
        reason: 'silently truncating an index surfaces three systems later',
      );
    });

    test('unrelated types do not connect', () {
      expect(FlowType.vector3.connectsTo(FlowType.boolean), isFalse);
    });
  });

  group('graph editing', () {
    test('an input takes one wire; the new one replaces the old', () {
      final graph = FlowGraph();
      final a = graph.add('math.add');
      final b = graph.add('math.add');
      final sink = graph.add('debug.print');

      graph.connect(
        FlowLink(fromNode: a.id, fromPin: 'value', toNode: sink.id, toPin: 'value'),
      );
      graph.connect(
        FlowLink(fromNode: b.id, fromPin: 'value', toNode: sink.id, toPin: 'value'),
      );
      expect(graph.links, hasLength(1));
      expect(graph.inputTo(sink.id, 'value')!.fromNode, b.id);
    });

    test('an exec output also takes one wire', () {
      final graph = FlowGraph();
      final start = graph.add('event.start');
      final first = graph.add('debug.print');
      final second = graph.add('debug.print');

      graph.connect(
        FlowLink(fromNode: start.id, fromPin: 'then', toNode: first.id, toPin: 'exec'),
      );
      graph.connect(
        FlowLink(fromNode: start.id, fromPin: 'then', toNode: second.id, toPin: 'exec'),
      );
      expect(graph.outputsFrom(start.id, 'then'), hasLength(1));
    });

    test('a data output feeds as many inputs as want it', () {
      final graph = FlowGraph();
      final source = graph.add('math.add');
      final one = graph.add('debug.print');
      final two = graph.add('debug.print');
      graph.connect(
        FlowLink(fromNode: source.id, fromPin: 'value', toNode: one.id, toPin: 'value'),
        execOutputIsSingular: false,
      );
      graph.connect(
        FlowLink(fromNode: source.id, fromPin: 'value', toNode: two.id, toPin: 'value'),
        execOutputIsSingular: false,
      );
      expect(graph.outputsFrom(source.id, 'value'), hasLength(2));
    });

    test('removing a node takes its wires with it', () {
      final graph = FlowGraph();
      final a = graph.add('math.add');
      final b = graph.add('debug.print');
      graph.connect(
        FlowLink(fromNode: a.id, fromPin: 'value', toNode: b.id, toPin: 'value'),
      );
      graph.removeNode(a.id);
      expect(graph.nodes, hasLength(1));
      expect(graph.links, isEmpty);
    });

    test('ids are not reused after a delete', () {
      final graph = FlowGraph();
      final first = graph.add('math.add');
      graph.removeNode(first.id);
      final second = graph.add('math.add');
      expect(
        second.id,
        isNot(first.id),
        reason: 'reusing an id would silently reconnect a stale wire',
      );
    });

    test('a copy is independent', () {
      final graph = FlowGraph();
      final node = graph.add('math.add')..literals['a'] = 3.0;
      final copy = graph.copy();
      copy.node(node.id)!.literals['a'] = 9.0;
      copy.node(node.id)!.position.x = 100;
      expect(graph.node(node.id)!.literals['a'], 3.0);
      expect(graph.node(node.id)!.position.x, 0);
    });
  });

  group('execution', () {
    test('an event with nothing wired does nothing but still fires', () {
      final r = rig();
      r.graph.add('event.start');
      final context = FlowContext(graph: r.graph, host: r.host);
      expect(r.runner.fire(context, onStart.id), 1);
      expect(r.host.messages, isEmpty);
    });

    test('exec pushes forward from the event', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final print = r.graph.add('debug.print')
        ..literals['label'] = 'hello'
        ..literals['value'] = 42;
      r.graph.connect(
        FlowLink(fromNode: start.id, fromPin: 'then', toNode: print.id, toPin: 'exec'),
      );

      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(r.host.messages, ['hello: 42']);
    });

    test('data pulls backward through the wire', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final add = r.graph.add('math.add')
        ..literals['a'] = 2.0
        ..literals['b'] = 3.0;
      final multiply = r.graph.add('math.multiply')..literals['b'] = 10.0;
      final print = r.graph.add('debug.print');

      r.graph
        ..connect(FlowLink(
          fromNode: start.id, fromPin: 'then', toNode: print.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: add.id, fromPin: 'value', toNode: multiply.id, toPin: 'a'))
        ..connect(FlowLink(
          fromNode: multiply.id, fromPin: 'value', toNode: print.id, toPin: 'value'));

      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(r.host.messages, ['50.0']);
    });

    test('an unconnected input reads its literal, then its default', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final print = r.graph.add('debug.print');
      r.graph.connect(FlowLink(
        fromNode: start.id, fromPin: 'then', toNode: print.id, toPin: 'exec'));

      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      // The label defaults to empty and the value to null.
      expect(r.host.messages, ['null']);
    });

    test('Branch takes one side', () {
      String run(bool condition) {
        final r = rig();
        final start = r.graph.add('event.start');
        final gate = r.graph.add('flow.branch')..literals['condition'] = condition;
        final yes = r.graph.add('debug.print')..literals['value'] = 'yes';
        final no = r.graph.add('debug.print')..literals['value'] = 'no';
        r.graph
          ..connect(FlowLink(
            fromNode: start.id, fromPin: 'then', toNode: gate.id, toPin: 'exec'))
          ..connect(FlowLink(
            fromNode: gate.id, fromPin: 'true', toNode: yes.id, toPin: 'exec'))
          ..connect(FlowLink(
            fromNode: gate.id, fromPin: 'false', toNode: no.id, toPin: 'exec'));
        final context = FlowContext(graph: r.graph, host: r.host);
        r.runner.fire(context, onStart.id);
        return r.host.messages.single;
      }

      expect(run(true), 'yes');
      expect(run(false), 'no');
    });

    test('Sequence runs every branch, in order', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final seq = r.graph.add('flow.sequence');
      final one = r.graph.add('debug.print')..literals['value'] = '1';
      final two = r.graph.add('debug.print')..literals['value'] = '2';
      final three = r.graph.add('debug.print')..literals['value'] = '3';
      r.graph
        ..connect(FlowLink(
          fromNode: start.id, fromPin: 'then', toNode: seq.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: seq.id, fromPin: 'a', toNode: one.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: seq.id, fromPin: 'b', toNode: two.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: seq.id, fromPin: 'c', toNode: three.id, toPin: 'exec'));

      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(r.host.messages, ['1', '2', '3']);
    });

    test('an exec cycle stops with an error, not a hang', () {
      // connect() keeps an input to one wire, so a cycle cannot be drawn on
      // the canvas at all. It can arrive from a hand-edited file, which is
      // what the step budget is there for, so the links go on directly.
      final r = rig();
      final start = r.graph.add('event.start');
      final a = r.graph.add('flow.gate');
      final b = r.graph.add('flow.gate');
      r.graph.links.addAll([
        FlowLink(fromNode: start.id, fromPin: 'then', toNode: a.id, toPin: 'exec'),
        FlowLink(fromNode: a.id, fromPin: 'then', toNode: b.id, toPin: 'exec'),
        FlowLink(fromNode: b.id, fromPin: 'then', toNode: a.id, toPin: 'exec'),
      ]);

      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(context.error, contains('loop in the exec wires'));
    });

    test('a data cycle stops with an error, not a stack overflow', () {
      // This one *can* be drawn: A's input from B and B's input from A are
      // two different inputs, so neither replaces the other. A pull is
      // recursive, so a budget would overflow the stack first; the cycle is
      // caught directly instead.
      final r = rig();
      final a = r.graph.add('math.add');
      final b = r.graph.add('math.add');
      r.graph
        ..connect(FlowLink(
          fromNode: a.id, fromPin: 'value', toNode: b.id, toPin: 'a'))
        ..connect(FlowLink(
          fromNode: b.id, fromPin: 'value', toNode: a.id, toPin: 'a'));

      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.evaluateOutput(context, a.id, 'value');
      expect(context.error, contains('cycle in the data wires'));
    });

    test('one source feeding two inputs is a diamond, not a cycle', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final source = r.graph.add('math.add')
        ..literals['a'] = 2.0
        ..literals['b'] = 3.0;
      final sum = r.graph.add('math.add');
      final print = r.graph.add('debug.print');
      r.graph
        ..connect(FlowLink(
          fromNode: start.id, fromPin: 'then', toNode: print.id, toPin: 'exec'))
        ..connect(
          FlowLink(fromNode: source.id, fromPin: 'value', toNode: sum.id, toPin: 'a'),
          execOutputIsSingular: false,
        )
        ..connect(
          FlowLink(fromNode: source.id, fromPin: 'value', toNode: sum.id, toPin: 'b'),
          execOutputIsSingular: false,
        )
        ..connect(FlowLink(
          fromNode: sum.id, fromPin: 'value', toNode: print.id, toPin: 'value'));

      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(context.error, isNull);
      expect(r.host.messages, ['10.0'], reason: '(2 + 3) twice');
    });

    test('an unknown node type is reported rather than skipped', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final bogus = r.graph.add('nothing.here');
      r.graph.connect(FlowLink(
        fromNode: start.id, fromPin: 'then', toNode: bogus.id, toPin: 'exec'));
      final context = FlowContext(graph: r.graph, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(context.error, contains('nothing.here'));
    });
  });

  group('stateful nodes', () {
    test('Do Once passes through once, then never', () {
      final r = rig();
      final tick = r.graph.add('event.tick');
      final once = r.graph.add('flow.doOnce');
      final print = r.graph.add('debug.print')..literals['value'] = 'fired';
      r.graph
        ..connect(FlowLink(
          fromNode: tick.id, fromPin: 'then', toNode: once.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: once.id, fromPin: 'then', toNode: print.id, toPin: 'exec'));

      final context = FlowContext(graph: r.graph, host: r.host);
      for (var i = 0; i < 5; i++) {
        r.runner.fire(context, onTick.id);
      }
      expect(r.host.messages, ['fired']);
    });

    test('Delay holds, then fires, then re-arms', () {
      final r = rig();
      final tick = r.graph.add('event.tick');
      final wait = r.graph.add('flow.delay')..literals['seconds'] = 0.1;
      final print = r.graph.add('debug.print')..literals['value'] = 'now';
      r.graph
        ..connect(FlowLink(
          fromNode: tick.id, fromPin: 'then', toNode: wait.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: wait.id, fromPin: 'then', toNode: print.id, toPin: 'exec'));

      final context = FlowContext(graph: r.graph, host: r.host..deltaSeconds = 1 / 60);
      for (var i = 0; i < 6; i++) {
        r.runner.fire(context, onTick.id);
      }
      expect(r.host.messages, isEmpty, reason: 'a tenth of a second is 6 frames');
      r.runner.fire(context, onTick.id);
      expect(r.host.messages, ['now']);

      // Re-armed, so a Delay under a repeating event is a metronome.
      for (var i = 0; i < 7; i++) {
        r.runner.fire(context, onTick.id);
      }
      expect(r.host.messages, ['now', 'now']);
    });

    test('variables persist across ticks', () {
      final r = rig();
      r.graph.variables.add(
        FlowVariable(name: 'count', type: FlowType.number, initial: 0.0),
      );
      final tick = r.graph.add('event.tick');
      final read = r.graph.add('var.get')..literals['name'] = 'count';
      final add = r.graph.add('math.add')..literals['b'] = 1.0;
      final write = r.graph.add('var.set')..literals['name'] = 'count';
      r.graph
        ..connect(FlowLink(
          fromNode: tick.id, fromPin: 'then', toNode: write.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: read.id, fromPin: 'value', toNode: add.id, toPin: 'a'))
        ..connect(FlowLink(
          fromNode: add.id, fromPin: 'value', toNode: write.id, toPin: 'value'));

      final context = FlowContext(graph: r.graph, host: r.host);
      for (var i = 0; i < 4; i++) {
        r.runner.fire(context, onTick.id);
      }
      expect(context.variables['count'], 4.0);
    });
  });

  group('the standard nodes', () {
    Object? evaluate(String type, Map<String, Object?> literals, String pin) {
      final r = rig();
      final node = r.graph.add(type)..literals.addAll(literals);
      final context = FlowContext(graph: r.graph, host: r.host);
      return r.runner.evaluateOutput(context, node.id, pin);
    }

    test('arithmetic', () {
      expect(evaluate('math.add', {'a': 2.0, 'b': 5.0}, 'value'), 7.0);
      expect(evaluate('math.subtract', {'a': 2.0, 'b': 5.0}, 'value'), -3.0);
      expect(evaluate('math.multiply', {'a': 3.0, 'b': 4.0}, 'value'), 12.0);
      expect(evaluate('math.divide', {'a': 9.0, 'b': 3.0}, 'value'), 3.0);
    });

    test('dividing by zero gives zero, not an infinity', () {
      expect(evaluate('math.divide', {'a': 1.0, 'b': 0.0}, 'value'), 0.0);
    });

    test('clamp holds the range, even an inverted one', () {
      expect(evaluate('math.clamp', {'value': 5.0, 'min': 0.0, 'max': 1.0}, 'out'), 1.0);
      expect(evaluate('math.clamp', {'value': -5.0, 'min': 0.0, 'max': 1.0}, 'out'), 0.0);
      expect(
        evaluate('math.clamp', {'value': 5.0, 'min': 1.0, 'max': 0.0}, 'out'),
        1.0,
        reason: 'an inverted range collapses to its low end rather than throwing',
      );
    });

    test('comparisons', () {
      expect(evaluate('logic.greater', {'a': 2.0, 'b': 1.0}, 'value'), isTrue);
      expect(evaluate('logic.less', {'a': 2.0, 'b': 1.0}, 'value'), isFalse);
      expect(
        evaluate('logic.equal', {'a': 0.1 + 0.2, 'b': 0.3}, 'value'),
        isTrue,
        reason: 'exact float equality is a trap, so this is near equality',
      );
    });

    test('logic gates', () {
      expect(evaluate('logic.and', {'a': true, 'b': false}, 'value'), isFalse);
      expect(evaluate('logic.or', {'a': true, 'b': false}, 'value'), isTrue);
      expect(evaluate('logic.not', {'a': true}, 'value'), isFalse);
    });

    test('vectors are made, broken, added, and scaled', () {
      final made = evaluate(
        'vector.make',
        {'x': 1.0, 'y': 2.0, 'z': 3.0},
        'value',
      );
      expect(made, Vector3(1, 2, 3));
      expect(
        evaluate('vector.break', {'value': Vector3(4, 5, 6)}, 'y'),
        5.0,
      );
      expect(
        evaluate(
          'vector.add',
          {'a': Vector3(1, 1, 1), 'b': Vector3(2, 0, 0)},
          'value',
        ),
        Vector3(3, 1, 1),
      );
      expect(
        evaluate(
          'vector.scale',
          {'a': Vector3(1, 2, 3), 'scale': 2.0},
          'value',
        ),
        Vector3(2, 4, 6),
      );
    });

    test('sine oscillates inside its range', () {
      final r = rig();
      final node = r.graph.add('math.sine')
        ..literals['rate'] = 1.0
        ..literals['min'] = 10.0
        ..literals['max'] = 20.0;
      final context = FlowContext(graph: r.graph, host: r.host);
      final seen = <double>[];
      for (var i = 0; i < 60; i++) {
        r.host.elapsedSeconds = i / 60;
        seen.add(
          r.runner.evaluateOutput(context, node.id, 'value')! as double,
        );
      }
      expect(seen.every((v) => v >= 10 - 1e-9 && v <= 20 + 1e-9), isTrue);
      expect(seen.reduce((a, b) => a > b ? a : b), greaterThan(19));
      expect(seen.reduce((a, b) => a < b ? a : b), lessThan(11));
    });

    test('every standard node is registered exactly once', () {
      final registry = standardFlowRegistry();
      expect(registry.all, hasLength(standardFlowNodes.length));
      for (final type in standardFlowNodes) {
        expect(registry[type.id], same(type), reason: type.id);
      }
    });

    test('every node type declares a doc and unique pin ids', () {
      for (final type in standardFlowNodes) {
        expect(type.doc, isNotEmpty, reason: type.id);
        final ids = <String>{};
        for (final pin in type.pins) {
          expect(ids.add(pin.id), isTrue, reason: '${type.id}.${pin.id}');
        }
      }
    });

    test('an event has no exec input; everything else that flows has one', () {
      for (final type in standardFlowNodes) {
        final execIn = type.inputs.any((pin) => pin.type == FlowType.exec);
        if (type.isEvent) {
          expect(execIn, isFalse, reason: '${type.id} is an event');
        }
      }
    });
  });

  group('serialization', () {
    test('a graph round-trips through its text form', () {
      final graph = FlowGraph();
      graph.variables.add(
        FlowVariable(name: 'speed', type: FlowType.number, initial: 2.5),
      );
      final start = graph.add('event.tick');
      final make = graph.add('vector.make')
        ..literals['x'] = 1.5
        ..literals['y'] = Vector3(1, 2, 3);
      make.position.setValues(120, -40);
      final print = graph.add('debug.print')..literals['label'] = 'v';
      graph
        ..connect(FlowLink(
          fromNode: start.id, fromPin: 'then', toNode: print.id, toPin: 'exec'))
        ..connect(FlowLink(
          fromNode: make.id, fromPin: 'value', toNode: print.id, toPin: 'value'));

      final restored = readFlowGraph(writeFlowGraph(graph));
      expect(restored.nodes, hasLength(3));
      expect(restored.links, hasLength(2));
      expect(restored.nextNodeId, graph.nextNodeId);
      final madeAgain = restored.node(make.id)!;
      expect(madeAgain.type, 'vector.make');
      expect(madeAgain.position.x, 120);
      expect(madeAgain.position.y, -40);
      expect(madeAgain.literals['x'], 1.5);
      expect(
        madeAgain.literals['y'],
        Vector3(1, 2, 3),
        reason: 'a vector literal is tagged so it does not decode as a list',
      );
      expect(restored.variable('speed')!.initial, 2.5);
      expect(restored.variable('speed')!.type, FlowType.number);
    });

    test('a second round trip is byte-identical', () {
      final graph = FlowGraph();
      graph.add('event.start');
      graph.add('debug.print');
      final once = writeFlowGraph(graph);
      expect(writeFlowGraph(readFlowGraph(once)), once);
    });

    test('a restored graph still runs', () {
      final r = rig();
      final start = r.graph.add('event.start');
      final print = r.graph.add('debug.print')..literals['value'] = 'ok';
      r.graph.connect(FlowLink(
        fromNode: start.id, fromPin: 'then', toNode: print.id, toPin: 'exec'));

      final restored = readFlowGraph(writeFlowGraph(r.graph));
      final context = FlowContext(graph: restored, host: r.host);
      r.runner.fire(context, onStart.id);
      expect(r.host.messages, ['ok']);
    });

    test('a counter behind the ids in use is lifted past them', () {
      // A hand-edited file would otherwise hand a fresh node an id a wire
      // already points at.
      final graph = decodeFlowGraph({
        'nextNodeId': 1,
        'nodes': [
          {'id': 9, 'type': 'math.add', 'x': 0, 'y': 0},
        ],
        'links': <Object?>[],
      });
      expect(graph.nextNodeId, 10);
    });

    test('malformed entries are skipped rather than throwing', () {
      final graph = decodeFlowGraph({
        'nodes': [
          {'id': 1, 'type': 'math.add', 'x': 0, 'y': 0},
          {'type': 'no.id'},
          'not a map',
        ],
        'links': [
          {'from': 1, 'fromPin': 'value', 'to': 2, 'toPin': 'a'},
          {'from': 1, 'to': 2},
        ],
      });
      expect(graph.nodes, hasLength(1));
      expect(graph.links, hasLength(1));
    });

    test('a graph that is not an object is refused', () {
      expect(() => readFlowGraph('[]'), throwsFormatException);
    });
  });
}
