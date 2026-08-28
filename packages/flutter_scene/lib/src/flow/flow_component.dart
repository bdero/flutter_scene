/// Running a visual script on a node.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:scene/flow.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/flow/scene_flow_host.dart';
import 'package:flutter_scene/src/flow/scene_flow_nodes.dart';
import 'package:flutter_scene/src/node.dart';

/// Runs a [FlowGraph] on the node it is attached to.
///
/// Fires On Start once, On Tick every frame, and On Signal whenever
/// [raise] is called. The graph's own state (its variables, a Delay's
/// remaining time, a Do Once's latch) lives in one [FlowContext] that
/// persists across ticks, so a script written as a state machine behaves like
/// one.
///
/// An error in the graph -- a loop in the wires, an unknown node type -- is
/// reported once and then the component stops running it, rather than
/// repeating the same failure sixty times a second.
/// {@category Flow}
class FlowComponent extends Component {
  FlowComponent({
    FlowGraph? graph,
    FlowRegistry? registry,
    this.onAction,
    this.onLog,
  }) : _graph = graph ?? FlowGraph(),
       registry = registry ?? sceneFlowRegistry();

  /// The script this runs. Replacing it restarts from a fresh context, so an
  /// edit in the editor takes effect without a scene reload.
  FlowGraph get graph => _graph;
  set graph(FlowGraph value) {
    _graph = value;
    _reset();
  }

  FlowGraph _graph;

  /// The node types the graph may use.
  final FlowRegistry registry;

  /// Handles an action the built-in nodes do not cover, so an application can
  /// extend a graph's reach without a new node type.
  final Object? Function(String action, Map<String, Object?> arguments)?
  onAction;

  /// Where Print goes. Null prints through `debugPrint`.
  final void Function(String message)? onLog;

  /// Whether the graph ticks. False leaves its state intact, so toggling it
  /// pauses a script rather than restarting it.
  bool running = true;

  SceneFlowHost? _host;
  FlowContext? _context;
  late final FlowInterpreter _interpreter = FlowInterpreter(registry);
  bool _started = false;

  /// The error the graph stopped on, or null while it is healthy.
  String? get error => _context?.error;

  /// The graph's live variables, for a caller inspecting or seeding one.
  ///
  /// Null until the component is attached, since the variables belong to a
  /// run and a run needs somewhere to happen.
  Map<String, Object?>? get variables =>
      _ensureContext() ? _context!.variables : null;

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
    final host = _host;
    if (host == null) return;
    _context = FlowContext(graph: _graph, host: host);
  }

  /// Builds the host and the run state on first use.
  ///
  /// Lazily rather than in [onMount], because a component only mounts once
  /// its node joins a live scene, and a graph is about the node it is on: it
  /// should run on a node driven by hand in a test exactly as it does on one
  /// in a scene.
  bool _ensureContext() {
    if (_context != null) return true;
    if (!isAttached) return false;
    final host = SceneFlowHost(node, onAction: onAction, onLog: onLog);
    _host = host;
    _context = FlowContext(graph: _graph, host: host);
    _started = false;
    return true;
  }

  @override
  void onUnmount() {
    _host = null;
    _context = null;
    _started = false;
  }

  @override
  void update(double deltaSeconds) {
    if (!running) return;
    if (!_ensureContext()) return;
    final context = _context;
    final host = _host;
    if (context == null || host == null) return;
    if (context.error != null) return;

    host
      ..deltaSeconds = deltaSeconds
      ..elapsedSeconds = host.elapsedSeconds + deltaSeconds;
    // The budget is per tick, not per lifetime: a graph that legitimately
    // does a lot of work every frame should not run out after a minute.
    context.steps = 0;

    if (!_started) {
      _started = true;
      _interpreter.fire(context, onStart.id);
    }
    _interpreter.fire(context, onTick.id);

    if (host.pendingSignals.isNotEmpty) {
      final raised = Set.of(host.pendingSignals);
      host.pendingSignals.clear();
      for (final node in context.graph.nodes) {
        if (node.type != onSignal.id) continue;
        final name = '${node.literals['name'] ?? 'signal'}';
        if (raised.contains(name)) _interpreter.fire(context, onSignal.id);
      }
    }

    final failure = context.error;
    if (failure != null) {
      final message = 'flow: the graph on "${node.name}" stopped: $failure';
      final sink = onLog;
      if (sink != null) {
        sink(message);
      } else {
        debugPrint(message);
      }
    }
  }

  @override
  Component? cloneFor(Node cloneOwner) => FlowComponent(
    // A clone gets its own copy: two objects running one script must not
    // share a Delay's countdown or a variable.
    graph: _graph.copy(),
    registry: registry,
    onAction: onAction,
    onLog: onLog,
  );
}
