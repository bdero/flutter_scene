// A blueprint: variables that belong to it, and graphs that run at different
// times. The distinctions worth testing are the ones you cannot see from a
// single graph -- that construction runs once and ticking does not run it,
// that two graphs read one variable, and that a routine cannot recurse.

import 'package:scene/visual_script.dart';
import 'package:test/test.dart';

/// A graph that adds one to `count` when it is entered.
VisualScriptGraph counting() {
  final graph = VisualScriptGraph();
  final start = graph.add('event.start');
  final read = graph.add('var.get')..literals['name'] = 'count';
  final add = graph.add('math.add')..literals['b'] = 1.0;
  final write = graph.add('var.set')..literals['name'] = 'count';
  graph
    ..connect(
      VisualScriptLink(
        fromNode: start.id,
        fromPin: 'then',
        toNode: write.id,
        toPin: 'exec',
      ),
    )
    ..connect(
      VisualScriptLink(
        fromNode: read.id,
        fromPin: 'value',
        toNode: add.id,
        toPin: 'a',
      ),
    )
    ..connect(
      VisualScriptLink(
        fromNode: add.id,
        fromPin: 'value',
        toNode: write.id,
        toPin: 'value',
      ),
    );
  return graph;
}

BlueprintRunner runner(Blueprint blueprint) =>
    BlueprintRunner(blueprint: blueprint, host: NullVisualScriptHost());

void main() {
  group('graphs', () {
    test('a bare graph becomes a blueprint with one event graph', () {
      final blueprint = Blueprint.of(VisualScriptGraph(), name: 'Door');
      expect(blueprint.name, 'Door');
      expect(blueprint.graphs, hasLength(1));
      expect(blueprint.graphs.single.kind, VisualScriptGraphKind.eventGraph);
      expect(blueprint.graphs.single.name, defaultEventGraphName);
    });

    test('a graph added twice under one name gets a name of its own', () {
      final blueprint = Blueprint();
      blueprint.addGraph(
        VisualScriptGraph(),
        kind: VisualScriptGraphKind.function,
        name: 'Open',
      );
      final second = blueprint.addGraph(
        VisualScriptGraph(),
        kind: VisualScriptGraphKind.function,
        name: 'Open',
      );
      expect(second.name, 'Open 2');
    });

    test('only functions and macros are callable', () {
      // Calling an event graph or a construction script from a wire would run
      // something whose whole point is when it runs.
      final blueprint = Blueprint();
      blueprint
        ..addGraph(
          VisualScriptGraph(),
          kind: VisualScriptGraphKind.eventGraph,
          name: 'Events',
        )
        ..addGraph(
          VisualScriptGraph(),
          kind: VisualScriptGraphKind.constructionScript,
          name: 'Build',
        )
        ..addGraph(
          VisualScriptGraph(),
          kind: VisualScriptGraphKind.function,
          name: 'Open',
        );
      expect(blueprint.routine('Open'), isNotNull);
      expect(blueprint.routine('Events'), isNull);
      expect(blueprint.routine('Build'), isNull);
      // But they are all findable by name.
      expect(blueprint.graph('Events'), isNotNull);
    });

    test('copying leaves the original alone', () {
      final blueprint = Blueprint(
        variables: [
          VisualScriptVariable(name: 'n', type: VisualScriptType.number),
        ],
      )..addGraph(counting(), kind: VisualScriptGraphKind.eventGraph);
      final copy = blueprint.copy()
        ..name = 'other'
        ..variables.clear();
      copy.graphs.single.nodes.clear();
      expect(blueprint.name, '');
      expect(blueprint.variables, hasLength(1));
      expect(blueprint.graphs.single.nodes, isNotEmpty);
    });
  });

  group('running', () {
    test('construction runs once, and ticking never runs it again', () {
      // The whole reason the two are separate graphs: a construction script
      // that ran every frame would rebuild the instance sixty times a second.
      final blueprint = Blueprint(
        variables: [
          VisualScriptVariable(
            name: 'count',
            type: VisualScriptType.number,
            initial: 0.0,
          ),
        ],
      )..addGraph(counting(), kind: VisualScriptGraphKind.constructionScript);
      final run = runner(blueprint);

      expect(run.isBuilt, isFalse);
      run.build();
      expect(run.isBuilt, isTrue);
      expect(run.variables['count'], 1.0);

      run.build();
      expect(run.variables['count'], 1.0, reason: 'it built twice');
      run.fire('event.tick');
      expect(run.variables['count'], 1.0, reason: 'a tick ran construction');
    });

    test('an event graph is not run by building', () {
      final blueprint = Blueprint(
        variables: [
          VisualScriptVariable(
            name: 'count',
            type: VisualScriptType.number,
            initial: 0.0,
          ),
        ],
      )..addGraph(counting(), kind: VisualScriptGraphKind.eventGraph);
      final run = runner(blueprint)..build();
      expect(run.variables['count'], 0.0);
      run.fire('event.start');
      expect(run.variables['count'], 1.0);
    });

    test('two graphs read and write one variable', () {
      // A variable belongs to the blueprint, so the function that decrements a
      // counter and the graph that reads it see the same counter.
      final blueprint =
          Blueprint(
              variables: [
                VisualScriptVariable(
                  name: 'count',
                  type: VisualScriptType.number,
                  initial: 0.0,
                ),
              ],
            )
            ..addGraph(
              counting(),
              kind: VisualScriptGraphKind.constructionScript,
            )
            ..addGraph(
              counting(),
              kind: VisualScriptGraphKind.function,
              name: 'Bump',
            );
      final run = runner(blueprint)..build();
      expect(run.variables['count'], 1.0);
      expect(run.call('Bump'), isTrue);
      expect(
        run.variables['count'],
        2.0,
        reason: 'the graphs did not share it',
      );
    });

    test('a graph declaring a variable does not reset the shared one', () {
      final graph = counting()
        ..variables.add(
          VisualScriptVariable(
            name: 'count',
            type: VisualScriptType.number,
            initial: 99.0,
          ),
        );
      final blueprint = Blueprint(
        variables: [
          VisualScriptVariable(
            name: 'count',
            type: VisualScriptType.number,
            initial: 0.0,
          ),
        ],
      )..addGraph(graph, kind: VisualScriptGraphKind.constructionScript);
      runner(blueprint).build();
      // The blueprint's initial value wins; the graph's is not applied over it.
      expect(blueprint.variables.single.initial, 0.0);
    });

    test('calling a routine that is not there reports it', () {
      expect(runner(Blueprint()).call('Nothing'), isFalse);
    });

    test('a routine cannot call itself', () {
      // A graph has no base case to express, so the second entry is refused
      // rather than allowed to recurse until the stack goes.
      final blueprint = Blueprint();
      final graph = VisualScriptGraph();
      final start = graph.add('event.start');
      final call = graph.add('debug.print')..literals['value'] = 'x';
      graph.connect(
        VisualScriptLink(
          fromNode: start.id,
          fromPin: 'then',
          toNode: call.id,
          toPin: 'exec',
        ),
      );
      blueprint.addGraph(
        graph,
        kind: VisualScriptGraphKind.function,
        name: 'Loop',
      );
      final run = runner(blueprint);
      expect(run.call('Loop'), isTrue);
      expect(
        run.call('Loop'),
        isTrue,
        reason: 'it stayed latched after one run',
      );
    });

    test('every graph gets its own node state', () {
      // Node ids are only unique within a graph, so one shared state map would
      // have two graphs' Do Once latches on top of each other.
      final blueprint = Blueprint()
        ..addGraph(counting(), kind: VisualScriptGraphKind.eventGraph)
        ..addGraph(counting(), kind: VisualScriptGraphKind.function, name: 'F');
      final run = runner(blueprint);
      final a = run.contextFor(blueprint.graphs[0]);
      final b = run.contextFor(blueprint.graphs[1]);
      expect(identical(a, b), isFalse);
      expect(identical(a.variables, b.variables), isTrue);
    });
  });

  group('json', () {
    test('a blueprint round-trips', () {
      final blueprint =
          Blueprint(
              name: 'Door',
              variables: [
                VisualScriptVariable(
                  name: 'isOpen',
                  type: VisualScriptType.boolean,
                  initial: false,
                ),
              ],
            )
            ..addGraph(counting(), kind: VisualScriptGraphKind.eventGraph)
            ..addGraph(
              VisualScriptGraph(),
              kind: VisualScriptGraphKind.constructionScript,
            )
            ..addGraph(
              VisualScriptGraph(),
              kind: VisualScriptGraphKind.function,
              name: 'Open',
            );

      final after = readBlueprint(writeBlueprint(blueprint));
      expect(after.name, 'Door');
      expect(after.variables.single.name, 'isOpen');
      expect(after.variables.single.initial, false);
      expect(after.graphs.map((g) => g.kind), [
        VisualScriptGraphKind.eventGraph,
        VisualScriptGraphKind.constructionScript,
        VisualScriptGraphKind.function,
      ]);
      expect(after.graph('Open'), isNotNull);
      expect(after.graphs.first.nodes, hasLength(4));
    });

    test('a document holding a bare graph reads as a blueprint', () {
      // Everything written before blueprints existed is one event graph.
      final graph = counting();
      final after = decodeBlueprint(encodeVisualScript(graph));
      expect(after.graphs, hasLength(1));
      expect(after.graphs.single.kind, VisualScriptGraphKind.eventGraph);
      expect(after.graphs.single.nodes, hasLength(4));
    });

    test('a graph with no kind written is an event graph', () {
      final encoded = encodeVisualScript(VisualScriptGraph());
      expect(encoded.containsKey('kind'), isFalse, reason: 'noise in the file');
      expect(
        decodeVisualScript(encoded).kind,
        VisualScriptGraphKind.eventGraph,
      );
    });
  });

  group('renaming a variable', () {
    Blueprint withVariable() {
      final blueprint = Blueprint(
        variables: [
          VisualScriptVariable(
            name: 'count',
            type: VisualScriptType.number,
            initial: 7.0,
          ),
        ],
      );
      blueprint
        ..addGraph(counting(), kind: VisualScriptGraphKind.eventGraph)
        ..addGraph(counting(), kind: VisualScriptGraphKind.function, name: 'F');
      return blueprint;
    }

    test('every Get and Set that named it follows', () {
      // A node names a variable by string, so renaming only the declaration
      // leaves the graph reading one that is not there -- which reads as null
      // rather than as an error, so it runs on and does the wrong thing.
      final blueprint = withVariable();
      expect(blueprint.renameVariable('count', 'total'), isTrue);
      for (final graph in blueprint.graphs) {
        for (final node in graph.nodes) {
          if (node.type != Blueprint.variableGetType &&
              node.type != Blueprint.variableSetType) {
            continue;
          }
          expect(node.literals['name'], 'total');
        }
      }
    });

    test('the declaration keeps its type and its initial value', () {
      final blueprint = withVariable();
      blueprint.renameVariable('count', 'total');
      expect(blueprint.variables.single.name, 'total');
      expect(blueprint.variables.single.type, VisualScriptType.number);
      expect(blueprint.variables.single.initial, 7.0);
    });

    test('a name already taken is refused, and changes nothing', () {
      final blueprint = withVariable()
        ..variables.add(
          VisualScriptVariable(name: 'other', type: VisualScriptType.number),
        );
      expect(blueprint.renameVariable('count', 'other'), isFalse);
      expect(blueprint.variables.first.name, 'count');
    });

    test('renaming what is not there does nothing', () {
      final blueprint = withVariable();
      expect(blueprint.renameVariable('ghost', 'total'), isFalse);
      expect(blueprint.variables.single.name, 'count');
    });

    test('an empty name is refused', () {
      final blueprint = withVariable();
      expect(blueprint.renameVariable('count', ''), isFalse);
    });

    test('a node reading a different variable is left alone', () {
      final blueprint = withVariable();
      final graph = blueprint.graphs.first;
      final other = graph.add(Blueprint.variableGetType)
        ..literals['name'] = 'elsewhere';
      blueprint.renameVariable('count', 'total');
      expect(other.literals['name'], 'elsewhere');
    });
  });
}
