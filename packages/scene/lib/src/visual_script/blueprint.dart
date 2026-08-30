/// A blueprint: a class you can spawn, written as graphs.
///
/// A single graph is a script attached to one object. A blueprint is the thing
/// Unreal means by the word — a class, with variables that belong to it and
/// several graphs that run at different times: a construction script that
/// builds an instance, an event graph that runs it, and functions and macros
/// the other two call.
///
/// The split matters because the two halves have different lives.
/// Construction runs once while the instance is being made, before anything is
/// live, which is where "how many barrels does this crate spawn" belongs.
/// The event graph runs every frame afterwards, which is where "what happens
/// when the player touches it" belongs. Putting both in one graph is how you
/// end up rebuilding the barrels sixty times a second.
///
/// Variables belong to the blueprint rather than to a graph, so the function
/// that decrements a counter and the event graph that reads it are looking at
/// the same counter. Graphs share one variables map and keep their own node
/// state, since node ids are only unique inside a graph.
library;

import 'visual_script_graph.dart';
import 'visual_script_library.dart';
import 'visual_script_runtime.dart';
import 'visual_script_trace.dart';

/// The name an event graph is given when nothing else names it.
const String defaultEventGraphName = 'Event Graph';

/// The name a construction script is given when nothing else names it.
const String defaultConstructionScriptName = 'Construction Script';

/// What kind of thing a blueprint is.
///
/// Unreal's distinction, and it is a real one: these are not four flavours of
/// the same asset, they are four different answers to "what does this
/// produce". A class produces objects, an interface produces nothing and only
/// says what a class must be able to do, and a macro library produces nothing
/// either -- it is a shelf of graphs other blueprints paste in.
enum BlueprintKind {
  /// A class you can place and spawn: graphs plus the variables they share.
  blueprintClass('Blueprint Class'),

  /// A piece of interface, whose graphs run against widgets rather than a
  /// node in the world.
  widgetBlueprint('Widget Blueprint'),

  /// A set of function signatures a blueprint promises to implement, with no
  /// bodies of its own.
  ///
  /// The point is to let one graph call another blueprint it knows nothing
  /// about beyond the promise -- a door and a chest can both be Openable
  /// without either knowing the other exists.
  blueprintInterface('Blueprint Interface'),

  /// A shelf of macros for other blueprints to use.
  macroLibrary('Blueprint Macro Library');

  const BlueprintKind(this.label);

  /// What the editor calls this kind.
  final String label;

  /// The kind named [name], or [blueprintClass] when it is not one of these.
  ///
  /// A document naming a kind this build does not know is read as a plain
  /// class rather than refused: its graphs are still graphs.
  static BlueprintKind parse(String? name) =>
      values.where((kind) => kind.name == name).firstOrNull ??
      BlueprintKind.blueprintClass;

  /// Which graph kinds this kind of blueprint may hold.
  ///
  /// An interface has signatures and no bodies, and a macro library has
  /// macros and nothing to run them, so neither has an event graph. Saying so
  /// here keeps the editor from offering to add one.
  Set<VisualScriptGraphKind> get allowedGraphKinds => switch (this) {
    BlueprintKind.blueprintInterface => const {VisualScriptGraphKind.function},
    BlueprintKind.macroLibrary => const {VisualScriptGraphKind.macro},
    _ => const {
      VisualScriptGraphKind.eventGraph,
      VisualScriptGraphKind.constructionScript,
      VisualScriptGraphKind.function,
      VisualScriptGraphKind.macro,
    },
  };
}

/// What a blueprint extends when nobody says: an object placed in a scene.
const String defaultBlueprintParent = 'node';

/// A class defined as graphs.
/// {@category Visual scripting}
class Blueprint {
  Blueprint({
    this.name = '',
    this.kind = BlueprintKind.blueprintClass,
    this.parentClass = defaultBlueprintParent,
    List<VisualScriptVariable>? variables,
    List<VisualScriptGraph>? graphs,
  }) : variables = variables ?? [],
       graphs = graphs ?? [];

  /// A blueprint holding one event graph, which is what a script that has not
  /// grown past one graph is.
  factory Blueprint.of(
    VisualScriptGraph graph, {
    String name = '',
  }) => Blueprint(
    name: name,
    // The graph's own variables become the blueprint's, since a blueprint is
    // where variables live once there is one.
    variables: List.of(graph.variables),
    graphs: [
      graph
        ..name = graph.name.isEmpty ? defaultEventGraphName : graph.name
        ..kind = VisualScriptGraphKind.eventGraph,
    ],
  );

  /// What the blueprint is called.
  String name;

  /// What kind of thing it is.
  BlueprintKind kind;

  /// What it extends: the key of a node kind or a component type.
  ///
  /// A string rather than a type, because the set of things a blueprint can
  /// extend is the set of components this build has registered -- which is
  /// open, since a project's own components join it. A parent this build does
  /// not know is kept rather than dropped, so opening a teammate's blueprint
  /// without their components does not quietly reparent it.
  String parentClass;

  /// The variables every graph in it shares.
  final List<VisualScriptVariable> variables;

  /// Its graphs, in the order an editor lists them.
  final List<VisualScriptGraph> graphs;

  /// Every graph of [kind].
  Iterable<VisualScriptGraph> graphsOfKind(VisualScriptGraphKind kind) =>
      graphs.where((graph) => graph.kind == kind);

  /// The graph called [name], of any kind, or null.
  VisualScriptGraph? graph(String name) {
    for (final graph in graphs) {
      if (graph.name == name) return graph;
    }
    return null;
  }

  /// The function or macro called [name], or null.
  ///
  /// Only these two are callable: an event graph is entered by its events and
  /// a construction script by being built, and calling either from a wire
  /// would run something whose whole point is *when* it runs.
  VisualScriptGraph? routine(String name) {
    for (final graph in graphs) {
      if (graph.name != name) continue;
      if (graph.kind == VisualScriptGraphKind.function ||
          graph.kind == VisualScriptGraphKind.macro) {
        return graph;
      }
    }
    return null;
  }

  /// Adds [graph] under a name no other graph in this blueprint has.
  ///
  /// Names are how a function is called and how an editor tab is labelled, so
  /// two graphs sharing one is a call with two possible answers.
  VisualScriptGraph addGraph(
    VisualScriptGraph graph, {
    required VisualScriptGraphKind kind,
    String? name,
  }) {
    graph
      ..kind = kind
      ..name = uniqueGraphName(name ?? kind.label);
    graphs.add(graph);
    return graph;
  }

  /// A name like [wanted] that no graph here already has.
  String uniqueGraphName(String wanted) {
    final taken = {for (final graph in graphs) graph.name};
    if (!taken.contains(wanted)) return wanted;
    for (var i = 2; ; i++) {
      final candidate = '$wanted $i';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// Renames variable [from] to [to], across every graph that reads it.
  ///
  /// Returns false when there is no such variable or the new name is taken.
  ///
  /// The Get and Set nodes name a variable by string, so renaming only the
  /// declaration leaves every node reading one that no longer exists — and an
  /// unset variable reads as null rather than as an error, so the script goes
  /// on running and quietly does the wrong thing.
  bool renameVariable(String from, String to) {
    if (from == to) return false;
    if (to.isEmpty) return false;
    if (variables.any((variable) => variable.name == to)) return false;
    final index = variables.indexWhere((variable) => variable.name == from);
    if (index < 0) return false;
    final existing = variables[index];
    variables[index] = VisualScriptVariable(
      name: to,
      type: existing.type,
      initial: existing.initial,
    );
    for (final graph in graphs) {
      for (final node in graph.nodes) {
        if (node.type != variableGetType && node.type != variableSetType) {
          continue;
        }
        if (node.literals['name'] == from) node.literals['name'] = to;
      }
    }
    return true;
  }

  /// The node type that reads a variable.
  static const String variableGetType = 'var.get';

  /// The node type that writes one.
  static const String variableSetType = 'var.set';

  /// A deep copy.
  Blueprint copy() => Blueprint(
    name: name,
    variables: [
      for (final variable in variables)
        VisualScriptVariable(
          name: variable.name,
          type: variable.type,
          initial: variable.initial,
        ),
    ],
    graphs: [for (final graph in graphs) graph.copy()],
  );
}

/// Runs a [Blueprint]: its construction script once, its event graph every
/// tick, and its functions when something calls them.
///
/// Holds one [VisualScriptContext] per graph over a single shared variables
/// map. Per graph because node state — a delay's remaining time, a Do Once's
/// latch — is keyed by node id, and node ids are only unique within a graph;
/// shared variables because a variable belongs to the blueprint.
/// {@category Visual scripting}
class BlueprintRunner {
  BlueprintRunner({
    required this.blueprint,
    required this.host,
    VisualScriptRegistry? registry,
    this.trace,
  }) : registry = registry ?? standardVisualScriptRegistry() {
    _interpreter = VisualScriptInterpreter(this.registry);
    for (final variable in blueprint.variables) {
      variables[variable.name] = variable.initial;
    }
  }

  final Blueprint blueprint;
  final VisualScriptHost host;
  final VisualScriptRegistry registry;

  /// Where to record what a run did, or null to record nothing.
  final VisualScriptTrace? trace;

  /// The variables every graph shares.
  final Map<String, Object?> variables = {};

  final Map<VisualScriptGraph, VisualScriptContext> _contexts = {};
  late final VisualScriptInterpreter _interpreter;

  /// Whether the construction script has run.
  bool get isBuilt => _built;
  bool _built = false;

  /// Routines currently running, so a function that calls itself is stopped
  /// rather than recursing until the stack goes.
  final Set<String> _running = {};

  /// The context for [graph], made on first use.
  VisualScriptContext contextFor(VisualScriptGraph graph) =>
      _contexts[graph] ??= VisualScriptContext(
        graph: graph,
        host: host,
        trace: trace,
        variables: variables,
      );

  /// Runs every construction script, once for the life of this runner.
  ///
  /// Returns how many events fired. Calling it again does nothing, which is
  /// what makes it safe to call from a build path that may run twice.
  int build() {
    if (_built) return 0;
    _built = true;
    var fired = 0;
    for (final graph in blueprint.graphsOfKind(
      VisualScriptGraphKind.constructionScript,
    )) {
      fired += _interpreter.fire(contextFor(graph), eventType);
    }
    return fired;
  }

  /// Fires [eventType] on every event graph.
  ///
  /// Returns how many events fired, so a caller can tell a blueprint with no
  /// such event from one that ran.
  int fire(String event) {
    var fired = 0;
    for (final graph in blueprint.graphsOfKind(
      VisualScriptGraphKind.eventGraph,
    )) {
      fired += _interpreter.fire(contextFor(graph), event);
    }
    return fired;
  }

  /// Runs the function or macro called [name].
  ///
  /// Returns false when there is no such routine, or when it is already
  /// running — a routine that calls itself has no base case a graph can
  /// express, so the second entry is refused rather than allowed to recurse.
  bool call(String name) {
    final graph = blueprint.routine(name);
    if (graph == null) return false;
    if (!_running.add(name)) {
      contextFor(graph).error = 'the routine "$name" calls itself';
      return false;
    }
    try {
      _interpreter.fire(contextFor(graph), eventType);
      return true;
    } finally {
      _running.remove(name);
    }
  }

  /// The event type a construction script, function or macro is entered by.
  ///
  /// One entry point, so the node that starts a routine is the same node that
  /// starts a script: there is nothing else it could sensibly be.
  static const String eventType = 'event.start';

  /// The first error any of the graphs reported, or null.
  String? get error {
    for (final context in _contexts.values) {
      final failure = context.error;
      if (failure != null) return failure;
    }
    return null;
  }

  /// Clears every graph's per-tick bookkeeping.
  void beginTick() {
    trace?.clear();
    for (final context in _contexts.values) {
      context.steps = 0;
    }
  }
}
