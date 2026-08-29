/// The node types every graph gets: events, control flow, variables, maths,
/// logic, and the vector arithmetic that sits between them.
///
/// Nothing here knows what a scene is. Anything reaching outside the graph
/// goes through the [FlowHost], so this whole library runs in a test with a
/// stub and the scene-facing node types are registered separately by whoever
/// has a scene.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'flow_graph.dart';
import 'flow_runtime.dart';

FlowResult _out(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>[]);
FlowResult _then([String pin = 'then']) =>
    (outputs: const <String, Object?>{}, next: <String>[pin]);
FlowResult _stop() =>
    (outputs: const <String, Object?>{}, next: const <String>[]);

const FlowPin _execIn = FlowPin(id: 'exec', label: '', type: FlowType.exec);
const FlowPin _execOut = FlowPin(
  id: 'then',
  label: '',
  type: FlowType.exec,
  isInput: false,
);

// ---------------------------------------------------------------------------
// Events.
// ---------------------------------------------------------------------------

final FlowNodeType onStart = FlowNodeType(
  id: 'event.start',
  label: 'On Start',
  category: 'Events',
  doc: 'Runs once, the first time the graph ticks.',
  isEvent: true,
  pins: const [_execOut],
  evaluate: (context, node, inputs) => _then(),
);

final FlowNodeType onTick = FlowNodeType(
  id: 'event.tick',
  label: 'On Tick',
  category: 'Events',
  doc: 'Runs every frame. Delta Seconds is the time since the last one.',
  isEvent: true,
  pins: const [
    _execOut,
    FlowPin(
      id: 'delta',
      label: 'Delta Seconds',
      type: FlowType.number,
      isInput: false,
    ),
    FlowPin(
      id: 'elapsed',
      label: 'Elapsed',
      type: FlowType.number,
      isInput: false,
      doc: 'Seconds since the graph started.',
    ),
  ],
  evaluate: (context, node, inputs) => (
    outputs: {
      'delta': context.host.deltaSeconds,
      'elapsed': context.host.elapsedSeconds,
    },
    next: const <String>['then'],
  ),
);

final FlowNodeType onSignal = FlowNodeType(
  id: 'event.signal',
  label: 'On Signal',
  category: 'Events',
  doc:
      'Runs when the application raises a named signal, which is how gameplay '
      'code hands an event to a graph.',
  isEvent: true,
  pins: const [
    _execOut,
    FlowPin(
      id: 'name',
      label: 'Name',
      type: FlowType.string,
      defaultValue: 'signal',
    ),
  ],
  evaluate: (context, node, inputs) => _then(),
);

// ---------------------------------------------------------------------------
// Control flow.
// ---------------------------------------------------------------------------

final FlowNodeType branch = FlowNodeType(
  id: 'flow.branch',
  label: 'Branch',
  category: 'Flow',
  doc: 'Takes one exec path or the other.',
  pins: const [
    _execIn,
    FlowPin(
      id: 'condition',
      label: 'Condition',
      type: FlowType.boolean,
      defaultValue: false,
    ),
    FlowPin(id: 'true', label: 'True', type: FlowType.exec, isInput: false),
    FlowPin(id: 'false', label: 'False', type: FlowType.exec, isInput: false),
  ],
  evaluate: (context, node, inputs) => (
    outputs: const {},
    next: flowBool(inputs['condition'])
        ? const <String>['true']
        : const <String>['false'],
  ),
);

final FlowNodeType sequence = FlowNodeType(
  id: 'flow.sequence',
  label: 'Sequence',
  category: 'Flow',
  doc: 'Runs each output in order, waiting for one to finish before the next.',
  pins: const [
    _execIn,
    FlowPin(id: 'a', label: 'Then 1', type: FlowType.exec, isInput: false),
    FlowPin(id: 'b', label: 'Then 2', type: FlowType.exec, isInput: false),
    FlowPin(id: 'c', label: 'Then 3', type: FlowType.exec, isInput: false),
  ],
  // Naming all three is the whole node: the interpreter runs them in the
  // order given, each finishing before the next begins.
  evaluate: (context, node, inputs) =>
      (outputs: const <String, Object?>{}, next: const <String>['a', 'b', 'c']),
);

final FlowNodeType doOnce = FlowNodeType(
  id: 'flow.doOnce',
  label: 'Do Once',
  category: 'Flow',
  doc: 'Passes through the first time and never again, until Reset.',
  pins: const [
    _execIn,
    FlowPin(
      id: 'reset',
      label: 'Reset',
      type: FlowType.boolean,
      defaultValue: false,
      doc: 'True re-arms the gate on this tick.',
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    if (flowBool(inputs['reset'])) context.nodeState[node.id] = false;
    final fired = context.nodeState[node.id] == true;
    if (fired) return _stop();
    context.nodeState[node.id] = true;
    return _then();
  },
);

final FlowNodeType delay = FlowNodeType(
  id: 'flow.delay',
  label: 'Delay',
  category: 'Flow',
  doc:
      'Holds for a number of seconds, then continues. Counts down on every '
      'tick that reaches it, so wire it downstream of On Tick.',
  pins: const [
    _execIn,
    FlowPin(
      id: 'seconds',
      label: 'Seconds',
      type: FlowType.number,
      defaultValue: 1.0,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    final remaining =
        context.nodeState[node.id] as double? ??
        flowNumber(inputs['seconds'], 1);
    final next = remaining - context.host.deltaSeconds;
    if (next > 0) {
      context.nodeState[node.id] = next;
      return _stop();
    }
    // Re-arm on completion, so a Delay downstream of a repeating event is a
    // metronome rather than a one-shot.
    context.nodeState[node.id] = flowNumber(inputs['seconds'], 1);
    return _then();
  },
);

final FlowNodeType gate = FlowNodeType(
  id: 'flow.gate',
  label: 'Gate',
  category: 'Flow',
  doc: 'Passes through only while Open is true.',
  pins: const [
    _execIn,
    FlowPin(
      id: 'open',
      label: 'Open',
      type: FlowType.boolean,
      defaultValue: true,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) =>
      flowBool(inputs['open']) ? _then() : _stop(),
);

// ---------------------------------------------------------------------------
// Variables.
// ---------------------------------------------------------------------------

final FlowNodeType getVariable = FlowNodeType(
  id: 'var.get',
  label: 'Get Variable',
  category: 'Variables',
  doc: 'Reads one of the graph\'s variables.',
  pins: const [
    FlowPin(id: 'name', label: 'Name', type: FlowType.string, defaultValue: ''),
    FlowPin(id: 'value', label: 'Value', type: FlowType.any, isInput: false),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': context.variables['${inputs['name']}']}),
);

final FlowNodeType setVariable = FlowNodeType(
  id: 'var.set',
  label: 'Set Variable',
  category: 'Variables',
  doc: 'Writes one of the graph\'s variables.',
  pins: const [
    _execIn,
    FlowPin(id: 'name', label: 'Name', type: FlowType.string, defaultValue: ''),
    FlowPin(id: 'value', label: 'Value', type: FlowType.any),
    _execOut,
    FlowPin(
      id: 'out',
      label: 'Value',
      type: FlowType.any,
      isInput: false,
      doc: 'The value written, so it can feed on without a second Get.',
    ),
  ],
  evaluate: (context, node, inputs) {
    context.variables['${inputs['name']}'] = inputs['value'];
    return (outputs: {'out': inputs['value']}, next: const <String>['then']);
  },
);

// ---------------------------------------------------------------------------
// Maths.
// ---------------------------------------------------------------------------

FlowNodeType _binaryNumber(
  String id,
  String label,
  String doc,
  double Function(double a, double b) op, {
  double defaultB = 0,
}) => FlowNodeType(
  id: id,
  label: label,
  category: 'Math',
  doc: doc,
  pins: [
    const FlowPin(
      id: 'a',
      label: 'A',
      type: FlowType.number,
      defaultValue: 0.0,
    ),
    FlowPin(id: 'b', label: 'B', type: FlowType.number, defaultValue: defaultB),
    const FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': op(flowNumber(inputs['a']), flowNumber(inputs['b']))}),
);

final FlowNodeType addNumbers = _binaryNumber(
  'math.add',
  'Add',
  'A + B.',
  (a, b) => a + b,
);
final FlowNodeType subtractNumbers = _binaryNumber(
  'math.subtract',
  'Subtract',
  'A - B.',
  (a, b) => a - b,
);
final FlowNodeType multiplyNumbers = _binaryNumber(
  'math.multiply',
  'Multiply',
  'A * B.',
  (a, b) => a * b,
  defaultB: 1,
);
final FlowNodeType divideNumbers = _binaryNumber(
  'math.divide',
  'Divide',
  'A / B. Dividing by zero gives zero rather than an infinity, so one bad '
      'frame does not poison every value downstream of it.',
  (a, b) => b == 0 ? 0 : a / b,
  defaultB: 1,
);

final FlowNodeType clampNumber = FlowNodeType(
  id: 'math.clamp',
  label: 'Clamp',
  category: 'Math',
  doc: 'Holds a value inside a range.',
  pins: const [
    FlowPin(id: 'value', label: 'Value', type: FlowType.number),
    FlowPin(id: 'min', label: 'Min', type: FlowType.number, defaultValue: 0.0),
    FlowPin(id: 'max', label: 'Max', type: FlowType.number, defaultValue: 1.0),
    FlowPin(id: 'out', label: 'Result', type: FlowType.number, isInput: false),
  ],
  evaluate: (context, node, inputs) {
    final low = flowNumber(inputs['min']);
    final high = flowNumber(inputs['max']);
    final value = flowNumber(inputs['value']);
    return _out({'out': high < low ? low : value.clamp(low, high)});
  },
);

final FlowNodeType lerpNumber = FlowNodeType(
  id: 'math.lerp',
  label: 'Lerp',
  category: 'Math',
  doc: 'Blends from A to B by T.',
  pins: const [
    FlowPin(id: 'a', label: 'A', type: FlowType.number, defaultValue: 0.0),
    FlowPin(id: 'b', label: 'B', type: FlowType.number, defaultValue: 1.0),
    FlowPin(id: 't', label: 'T', type: FlowType.number, defaultValue: 0.5),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final a = flowNumber(inputs['a']);
    final b = flowNumber(inputs['b']);
    return _out({'value': a + (b - a) * flowNumber(inputs['t'])});
  },
);

final FlowNodeType sineWave = FlowNodeType(
  id: 'math.sine',
  label: 'Sine',
  category: 'Math',
  doc:
      'An oscillation between Min and Max at a rate, driven by the graph\'s '
      'clock. The one node that makes something bob without any state.',
  pins: const [
    FlowPin(
      id: 'rate',
      label: 'Cycles/sec',
      type: FlowType.number,
      defaultValue: 1.0,
    ),
    FlowPin(id: 'min', label: 'Min', type: FlowType.number, defaultValue: -1.0),
    FlowPin(id: 'max', label: 'Max', type: FlowType.number, defaultValue: 1.0),
    FlowPin(
      id: 'phase',
      label: 'Phase',
      type: FlowType.number,
      defaultValue: 0.0,
    ),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final wave = math.sin(
      (context.host.elapsedSeconds * flowNumber(inputs['rate'], 1) +
              flowNumber(inputs['phase'])) *
          2 *
          math.pi,
    );
    final low = flowNumber(inputs['min'], -1);
    final high = flowNumber(inputs['max'], 1);
    return _out({'value': low + (wave * 0.5 + 0.5) * (high - low)});
  },
);

final FlowNodeType randomNumber = FlowNodeType(
  id: 'math.random',
  label: 'Random',
  category: 'Math',
  doc: 'A fresh value in a range each time it is asked for.',
  pins: const [
    FlowPin(id: 'min', label: 'Min', type: FlowType.number, defaultValue: 0.0),
    FlowPin(id: 'max', label: 'Max', type: FlowType.number, defaultValue: 1.0),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final low = flowNumber(inputs['min']);
    final high = flowNumber(inputs['max'], 1);
    return _out({'value': low + _random.nextDouble() * (high - low)});
  },
);

final math.Random _random = math.Random();

// ---------------------------------------------------------------------------
// Logic and comparison.
// ---------------------------------------------------------------------------

FlowNodeType _compare(
  String id,
  String label,
  String doc,
  bool Function(double a, double b) op,
) => FlowNodeType(
  id: id,
  label: label,
  category: 'Logic',
  doc: doc,
  pins: const [
    FlowPin(id: 'a', label: 'A', type: FlowType.number, defaultValue: 0.0),
    FlowPin(id: 'b', label: 'B', type: FlowType.number, defaultValue: 0.0),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': op(flowNumber(inputs['a']), flowNumber(inputs['b']))}),
);

final FlowNodeType numberGreaterThan = _compare(
  'logic.greater',
  'Greater Than',
  'A > B.',
  (a, b) => a > b,
);
final FlowNodeType numberLessThan = _compare(
  'logic.less',
  'Less Than',
  'A < B.',
  (a, b) => a < b,
);
final FlowNodeType numberNearlyEqual = _compare(
  'logic.equal',
  'Nearly Equal',
  'A and B within a millionth. Exact equality on floats is a trap, so this '
      'is the comparison offered instead.',
  (a, b) => (a - b).abs() < 1e-6,
);

final FlowNodeType andGate = FlowNodeType(
  id: 'logic.and',
  label: 'And',
  category: 'Logic',
  doc: 'True when both are.',
  pins: const [
    FlowPin(id: 'a', label: 'A', type: FlowType.boolean, defaultValue: false),
    FlowPin(id: 'b', label: 'B', type: FlowType.boolean, defaultValue: false),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': flowBool(inputs['a']) && flowBool(inputs['b'])}),
);

final FlowNodeType orGate = FlowNodeType(
  id: 'logic.or',
  label: 'Or',
  category: 'Logic',
  doc: 'True when either is.',
  pins: const [
    FlowPin(id: 'a', label: 'A', type: FlowType.boolean, defaultValue: false),
    FlowPin(id: 'b', label: 'B', type: FlowType.boolean, defaultValue: false),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': flowBool(inputs['a']) || flowBool(inputs['b'])}),
);

final FlowNodeType notGate = FlowNodeType(
  id: 'logic.not',
  label: 'Not',
  category: 'Logic',
  doc: 'Flips a condition.',
  pins: const [
    FlowPin(id: 'a', label: 'A', type: FlowType.boolean, defaultValue: false),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({'value': !flowBool(inputs['a'])}),
);

// ---------------------------------------------------------------------------
// Vectors.
// ---------------------------------------------------------------------------

final FlowNodeType makeVector = FlowNodeType(
  id: 'vector.make',
  label: 'Make Vector',
  category: 'Vector',
  doc: 'Builds a vector from three numbers.',
  pins: const [
    FlowPin(id: 'x', label: 'X', type: FlowType.number, defaultValue: 0.0),
    FlowPin(id: 'y', label: 'Y', type: FlowType.number, defaultValue: 0.0),
    FlowPin(id: 'z', label: 'Z', type: FlowType.number, defaultValue: 0.0),
    FlowPin(
      id: 'value',
      label: 'Vector',
      type: FlowType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': Vector3(
      flowNumber(inputs['x']),
      flowNumber(inputs['y']),
      flowNumber(inputs['z']),
    ),
  }),
);

final FlowNodeType breakVector = FlowNodeType(
  id: 'vector.break',
  label: 'Break Vector',
  category: 'Vector',
  doc: 'Splits a vector into its components.',
  pins: const [
    FlowPin(id: 'value', label: 'Vector', type: FlowType.vector3),
    FlowPin(id: 'x', label: 'X', type: FlowType.number, isInput: false),
    FlowPin(id: 'y', label: 'Y', type: FlowType.number, isInput: false),
    FlowPin(id: 'z', label: 'Z', type: FlowType.number, isInput: false),
  ],
  evaluate: (context, node, inputs) {
    final v = flowVector(inputs['value']);
    return _out({'x': v.x, 'y': v.y, 'z': v.z});
  },
);

final FlowNodeType addVectors = FlowNodeType(
  id: 'vector.add',
  label: 'Add Vectors',
  category: 'Vector',
  doc: 'A + B.',
  pins: const [
    FlowPin(id: 'a', label: 'A', type: FlowType.vector3),
    FlowPin(id: 'b', label: 'B', type: FlowType.vector3),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': flowVector(inputs['a']) + flowVector(inputs['b'])}),
);

final FlowNodeType scaleVector = FlowNodeType(
  id: 'vector.scale',
  label: 'Scale Vector',
  category: 'Vector',
  doc: 'Multiplies a vector by a number.',
  pins: const [
    FlowPin(id: 'a', label: 'Vector', type: FlowType.vector3),
    FlowPin(
      id: 'scale',
      label: 'Scale',
      type: FlowType.number,
      defaultValue: 1.0,
    ),
    FlowPin(
      id: 'value',
      label: 'Result',
      type: FlowType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': flowVector(inputs['a']).scaled(flowNumber(inputs['scale'], 1)),
  }),
);

// ---------------------------------------------------------------------------
// Debug.
// ---------------------------------------------------------------------------

final FlowNodeType printValue = FlowNodeType(
  id: 'debug.print',
  label: 'Print',
  category: 'Debug',
  doc:
      'Writes a value to the host\'s log. The first thing to reach for when '
      'a graph is not doing what it looks like it should.',
  pins: const [
    _execIn,
    FlowPin(
      id: 'label',
      label: 'Label',
      type: FlowType.string,
      defaultValue: '',
    ),
    FlowPin(id: 'value', label: 'Value', type: FlowType.any),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    final label = '${inputs['label'] ?? ''}';
    final text = flowString(inputs['value']);
    context.host.log(label.isEmpty ? text : '$label: $text');
    return _then();
  },
);

/// Every node type in this library, in palette order.
/// {@category Flow}
final List<FlowNodeType> standardFlowNodes = [
  onStart,
  onTick,
  onSignal,
  branch,
  sequence,
  doOnce,
  delay,
  gate,
  getVariable,
  setVariable,
  addNumbers,
  subtractNumbers,
  multiplyNumbers,
  divideNumbers,
  clampNumber,
  lerpNumber,
  sineWave,
  randomNumber,
  numberGreaterThan,
  numberLessThan,
  numberNearlyEqual,
  andGate,
  orGate,
  notGate,
  makeVector,
  breakVector,
  addVectors,
  scaleVector,
  printValue,
];

/// A registry preloaded with [standardFlowNodes].
/// {@category Flow}
FlowRegistry standardFlowRegistry() =>
    FlowRegistry()..registerAll(standardFlowNodes);
