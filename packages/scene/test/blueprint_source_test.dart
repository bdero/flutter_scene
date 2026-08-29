// A blueprint as text. The load-bearing property is the round trip: whatever
// the editor hands the code view has to come back as the same blueprint, or
// opening a graph as code and closing it again quietly edits it.

import 'dart:math';

import 'package:scene/visual_script.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A small graph with one of everything that has to survive.
VisualScriptGraph sample() {
  final graph = VisualScriptGraph(
    variables: [
      VisualScriptVariable(
        name: 'isOpen',
        type: VisualScriptType.boolean,
        initial: false,
      ),
      VisualScriptVariable(
        name: 'count',
        type: VisualScriptType.number,
        initial: 3.5,
      ),
      VisualScriptVariable(
        name: 'label',
        type: VisualScriptType.string,
        initial: 'a "quoted" bit',
      ),
      VisualScriptVariable(name: 'spare', type: VisualScriptType.any),
    ],
  );
  final start = graph.add('event.start', position: Vector2(40, 40));
  final move = graph.add('scene.setPosition', position: Vector2(260, 40))
    ..literals['target'] = 'door'
    ..literals['value'] = Vector3(0, 1, -2.5);
  final say = graph.add('debug.print', position: Vector2(480, 40))
    ..literals['value'] = 'opened';
  graph.links.addAll([
    VisualScriptLink(
      fromNode: start.id,
      fromPin: 'then',
      toNode: move.id,
      toPin: 'exec',
    ),
    VisualScriptLink(
      fromNode: move.id,
      fromPin: 'then',
      toNode: say.id,
      toPin: 'exec',
    ),
  ]);
  return graph;
}

/// A graph built from [seed], for the round trip to be tried against something
/// nobody chose by hand.
VisualScriptGraph fuzzed(int seed) {
  final random = Random(seed);
  const types = [
    'event.start',
    'event.tick',
    'flow.branch',
    'math.add',
    'var.get',
    'var.set',
    'scene.setPosition',
    'debug.print',
  ];
  const pins = ['exec', 'then', 'true', 'false', 'value', 'a', 'b', 'out'];
  final graph = VisualScriptGraph();
  final count = 1 + random.nextInt(9);
  for (var i = 0; i < count; i++) {
    final node = graph.add(
      types[random.nextInt(types.length)],
      position: Vector2(
        (random.nextInt(2000) - 1000).toDouble(),
        (random.nextInt(2000) - 1000).toDouble(),
      ),
    );
    if (random.nextBool()) node.literals['value'] = random.nextInt(100);
    if (random.nextBool()) node.literals['name'] = 'v${random.nextInt(5)}';
    if (random.nextBool()) {
      node.literals['flag'] = random.nextBool();
    }
    if (random.nextBool()) {
      node.literals['at'] = Vector3(
        random.nextDouble() * 10,
        random.nextDouble() * 10,
        random.nextDouble() * 10,
      );
    }
  }
  for (var i = 0; i < count; i++) {
    if (!random.nextBool()) continue;
    graph.links.add(
      VisualScriptLink(
        fromNode: graph.nodes[random.nextInt(count)].id,
        fromPin: pins[random.nextInt(pins.length)],
        toNode: graph.nodes[random.nextInt(count)].id,
        toPin: pins[random.nextInt(pins.length)],
      ),
    );
  }
  for (var i = 0; i < random.nextInt(4); i++) {
    graph.variables.add(
      VisualScriptVariable(
        name: 'var$i',
        type: VisualScriptType
            .values[random.nextInt(VisualScriptType.values.length)],
        initial: random.nextBool() ? random.nextInt(50) : null,
      ),
    );
  }
  return graph;
}

void main() {
  group('round trip', () {
    test('a graph survives being written and read', () {
      final before = sample();
      final after = parseBlueprint(printBlueprint(before));
      expect(after.diagnostics, isEmpty);
      expect(blueprintEquivalent(before, after.graph), isTrue);
    });

    test('printing is stable, so a re-save is not a diff', () {
      final once = printBlueprint(sample());
      final twice = printBlueprint(parseBlueprint(once).graph);
      expect(twice, once);
    });

    test('it holds for graphs nobody chose by hand', () {
      for (var seed = 0; seed < 200; seed++) {
        final before = fuzzed(seed);
        final text = printBlueprint(before);
        final after = parseBlueprint(text);
        expect(after.diagnostics, isEmpty, reason: 'seed $seed:\n$text');
        expect(
          printBlueprint(after.graph),
          text,
          reason: 'seed $seed did not come back the same',
        );
      }
    });

    test('an empty graph is still a blueprint', () {
      final result = parseBlueprint(printBlueprint(VisualScriptGraph()));
      expect(result.diagnostics, isEmpty);
      expect(result.graph.nodes, isEmpty);
    });
  });

  group('what survives', () {
    test('positions', () {
      final after = parseBlueprint(printBlueprint(sample())).graph;
      expect(after.nodes[1].position.x, 260);
      expect(after.nodes[1].position.y, 40);
    });

    test('a vector literal, to its components', () {
      final after = parseBlueprint(printBlueprint(sample())).graph;
      final value = after.nodes[1].literals['value'];
      expect(value, isA<Vector3>());
      expect((value! as Vector3).z, -2.5);
    });

    test('a string with quotes in it', () {
      final after = parseBlueprint(printBlueprint(sample())).graph;
      expect(after.variables[2].initial, 'a "quoted" bit');
    });

    test('a variable with no initial value stays without one', () {
      final after = parseBlueprint(printBlueprint(sample())).graph;
      expect(after.variables[3].initial, isNull);
      expect(after.variables[3].type, VisualScriptType.any);
    });

    test('two wires out of one pin, which the graph allows', () {
      final graph = VisualScriptGraph();
      final a = graph.add('event.start');
      final b = graph.add('debug.print');
      final c = graph.add('debug.print');
      graph.links.addAll([
        VisualScriptLink(
          fromNode: a.id,
          fromPin: 'then',
          toNode: b.id,
          toPin: 'exec',
        ),
        VisualScriptLink(
          fromNode: a.id,
          fromPin: 'then',
          toNode: c.id,
          toPin: 'exec',
        ),
      ]);
      final after = parseBlueprint(printBlueprint(graph)).graph;
      expect(after.links, hasLength(2));
    });
  });

  group('reading', () {
    test('names repeat as little as possible, and never collide', () {
      final graph = VisualScriptGraph();
      for (var i = 0; i < 3; i++) {
        graph.add('debug.print');
      }
      final text = printBlueprint(graph);
      expect(text, contains('print = '));
      expect(text, contains('print2 = '));
      expect(text, contains('print3 = '));
    });

    test('comments and blank lines are ignored', () {
      const source = '''
blueprint 1
// a note about the door
name Door

var isOpen: boolean = false   // and one here

start = event.start @ 0, 0
''';
      final result = parseBlueprint(source);
      expect(result.diagnostics, isEmpty);
      expect(result.graph.nodes, hasLength(1));
      expect(result.graph.variables, hasLength(1));
    });

    test('a slash inside a string is not a comment', () {
      final result = parseBlueprint(
        'p = debug.print(value: "assets/door.glb") @ 0, 0',
      );
      expect(result.diagnostics, isEmpty);
      expect(result.graph.nodes.single.literals['value'], 'assets/door.glb');
    });

    test('a wire may be written before the nodes it joins', () {
      const source = '''
a.then -> b.exec
a = event.start @ 0, 0
b = debug.print @ 0, 0
''';
      // The node line needs its parentheses; this one is testing order.
      final result = parseBlueprint(
        source
            .replaceAll('event.start @', 'event.start() @')
            .replaceAll('debug.print @', 'debug.print() @'),
      );
      expect(result.diagnostics, isEmpty);
      expect(result.graph.links, hasLength(1));
    });

    test('a position may be left off, and lands at the origin', () {
      final result = parseBlueprint('a = event.start()');
      expect(result.diagnostics, isEmpty);
      expect(result.graph.nodes.single.position, Vector2.zero());
    });
  });

  group('when it is wrong', () {
    test(
      'a wire to a node that is not there is reported, not dropped silently',
      () {
        final result = parseBlueprint('''
a = event.start() @ 0, 0
a.then -> ghost.exec
''');
        expect(result.isClean, isFalse);
        expect(result.diagnostics.single.message, contains('ghost'));
        expect(result.diagnostics.single.line, 2);
      },
    );

    test('one bad line costs one line, not the file', () {
      final result = parseBlueprint('''
a = event.start() @ 0, 0
this line is nonsense
b = debug.print() @ 0, 0
''');
      expect(result.diagnostics, hasLength(1));
      expect(result.graph.nodes, hasLength(2), reason: 'the rest was dropped');
    });

    test('a repeated name is reported rather than overwriting', () {
      final result = parseBlueprint('''
a = event.start() @ 0, 0
a = debug.print() @ 0, 0
''');
      expect(result.diagnostics.single.message, contains('already called'));
      expect(result.graph.nodes, hasLength(1));
    });

    test('an unknown variable type is reported', () {
      final result = parseBlueprint('var x: quaternion = 1');
      expect(result.diagnostics.single.message, contains('quaternion'));
    });

    test('an argument with no pin name is reported', () {
      final result = parseBlueprint('a = debug.print("loose") @ 0, 0');
      expect(result.diagnostics.single.message, contains('pin name'));
    });

    test('nothing throws, whatever it is handed', () {
      for (final source in [
        '',
        '   ',
        '((((',
        'a = () @ ,',
        'var',
        '-> ->',
        'a = x.y(z: "unterminated) @ 0, 0',
      ]) {
        expect(() => parseBlueprint(source), returnsNormally, reason: source);
      }
    });
  });
}
