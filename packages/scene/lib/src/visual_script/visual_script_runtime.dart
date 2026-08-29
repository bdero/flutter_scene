/// Running a [VisualScriptGraph]: the node-type registry, the evaluation context, and
/// the interpreter that walks the wires.
///
/// Exec pushes and data pulls. An event node starts a run and hands control
/// along its exec output; whenever a node needs an input value it pulls
/// backward through the data wire and evaluates whoever is on the other end.
/// That is the whole execution model, and every node type is written against
/// it rather than against a schedule.
library;

import 'package:vector_math/vector_math.dart';

import 'visual_script_graph.dart';
import 'visual_script_trace.dart';

/// What a node can do while it runs.
///
/// The host supplies this. Everything a graph can reach outside its own
/// values goes through it, so the interpreter itself has no idea what a scene
/// is and the same graph runs in a test with a stub.
/// {@category Visual scripting}
abstract class VisualScriptHost {
  /// Seconds since the previous tick, for the nodes that integrate.
  double get deltaSeconds;

  /// Seconds since the graph started.
  double get elapsedSeconds;

  /// Reads a scene value by a dotted path the host understands
  /// (`position`, `rotation.y`, `target.position`).
  Object? read(String path);

  /// Writes one, and reports whether anything was written: a graph pointed at
  /// a node that no longer exists should say so rather than fail silently.
  bool write(String path, Object? value);

  /// Calls a host action by name with named arguments, returning whatever it
  /// produces. This is where playing a sound, spawning a prefab, or firing an
  /// application callback lands.
  Object? invoke(String action, Map<String, Object?> arguments);

  /// Reports a message from a Print node.
  void log(String message);
}

/// A host that does nothing, for a graph exercised without a scene.
/// {@category Visual scripting}
class NullVisualScriptHost implements VisualScriptHost {
  NullVisualScriptHost({this.deltaSeconds = 1 / 60, this.elapsedSeconds = 0});

  @override
  double deltaSeconds;

  @override
  double elapsedSeconds;

  /// Everything [log] was given, in order.
  final List<String> messages = [];

  /// Every [invoke] made, in order.
  final List<(String, Map<String, Object?>)> calls = [];

  /// Values [read] and [write] see, keyed by path.
  final Map<String, Object?> values = {};

  @override
  Object? read(String path) => values[path];

  @override
  bool write(String path, Object? value) {
    values[path] = value;
    return true;
  }

  @override
  Object? invoke(String action, Map<String, Object?> arguments) {
    calls.add((action, arguments));
    return null;
  }

  @override
  void log(String message) => messages.add(message);
}

/// The state one run of a graph carries.
/// {@category Visual scripting}
class VisualScriptContext {
  VisualScriptContext({required this.graph, required this.host, this.trace}) {
    for (final variable in graph.variables) {
      variables[variable.name] = variable.initial;
    }
  }

  final VisualScriptGraph graph;
  final VisualScriptHost host;

  /// Where to record what the run did, or null to record nothing.
  ///
  /// Null by default, so a graph nobody is watching pays a null check per
  /// node rather than the bookkeeping.
  final VisualScriptTrace? trace;

  /// The graph's variables, seeded from their initial values.
  final Map<String, Object?> variables = {};

  /// Per-node scratch, for the node types that remember something between
  /// ticks (a delay's remaining time, a Do Once's latch).
  final Map<int, Object?> nodeState = {};

  /// How many exec steps this run has taken, so a cycle in the wires stops
  /// rather than hangs the frame.
  int steps = 0;

  /// The step budget one run gets. A graph is authored by hand, so anything
  /// past a few thousand steps in one tick is a loop the author did not mean.
  static const int maxSteps = 10000;

  String? _error;

  /// Set when the budget runs out, so the caller can surface it once rather
  /// than every frame. Mirrored into [trace], so a canvas showing the run
  /// shows why it stopped without being handed the context as well.
  String? get error => _error;
  set error(String? value) {
    _error = value;
    trace?.error = value;
  }

  /// Nodes whose data pull is currently in progress.
  ///
  /// Re-entering one is a cycle in the data wires, which unlike an exec loop
  /// cannot be caught by a step budget: the pull is recursive, so it
  /// overflows the stack long before any count is reached. A node evaluated
  /// twice in one pull because two inputs share a source is not in here at
  /// the second visit, so the diamond that is legitimate stays legal.
  final Set<int> pulling = {};
}

/// What a node's evaluation produced.
/// {@category Visual scripting}
typedef VisualScriptResult = ({
  /// Values on the node's output data pins, keyed by pin id.
  Map<String, Object?> outputs,

  /// The exec outputs to follow, in order. Empty stops this branch.
  ///
  /// A list rather than a single pin because a node that fans out (Sequence)
  /// has to be expressible without reaching into the interpreter: it names
  /// its branches and they are run in the order given.
  List<String> next,
});

/// A registered node type: what it looks like, and what it does.
/// {@category Visual scripting}
class VisualScriptNodeType {
  const VisualScriptNodeType({
    required this.id,
    required this.label,
    required this.category,
    required this.pins,
    required this.evaluate,
    this.doc = '',
    this.isEvent = false,
  });

  /// The stable id a [VisualScriptNodeSpec] names.
  final String id;

  /// The title drawn on the node.
  final String label;

  /// The palette group.
  final String category;

  /// What the node is for, shown in the palette and on hover.
  final String doc;

  /// Whether this node starts a run rather than being reached by one. Events
  /// have no exec input.
  final bool isEvent;

  final List<VisualScriptPin> pins;

  /// Runs the node. [inputs] holds every input pin's resolved value; the
  /// result carries the output values and which exec pin to follow.
  final VisualScriptResult Function(
    VisualScriptContext context,
    VisualScriptNodeSpec node,
    Map<String, Object?> inputs,
  )
  evaluate;

  Iterable<VisualScriptPin> get inputs => pins.where((pin) => pin.isInput);
  Iterable<VisualScriptPin> get outputs => pins.where((pin) => !pin.isInput);

  VisualScriptPin? pin(String id) {
    for (final pin in pins) {
      if (pin.id == id) return pin;
    }
    return null;
  }
}

/// The node types a graph may use.
/// {@category Visual scripting}
class VisualScriptRegistry {
  final Map<String, VisualScriptNodeType> _types = {};

  void register(VisualScriptNodeType type) {
    if (_types.containsKey(type.id)) {
      throw StateError(
        'Visual script node type already registered: ${type.id}',
      );
    }
    _types[type.id] = type;
  }

  void registerAll(Iterable<VisualScriptNodeType> types) =>
      types.forEach(register);

  VisualScriptNodeType? operator [](String id) => _types[id];

  Iterable<VisualScriptNodeType> get all => _types.values;

  /// The registered categories, in first-registration order.
  List<String> get categories {
    final seen = <String>[];
    for (final type in _types.values) {
      if (!seen.contains(type.category)) seen.add(type.category);
    }
    return seen;
  }

  List<VisualScriptNodeType> inCategory(String category) => [
    for (final type in _types.values)
      if (type.category == category) type,
  ];
}

/// Walks a graph.
/// {@category Visual scripting}
class VisualScriptInterpreter {
  VisualScriptInterpreter(this.registry);

  final VisualScriptRegistry registry;

  /// Runs every node of type [eventType] as a starting point.
  ///
  /// Returns how many events fired, so a caller can tell a graph with no
  /// matching event from one that ran.
  int fire(VisualScriptContext context, String eventType) {
    var fired = 0;
    for (final node in context.graph.nodes) {
      if (node.type != eventType) continue;
      fired++;
      _run(context, node);
    }
    return fired;
  }

  /// Runs [start], then every exec branch it names, in order.
  ///
  /// An explicit work stack rather than recursion. A node may name several
  /// branches and each has to finish before the next begins, which is what a
  /// stack gives when the branches are pushed in reverse; recursion would
  /// give the same order but put the step budget's worth of frames on the
  /// real stack, and the budget is deliberately larger than that is safe.
  void _run(VisualScriptContext context, VisualScriptNodeSpec start) {
    final pending = <VisualScriptNodeSpec>[start];
    while (pending.isNotEmpty) {
      if (++context.steps > VisualScriptContext.maxSteps) {
        context.error =
            'The graph ran for ${VisualScriptContext.maxSteps} steps without '
            'finishing, which is a loop in the exec wires.';
        return;
      }
      final node = pending.removeLast();
      final type = registry[node.type];
      if (type == null) {
        context.error = 'Unknown node type "${node.type}".';
        return;
      }
      final inputs = _resolveInputs(context, node, type);
      final result = type.evaluate(context, node, inputs);
      final trace = context.trace;
      if (trace != null) {
        trace.recordStep(node.id, node.type);
        for (final entry in inputs.entries) {
          trace.recordValue(node.id, entry.key, entry.value);
        }
        for (final entry in result.outputs.entries) {
          trace.recordValue(node.id, entry.key, entry.value);
        }
        for (final pin in result.next) {
          trace.recordExec(node.id, pin);
        }
      }
      if (context.error != null) return;

      // Reverse, so the first branch named is the first popped and its whole
      // subtree runs before the second begins.
      for (var i = result.next.length - 1; i >= 0; i--) {
        // An exec output carries one wire (connect enforces it), but reading
        // them all keeps a hand-edited document from silently dropping one.
        for (final link in context.graph.outputsFrom(node.id, result.next[i])) {
          final target = context.graph.node(link.toNode);
          if (target != null) pending.add(target);
        }
      }
    }
  }

  /// Resolves every input pin of [node]: the wire if there is one, otherwise
  /// the literal typed into it, otherwise the pin's default.
  Map<String, Object?> _resolveInputs(
    VisualScriptContext context,
    VisualScriptNodeSpec node,
    VisualScriptNodeType type,
  ) {
    final values = <String, Object?>{};
    for (final pin in type.inputs) {
      if (pin.type == VisualScriptType.exec) continue;
      final link = context.graph.inputTo(node.id, pin.id);
      if (link != null) {
        values[pin.id] = evaluateOutput(context, link.fromNode, link.fromPin);
        continue;
      }
      values[pin.id] = node.literals.containsKey(pin.id)
          ? node.literals[pin.id]
          : pin.defaultValue;
    }
    return values;
  }

  /// Pulls the value of an output pin, evaluating the node behind it.
  ///
  /// Pure data nodes are evaluated on demand rather than scheduled, so a
  /// value nothing asks for is never computed. A node reached twice in one
  /// pull is evaluated twice; caching would need a notion of when a value
  /// goes stale, and at the size a hand-authored graph reaches, recomputing a
  /// multiply is cheaper than tracking that.
  Object? evaluateOutput(
    VisualScriptContext context,
    int nodeId,
    String pinId,
  ) {
    if (!context.pulling.add(nodeId)) {
      context.error =
          'Node $nodeId feeds itself, which is a cycle in the data wires.';
      return null;
    }
    try {
      if (++context.steps > VisualScriptContext.maxSteps) {
        context.error =
            'The graph ran for ${VisualScriptContext.maxSteps} steps without '
            'finishing.';
        return null;
      }
      final node = context.graph.node(nodeId);
      if (node == null) return null;
      final type = registry[node.type];
      if (type == null) {
        context.error = 'Unknown node type "${node.type}".';
        return null;
      }
      final inputs = _resolveInputs(context, node, type);
      final outputs = type.evaluate(context, node, inputs).outputs;
      // A pulled node is recorded too. Its value is what a data wire is
      // carrying, and a wire with no label is the thing a trace exists to
      // fix; that a value node never appears in the exec order is the point.
      final trace = context.trace;
      if (trace != null) {
        trace.recordStep(node.id, node.type);
        for (final entry in inputs.entries) {
          trace.recordValue(node.id, entry.key, entry.value);
        }
        for (final entry in outputs.entries) {
          trace.recordValue(node.id, entry.key, entry.value);
        }
      }
      return outputs[pinId];
    } finally {
      context.pulling.remove(nodeId);
    }
  }
}

/// Coerces [value] to a double, or [fallback].
/// {@category Visual scripting}
double scriptNumber(Object? value, [double fallback = 0]) => switch (value) {
  double v => v,
  int v => v.toDouble(),
  bool v => v ? 1 : 0,
  String v => double.tryParse(v) ?? fallback,
  _ => fallback,
};

/// Coerces [value] to an int, or [fallback].
/// {@category Visual scripting}
int scriptInteger(Object? value, [int fallback = 0]) => switch (value) {
  int v => v,
  double v => v.round(),
  bool v => v ? 1 : 0,
  String v => int.tryParse(v) ?? fallback,
  _ => fallback,
};

/// Coerces [value] to a bool.
///
/// A number is true when nonzero and a string when non-empty, which is what a
/// Branch fed a count or a name is asking for.
/// {@category Visual scripting}
bool scriptBool(Object? value, [bool fallback = false]) => switch (value) {
  bool v => v,
  double v => v != 0,
  int v => v != 0,
  String v => v.isNotEmpty,
  null => fallback,
  _ => true,
};

/// Coerces [value] to a vector, or zero.
/// {@category Visual scripting}
Vector3 scriptVector(Object? value) => switch (value) {
  Vector3 v => v,
  double v => Vector3.all(v),
  int v => Vector3.all(v.toDouble()),
  _ => Vector3.zero(),
};

/// Renders [value] the way a Print node shows it.
/// {@category Visual scripting}
String scriptString(Object? value) => switch (value) {
  null => 'null',
  Vector3 v =>
    '(${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, '
        '${v.z.toStringAsFixed(3)})',
  _ => '$value',
};
