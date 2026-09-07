/// Running a visual script on a node.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:scene/visual_script.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/visual_script/scene_visual_script_host.dart';
import 'package:flutter_scene/src/visual_script/scene_visual_script_nodes.dart';
import 'package:flutter_scene/src/node.dart';

/// Runs a [VisualScriptGraph] on the node it is attached to.
///
/// Fires On Start once, On Tick every frame, and On Signal whenever
/// [raise] is called. The graph's own state (its variables, a Delay's
/// remaining time, a Do Once's latch) lives in one [VisualScriptContext] that
/// persists across ticks, so a script written as a state machine behaves like
/// one.
///
/// An error in the graph -- a loop in the wires, an unknown node type -- is
/// reported once and then the component stops running it, rather than
/// repeating the same failure sixty times a second.
/// {@category Visual scripting}
class VisualScriptComponent extends Component {
  /// Runs [blueprint], or the single [graph] that is a blueprint with one
  /// event graph in it.
  ///
  /// Both spellings exist because most scripts are one graph and saying so
  /// should stay one line, while a script that has grown a construction
  /// script and three functions is a blueprint and wants to be handed one.
  VisualScriptComponent({
    Blueprint? blueprint,
    VisualScriptGraph? graph,
    VisualScriptRegistry? registry,
    this.onAction,
    this.onLog,
  }) : assert(
         blueprint == null || graph == null,
         'Pass a blueprint or a graph, not both: the graph would be the '
         'blueprint\'s or a second one, and there is no reading of that.',
       ),
       _blueprint = blueprint ?? Blueprint.of(graph ?? VisualScriptGraph()),
       registry = registry ?? sceneVisualScriptRegistry();

  /// The blueprint this runs. Replacing it restarts from a fresh run, so an
  /// edit in the editor takes effect without a scene reload.
  Blueprint get blueprint => _blueprint;
  set blueprint(Blueprint value) {
    _blueprint = value;
    _reset();
  }

  Blueprint _blueprint;

  /// The first event graph, which is the whole script for anything that has
  /// not grown past one.
  ///
  /// Setting it replaces that graph and leaves the blueprint's other graphs
  /// alone, so wiring an event does not delete a construction script.
  VisualScriptGraph get graph {
    for (final candidate in _blueprint.graphs) {
      if (candidate.kind == VisualScriptGraphKind.eventGraph) return candidate;
    }
    final added = _blueprint.addGraph(
      VisualScriptGraph(),
      kind: VisualScriptGraphKind.eventGraph,
      name: defaultEventGraphName,
    );
    return added;
  }

  set graph(VisualScriptGraph value) {
    final graphs = _blueprint.graphs;
    final index = graphs.indexWhere(
      (candidate) => candidate.kind == VisualScriptGraphKind.eventGraph,
    );
    value
      ..kind = VisualScriptGraphKind.eventGraph
      ..name = value.name.isEmpty ? defaultEventGraphName : value.name;
    if (index < 0) {
      graphs.add(value);
    } else {
      graphs[index] = value;
    }
    // The variables a bare graph carries are the blueprint's once it is in
    // one, or a script assembled graph-first would run with none.
    for (final variable in value.variables) {
      if (_blueprint.variables.any((v) => v.name == variable.name)) continue;
      _blueprint.variables.add(variable);
    }
    _reset();
  }

  /// The node types the graph may use.
  final VisualScriptRegistry registry;

  /// Handles an action the built-in nodes do not cover, so an application can
  /// extend a graph's reach without a new node type.
  final Object? Function(String action, Map<String, Object?> arguments)?
  onAction;

  /// Where Print goes. Null prints through `debugPrint`.
  final void Function(String message)? onLog;

  /// Whether the graph ticks. False leaves its state intact, so toggling it
  /// pauses a script rather than restarting it.
  bool running = true;

  VisualScriptTrace? _trace;

  /// What the last tick did, or null when nothing is watching.
  ///
  /// A graph that does nothing looks exactly like a graph that does the wrong
  /// thing, and no amount of staring at the canvas tells them apart. This is
  /// what an editor draws over it: which nodes ran, which branch of a Branch
  /// was taken, and the number that went down each wire.
  VisualScriptTrace? get trace => _trace;

  /// Whether the run is traced.
  ///
  /// Off by default. Turning it on rebuilds the context, which restarts the
  /// script -- the trace is fixed to a run at construction so the hot path
  /// stays a null check rather than a flag test per node.
  bool get tracing => _trace != null;
  set tracing(bool value) {
    if (value == tracing) return;
    _trace = value ? VisualScriptTrace() : null;
    _reset();
  }

  SceneVisualScriptHost? _host;
  BlueprintRunner? _runner;
  bool _started = false;

  /// The error the blueprint stopped on, or null while it is healthy.
  String? get error => _runner?.error;

  /// The blueprint's live variables, for a caller inspecting or seeding one.
  ///
  /// Null until the component is attached, since the variables belong to a
  /// run and a run needs somewhere to happen.
  Map<String, Object?>? get variables =>
      _ensureContext() ? _runner!.variables : null;

  /// Raises a named signal, which every matching On Signal event picks up on
  /// the next tick.
  ///
  /// Deferred to the tick rather than run immediately so a signal raised from
  /// inside a graph, or from a pointer callback mid-frame, sees the same
  /// world every other node that frame does.
  void raise(String signal) {
    if (_ensureContext()) _host!.pendingSignals.add(signal);
  }

  /// Restarts the script from its initial state.
  void restart() {
    if (_ensureContext()) _reset();
  }

  void _reset() {
    _started = false;
    _trace?.clear();
    final host = _host;
    if (host == null) return;
    _runner = BlueprintRunner(
      blueprint: _blueprint,
      host: host,
      registry: registry,
      trace: _trace,
    );
  }

  /// Builds the host and the run state on first use.
  ///
  /// Lazily rather than in [onMount], because a component only mounts once
  /// its node joins a live scene, and a graph is about the node it is on: it
  /// should run on a node driven by hand in a test exactly as it does on one
  /// in a scene.
  bool _ensureContext() {
    if (_runner != null) return true;
    if (!isAttached) return false;
    final host = SceneVisualScriptHost(node, onAction: onAction, onLog: onLog);
    _host = host;
    _runner = BlueprintRunner(
      blueprint: _blueprint,
      host: host,
      registry: registry,
      trace: _trace,
    );
    _started = false;
    return true;
  }

  @override
  void onUnmount() {
    _host = null;
    _runner = null;
    _started = false;
  }

  @override
  void update(double deltaSeconds) {
    if (!running) return;
    if (!_ensureContext()) return;
    final runner = _runner;
    final host = _host;
    if (runner == null || host == null) return;
    if (runner.error != null) return;

    host
      ..deltaSeconds = deltaSeconds
      ..elapsedSeconds = host.elapsedSeconds + deltaSeconds;
    // The budget is per tick, not per lifetime: a graph that legitimately
    // does a lot of work every frame should not run out after a minute. The
    // trace is per tick too, and for the same reason inverted: the
    // interesting run is the current one, and keeping every frame's would
    // grow without bound and bury the frame anyone is looking at.
    runner.beginTick();

    if (!_started) {
      _started = true;
      // Construction first, and only ever once: it says what the instance is,
      // and the events that follow are about what it does.
      runner.build();
      runner.fire(onStart.id);
    }
    runner.fire(onTick.id);

    if (host.pendingSignals.isNotEmpty) {
      final raised = Set.of(host.pendingSignals);
      host.pendingSignals.clear();
      for (final graph in runner.blueprint.graphsOfKind(
        VisualScriptGraphKind.eventGraph,
      )) {
        for (final node in graph.nodes) {
          if (node.type != onSignal.id) continue;
          final name = '${node.literals['name'] ?? 'signal'}';
          if (raised.contains(name)) {
            runner.fire(onSignal.id);
            break;
          }
        }
      }
    }

    final failure = runner.error;
    if (failure != null) {
      final message =
          'visual script: the blueprint on "${node.name}" stopped: $failure';
      final sink = onLog;
      if (sink != null) {
        sink(message);
      } else {
        debugPrint(message);
      }
    }
  }

  @override
  Component? cloneFor(Node cloneOwner) => VisualScriptComponent(
    // A clone gets its own copy: two objects running one script must not
    // share a Delay's countdown or a variable.
    blueprint: _blueprint.copy(),
    registry: registry,
    onAction: onAction,
    onLog: onLog,
  );
}
