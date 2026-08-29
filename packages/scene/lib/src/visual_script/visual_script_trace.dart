/// Watching a graph run.
///
/// Visual scripting has a failure mode that written code does not: a graph
/// that does nothing looks exactly like a graph that does the wrong thing.
/// The wires are all still there, the nodes all still say what they do, and
/// nothing on the canvas distinguishes the branch that fired from the one
/// that did not. Reading it back is guesswork, and the usual next step is
/// hanging Log nodes off everything until the shape of the bug appears.
///
/// A trace is what removes that. It records which nodes ran, in what order,
/// which exec wire each one took, and what value every data pin actually
/// resolved to -- so a canvas can draw the path the run took and label the
/// wires with the numbers that went down them.
///
/// Nothing records unless a trace is attached, so the cost of having this is
/// a null check per node on the runs nobody is watching.
library;

/// One node's turn, in the order it happened.
/// {@category Visual scripting}
typedef VisualScriptTraceStep = ({
  /// The node that ran.
  int nodeId,

  /// Its type, so a reader does not have to hold the graph to make sense of
  /// the trace.
  String type,

  /// Its position in the run, from zero.
  int order,
});

/// Which pin of which node. The key for everything a trace records about
/// values.
/// {@category Visual scripting}
typedef VisualScriptPinRef = ({int nodeId, String pinId});

/// What one run of a graph did.
///
/// Attach it to a [VisualScriptContext] and it fills as the graph runs. Read it
/// afterwards -- a canvas highlighting live wires, a test asserting a branch
/// was taken, a bug report.
/// {@category Visual scripting}
class VisualScriptTrace {
  /// Creates an empty trace holding at most [maxSteps] entries.
  ///
  /// Bounded because a graph on a tick event runs every frame and an
  /// unbounded list would be a leak with a nice name. Past the limit the
  /// counts and the values keep updating and the step list stops growing,
  /// which keeps the expensive part bounded and the useful part live.
  VisualScriptTrace({this.maxSteps = 512});

  /// The most steps [steps] holds.
  final int maxSteps;

  final List<VisualScriptTraceStep> _steps = [];

  /// The nodes that ran, in order.
  List<VisualScriptTraceStep> get steps => List.unmodifiable(_steps);

  /// How many nodes ran, including any past [maxSteps].
  int get stepCount => _stepCount;
  int _stepCount = 0;

  final Map<VisualScriptPinRef, Object?> _values = {};

  /// The last value seen on each pin.
  ///
  /// Inputs and outputs both: an input is what the node was handed, an output
  /// is what it produced, and a wire between them is labelled by either.
  Map<VisualScriptPinRef, Object?> get values => Map.unmodifiable(_values);

  final Set<VisualScriptPinRef> _fired = {};

  /// The exec outputs that were taken.
  ///
  /// What tells a Branch's true wire from its false one on the canvas, which
  /// is the single most useful thing a trace can say.
  Set<VisualScriptPinRef> get firedExec => Set.unmodifiable(_fired);

  final Set<int> _visited = {};

  /// Every node that ran at least once, for dimming the ones that did not.
  Set<int> get visitedNodes => Set.unmodifiable(_visited);

  /// What went wrong, when something did.
  String? error;

  /// The value on [pinId] of [nodeId], or null when nothing put one there.
  Object? valueOf(int nodeId, String pinId) =>
      _values[(nodeId: nodeId, pinId: pinId)];

  /// Whether the exec output [pinId] of [nodeId] was taken.
  bool didFire(int nodeId, String pinId) =>
      _fired.contains((nodeId: nodeId, pinId: pinId));

  /// Records that [nodeId] of type [type] ran.
  void recordStep(int nodeId, String type) {
    _visited.add(nodeId);
    if (_steps.length < maxSteps) {
      _steps.add((nodeId: nodeId, type: type, order: _stepCount));
    }
    _stepCount++;
  }

  /// Records the value on a pin.
  void recordValue(int nodeId, String pinId, Object? value) {
    _values[(nodeId: nodeId, pinId: pinId)] = value;
  }

  /// Records that an exec output was taken.
  void recordExec(int nodeId, String pinId) {
    _fired.add((nodeId: nodeId, pinId: pinId));
  }

  /// Forgets everything, for the next run.
  ///
  /// A graph on a tick event is traced per frame, and the interesting trace
  /// is the current one; keeping every frame's would grow without bound and
  /// bury the frame anyone is looking at.
  void clear() {
    _steps.clear();
    _values.clear();
    _fired.clear();
    _visited.clear();
    _stepCount = 0;
    error = null;
  }

  /// A short summary, for a status line.
  String describe() {
    if (error case final message?) return message;
    if (_stepCount == 0) return 'Nothing ran.';
    return '$_stepCount ${_stepCount == 1 ? 'node' : 'nodes'} ran, '
        '${_values.length} ${_values.length == 1 ? 'value' : 'values'} '
        'on the wires.';
  }
}
