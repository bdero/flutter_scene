// Watching a graph run. A graph that does nothing looks exactly like a graph
// that does the wrong thing, so what matters here is that a trace can tell
// them apart: which branch fired, what went down each wire, and what never
// ran at all.

import 'package:scene/visual_script.dart';
import 'package:test/test.dart';

/// A graph that branches on a variable and sets another either way, so a run
/// leaves a visible fork. Returns the graph and the node ids worth naming.
({VisualScriptGraph graph, int branch, int read, int yes, int no}) branching({
  required bool flag,
}) {
  final graph = VisualScriptGraph(
    variables: [
      VisualScriptVariable(
        name: 'taken',
        type: VisualScriptType.string,
        initial: '',
      ),
      VisualScriptVariable(
        name: 'flag',
        type: VisualScriptType.boolean,
        initial: flag,
      ),
    ],
  );

  final start = graph.add('event.start');
  final read = graph.add('var.get')..literals['name'] = 'flag';
  final branch = graph.add('flow.branch');
  final yes = graph.add('var.set')
    ..literals['name'] = 'taken'
    ..literals['value'] = 'yes';
  final no = graph.add('var.set')
    ..literals['name'] = 'taken'
    ..literals['value'] = 'no';

  graph
    ..connect(
      VisualScriptLink(
        fromNode: start.id,
        fromPin: 'then',
        toNode: branch.id,
        toPin: 'exec',
      ),
    )
    ..connect(
      VisualScriptLink(
        fromNode: read.id,
        fromPin: 'value',
        toNode: branch.id,
        toPin: 'condition',
      ),
    )
    ..connect(
      VisualScriptLink(
        fromNode: branch.id,
        fromPin: 'true',
        toNode: yes.id,
        toPin: 'exec',
      ),
    )
    ..connect(
      VisualScriptLink(
        fromNode: branch.id,
        fromPin: 'false',
        toNode: no.id,
        toPin: 'exec',
      ),
    );

  return (
    graph: graph,
    branch: branch.id,
    read: read.id,
    yes: yes.id,
    no: no.id,
  );
}

({VisualScriptContext context, VisualScriptTrace trace}) run(
  VisualScriptGraph graph,
) {
  final trace = VisualScriptTrace();
  final context = VisualScriptContext(
    graph: graph,
    host: NullVisualScriptHost(),
    trace: trace,
  );
  VisualScriptInterpreter(
    standardVisualScriptRegistry(),
  ).fire(context, 'event.start');
  return (context: context, trace: trace);
}

/// A graph that runs itself forever, for the budget cases.
VisualScriptGraph runaway() {
  final graph = VisualScriptGraph();
  final start = graph.add('event.start');
  final sequence = graph.add('flow.sequence');
  graph.connect(
    VisualScriptLink(
      fromNode: start.id,
      fromPin: 'then',
      toNode: sequence.id,
      toPin: 'exec',
    ),
  );
  // A hand-edited cycle; the canvas will not let one be drawn.
  graph.links.add(
    VisualScriptLink(
      fromNode: sequence.id,
      fromPin: 'a',
      toNode: sequence.id,
      toPin: 'exec',
    ),
  );
  return graph;
}

void main() {
  test('a run with nothing watching records nothing', () {
    final built = branching(flag: true);
    final context = VisualScriptContext(
      graph: built.graph,
      host: NullVisualScriptHost(),
    );
    VisualScriptInterpreter(
      standardVisualScriptRegistry(),
    ).fire(context, 'event.start');
    expect(context.trace, isNull);
    expect(context.variables['taken'], 'yes');
  });

  test('it says which branch was taken', () {
    final yes = branching(flag: true);
    final taken = run(yes.graph).trace;
    expect(taken.didFire(yes.branch, 'true'), isTrue);
    expect(taken.didFire(yes.branch, 'false'), isFalse);

    final no = branching(flag: false);
    final other = run(no.graph).trace;
    expect(other.didFire(no.branch, 'false'), isTrue);
    expect(other.didFire(no.branch, 'true'), isFalse);
  });

  test('it says what did not run, which is half the question', () {
    final built = branching(flag: true);
    final trace = run(built.graph).trace;
    expect(trace.visitedNodes, contains(built.yes));
    expect(trace.visitedNodes, isNot(contains(built.no)));
  });

  test('it labels the wires with the values that went down them', () {
    final built = branching(flag: true);
    final trace = run(built.graph).trace;
    expect(trace.valueOf(built.branch, 'condition'), isTrue);
    expect(trace.valueOf(built.read, 'value'), isTrue);
  });

  test('a pulled value node is recorded even though it never execs', () {
    // The whole reason a data wire is hard to debug: nothing about the exec
    // order mentions it.
    final built = branching(flag: false);
    final trace = run(built.graph).trace;
    expect(trace.visitedNodes, contains(built.read));
    expect(trace.valueOf(built.read, 'value'), isFalse);
  });

  test('the steps come back in the order they happened', () {
    final built = branching(flag: true);
    final trace = run(built.graph).trace;
    final orders = [for (final step in trace.steps) step.order];
    expect(orders, orderedEquals(List.generate(orders.length, (i) => i)));
    expect(trace.steps.first.type, 'event.start');
  });

  test('an error lands on the trace, not only on the context', () {
    final result = run(runaway());
    expect(result.context.error, isNotNull);
    expect(result.trace.error, result.context.error);
    expect(result.trace.describe(), result.context.error);
  });

  test('the step list is bounded but the counts keep going', () {
    final trace = VisualScriptTrace(maxSteps: 10);
    final context = VisualScriptContext(
      graph: runaway(),
      host: NullVisualScriptHost(),
      trace: trace,
    );
    VisualScriptInterpreter(
      standardVisualScriptRegistry(),
    ).fire(context, 'event.start');

    expect(trace.steps, hasLength(10));
    expect(
      trace.stepCount,
      greaterThan(10),
      reason: 'a runaway graph must still report how far it got',
    );
  });

  test('clearing it leaves nothing behind', () {
    final trace = run(branching(flag: true).graph).trace;
    expect(trace.stepCount, greaterThan(0));
    trace.clear();
    expect(trace.steps, isEmpty);
    expect(trace.values, isEmpty);
    expect(trace.firedExec, isEmpty);
    expect(trace.visitedNodes, isEmpty);
    expect(trace.stepCount, 0);
    expect(trace.error, isNull);
    expect(trace.describe(), 'Nothing ran.');
  });

  test('the summary says what a status line needs', () {
    final trace = run(branching(flag: true).graph).trace;
    expect(trace.describe(), contains('nodes ran'));
    expect(trace.describe(), contains('on the wires'));
  });
}
