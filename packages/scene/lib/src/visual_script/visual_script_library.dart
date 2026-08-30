/// The node types every graph gets: events, control flow, variables, maths,
/// logic, and the vector arithmetic that sits between them.
///
/// Nothing here knows what a scene is. Anything reaching outside the graph
/// goes through the [VisualScriptHost], so this whole library runs in a test with a
/// stub and the scene-facing node types are registered separately by whoever
/// has a scene.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'visual_script_graph.dart';
import 'visual_script_runtime.dart';

VisualScriptResult _out(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>[]);
VisualScriptResult _then([String pin = 'then']) =>
    (outputs: const <String, Object?>{}, next: <String>[pin]);
VisualScriptResult _stop() =>
    (outputs: const <String, Object?>{}, next: const <String>[]);

const VisualScriptPin _execIn = VisualScriptPin(
  id: 'exec',
  label: '',
  type: VisualScriptType.exec,
);
const VisualScriptPin _execOut = VisualScriptPin(
  id: 'then',
  label: '',
  type: VisualScriptType.exec,
  isInput: false,
);

// ---------------------------------------------------------------------------
// Events.
// ---------------------------------------------------------------------------

final VisualScriptNodeType onStart = VisualScriptNodeType(
  id: 'event.start',
  label: 'On Start',
  category: 'Events',
  doc: 'Runs once, the first time the graph ticks.',
  isEvent: true,
  pins: const [_execOut],
  evaluate: (context, node, inputs) => _then(),
);

final VisualScriptNodeType onTick = VisualScriptNodeType(
  id: 'event.tick',
  label: 'On Tick',
  category: 'Events',
  doc: 'Runs every frame. Delta Seconds is the time since the last one.',
  isEvent: true,
  pins: const [
    _execOut,
    VisualScriptPin(
      id: 'delta',
      label: 'Delta Seconds',
      type: VisualScriptType.number,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'elapsed',
      label: 'Elapsed',
      type: VisualScriptType.number,
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

final VisualScriptNodeType onSignal = VisualScriptNodeType(
  id: 'event.signal',
  label: 'On Signal',
  category: 'Events',
  doc:
      'Runs when the application raises a named signal, which is how gameplay '
      'code hands an event to a graph.',
  isEvent: true,
  pins: const [
    _execOut,
    VisualScriptPin(
      id: 'name',
      label: 'Name',
      type: VisualScriptType.string,
      defaultValue: 'signal',
    ),
  ],
  evaluate: (context, node, inputs) => _then(),
);

// ---------------------------------------------------------------------------
// Flow Control: the conventional group for these, and the reason the node ids
// below keep the `flow.` prefix. They are also written into saved graphs, so
// respelling them would be a migration for no gain.
// ---------------------------------------------------------------------------

final VisualScriptNodeType branch = VisualScriptNodeType(
  id: 'flow.branch',
  label: 'Branch',
  category: 'Flow Control',
  doc: 'Takes one exec path or the other.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'condition',
      label: 'Condition',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'true',
      label: 'True',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'false',
      label: 'False',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => (
    outputs: const {},
    next: scriptBool(inputs['condition'])
        ? const <String>['true']
        : const <String>['false'],
  ),
);

final VisualScriptNodeType sequence = VisualScriptNodeType(
  id: 'flow.sequence',
  label: 'Sequence',
  category: 'Flow Control',
  doc: 'Runs each output in order, waiting for one to finish before the next.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'a',
      label: 'Then 1',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'b',
      label: 'Then 2',
      type: VisualScriptType.exec,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'c',
      label: 'Then 3',
      type: VisualScriptType.exec,
      isInput: false,
    ),
  ],
  // Naming all three is the whole node: the interpreter runs them in the
  // order given, each finishing before the next begins.
  evaluate: (context, node, inputs) =>
      (outputs: const <String, Object?>{}, next: const <String>['a', 'b', 'c']),
);

final VisualScriptNodeType doOnce = VisualScriptNodeType(
  id: 'flow.doOnce',
  label: 'Do Once',
  category: 'Flow Control',
  doc: 'Passes through the first time and never again, until Reset.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'reset',
      label: 'Reset',
      type: VisualScriptType.boolean,
      defaultValue: false,
      doc: 'True re-arms the gate on this tick.',
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    if (scriptBool(inputs['reset'])) context.nodeState[node.id] = false;
    final fired = context.nodeState[node.id] == true;
    if (fired) return _stop();
    context.nodeState[node.id] = true;
    return _then();
  },
);

final VisualScriptNodeType delay = VisualScriptNodeType(
  id: 'flow.delay',
  label: 'Delay',
  category: 'Flow Control',
  doc:
      'Holds for a number of seconds, then continues. Counts down on every '
      'tick that reaches it, so wire it downstream of On Tick.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'seconds',
      label: 'Seconds',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    final remaining =
        context.nodeState[node.id] as double? ??
        scriptNumber(inputs['seconds'], 1);
    final next = remaining - context.host.deltaSeconds;
    if (next > 0) {
      context.nodeState[node.id] = next;
      return _stop();
    }
    // Re-arm on completion, so a Delay downstream of a repeating event is a
    // metronome rather than a one-shot.
    context.nodeState[node.id] = scriptNumber(inputs['seconds'], 1);
    return _then();
  },
);

final VisualScriptNodeType gate = VisualScriptNodeType(
  id: 'flow.gate',
  label: 'Gate',
  category: 'Flow Control',
  doc: 'Passes through only while Open is true.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'open',
      label: 'Open',
      type: VisualScriptType.boolean,
      defaultValue: true,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) =>
      scriptBool(inputs['open']) ? _then() : _stop(),
);

// ---------------------------------------------------------------------------
// Variables.
// ---------------------------------------------------------------------------

final VisualScriptNodeType getVariable = VisualScriptNodeType(
  id: 'var.get',
  label: 'Get Variable',
  category: 'Variables',
  doc: 'Reads one of the graph\'s variables.',
  pins: const [
    VisualScriptPin(
      id: 'name',
      label: 'Name',
      type: VisualScriptType.string,
      defaultValue: '',
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Value',
      type: VisualScriptType.any,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': context.variables['${inputs['name']}']}),
);

final VisualScriptNodeType setVariable = VisualScriptNodeType(
  id: 'var.set',
  label: 'Set Variable',
  category: 'Variables',
  doc: 'Writes one of the graph\'s variables.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'name',
      label: 'Name',
      type: VisualScriptType.string,
      defaultValue: '',
    ),
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.any),
    _execOut,
    VisualScriptPin(
      id: 'out',
      label: 'Value',
      type: VisualScriptType.any,
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

VisualScriptNodeType _binaryNumber(
  String id,
  String label,
  String doc,
  double Function(double a, double b) op, {
  double defaultB = 0,
}) => VisualScriptNodeType(
  id: id,
  label: label,
  category: 'Math',
  doc: doc,
  pins: [
    const VisualScriptPin(
      id: 'a',
      label: 'A',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'b',
      label: 'B',
      type: VisualScriptType.number,
      defaultValue: defaultB,
    ),
    const VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': op(scriptNumber(inputs['a']), scriptNumber(inputs['b']))}),
);

final VisualScriptNodeType addNumbers = _binaryNumber(
  'math.add',
  'Add',
  'A + B.',
  (a, b) => a + b,
);
final VisualScriptNodeType subtractNumbers = _binaryNumber(
  'math.subtract',
  'Subtract',
  'A - B.',
  (a, b) => a - b,
);
final VisualScriptNodeType multiplyNumbers = _binaryNumber(
  'math.multiply',
  'Multiply',
  'A * B.',
  (a, b) => a * b,
  defaultB: 1,
);
final VisualScriptNodeType divideNumbers = _binaryNumber(
  'math.divide',
  'Divide',
  'A / B. Dividing by zero gives zero rather than an infinity, so one bad '
      'frame does not poison every value downstream of it.',
  (a, b) => b == 0 ? 0 : a / b,
  defaultB: 1,
);

final VisualScriptNodeType clampNumber = VisualScriptNodeType(
  id: 'math.clamp',
  label: 'Clamp',
  category: 'Math',
  doc: 'Holds a value inside a range.',
  pins: const [
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.number),
    VisualScriptPin(
      id: 'min',
      label: 'Min',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'max',
      label: 'Max',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    VisualScriptPin(
      id: 'out',
      label: 'Result',
      type: VisualScriptType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final low = scriptNumber(inputs['min']);
    final high = scriptNumber(inputs['max']);
    final value = scriptNumber(inputs['value']);
    return _out({'out': high < low ? low : value.clamp(low, high)});
  },
);

final VisualScriptNodeType lerpNumber = VisualScriptNodeType(
  id: 'math.lerp',
  label: 'Lerp',
  category: 'Math',
  doc: 'Blends from A to B by T.',
  pins: const [
    VisualScriptPin(
      id: 'a',
      label: 'A',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'b',
      label: 'B',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    VisualScriptPin(
      id: 't',
      label: 'T',
      type: VisualScriptType.number,
      defaultValue: 0.5,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final a = scriptNumber(inputs['a']);
    final b = scriptNumber(inputs['b']);
    return _out({'value': a + (b - a) * scriptNumber(inputs['t'])});
  },
);

final VisualScriptNodeType sineWave = VisualScriptNodeType(
  id: 'math.sine',
  label: 'Sine',
  category: 'Math',
  doc:
      'An oscillation between Min and Max at a rate, driven by the graph\'s '
      'clock. The one node that makes something bob without any state.',
  pins: const [
    VisualScriptPin(
      id: 'rate',
      label: 'Cycles/sec',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    VisualScriptPin(
      id: 'min',
      label: 'Min',
      type: VisualScriptType.number,
      defaultValue: -1.0,
    ),
    VisualScriptPin(
      id: 'max',
      label: 'Max',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    VisualScriptPin(
      id: 'phase',
      label: 'Phase',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final wave = math.sin(
      (context.host.elapsedSeconds * scriptNumber(inputs['rate'], 1) +
              scriptNumber(inputs['phase'])) *
          2 *
          math.pi,
    );
    final low = scriptNumber(inputs['min'], -1);
    final high = scriptNumber(inputs['max'], 1);
    return _out({'value': low + (wave * 0.5 + 0.5) * (high - low)});
  },
);

final VisualScriptNodeType randomNumber = VisualScriptNodeType(
  id: 'math.random',
  label: 'Random',
  category: 'Math',
  doc: 'A fresh value in a range each time it is asked for.',
  pins: const [
    VisualScriptPin(
      id: 'min',
      label: 'Min',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'max',
      label: 'Max',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final low = scriptNumber(inputs['min']);
    final high = scriptNumber(inputs['max'], 1);
    return _out({'value': low + _random.nextDouble() * (high - low)});
  },
);

final math.Random _random = math.Random();

// ---------------------------------------------------------------------------
// Logic and comparison.
// ---------------------------------------------------------------------------

VisualScriptNodeType _compare(
  String id,
  String label,
  String doc,
  bool Function(double a, double b) op,
) => VisualScriptNodeType(
  id: id,
  label: label,
  category: 'Logic',
  doc: doc,
  pins: const [
    VisualScriptPin(
      id: 'a',
      label: 'A',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'b',
      label: 'B',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': op(scriptNumber(inputs['a']), scriptNumber(inputs['b']))}),
);

final VisualScriptNodeType numberGreaterThan = _compare(
  'logic.greater',
  'Greater Than',
  'A > B.',
  (a, b) => a > b,
);
final VisualScriptNodeType numberLessThan = _compare(
  'logic.less',
  'Less Than',
  'A < B.',
  (a, b) => a < b,
);
final VisualScriptNodeType numberNearlyEqual = _compare(
  'logic.equal',
  'Nearly Equal',
  'A and B within a millionth. Exact equality on floats is a trap, so this '
      'is the comparison offered instead.',
  (a, b) => (a - b).abs() < 1e-6,
);

final VisualScriptNodeType andGate = VisualScriptNodeType(
  id: 'logic.and',
  label: 'And',
  category: 'Logic',
  doc: 'True when both are.',
  pins: const [
    VisualScriptPin(
      id: 'a',
      label: 'A',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'b',
      label: 'B',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptBool(inputs['a']) && scriptBool(inputs['b'])}),
);

final VisualScriptNodeType orGate = VisualScriptNodeType(
  id: 'logic.or',
  label: 'Or',
  category: 'Logic',
  doc: 'True when either is.',
  pins: const [
    VisualScriptPin(
      id: 'a',
      label: 'A',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'b',
      label: 'B',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptBool(inputs['a']) || scriptBool(inputs['b'])}),
);

final VisualScriptNodeType notGate = VisualScriptNodeType(
  id: 'logic.not',
  label: 'Not',
  category: 'Logic',
  doc: 'Flips a condition.',
  pins: const [
    VisualScriptPin(
      id: 'a',
      label: 'A',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.boolean,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': !scriptBool(inputs['a'])}),
);

// ---------------------------------------------------------------------------
// Vectors.
// ---------------------------------------------------------------------------

final VisualScriptNodeType makeVector = VisualScriptNodeType(
  id: 'vector.make',
  label: 'Make Vector',
  category: 'Vector',
  doc: 'Builds a vector from three numbers.',
  pins: const [
    VisualScriptPin(
      id: 'x',
      label: 'X',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'y',
      label: 'Y',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'z',
      label: 'Z',
      type: VisualScriptType.number,
      defaultValue: 0.0,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Vector',
      type: VisualScriptType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': Vector3(
      scriptNumber(inputs['x']),
      scriptNumber(inputs['y']),
      scriptNumber(inputs['z']),
    ),
  }),
);

final VisualScriptNodeType breakVector = VisualScriptNodeType(
  id: 'vector.break',
  label: 'Break Vector',
  category: 'Vector',
  doc: 'Splits a vector into its components.',
  pins: const [
    VisualScriptPin(
      id: 'value',
      label: 'Vector',
      type: VisualScriptType.vector3,
    ),
    VisualScriptPin(
      id: 'x',
      label: 'X',
      type: VisualScriptType.number,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'y',
      label: 'Y',
      type: VisualScriptType.number,
      isInput: false,
    ),
    VisualScriptPin(
      id: 'z',
      label: 'Z',
      type: VisualScriptType.number,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) {
    final v = scriptVector(inputs['value']);
    return _out({'x': v.x, 'y': v.y, 'z': v.z});
  },
);

final VisualScriptNodeType addVectors = VisualScriptNodeType(
  id: 'vector.add',
  label: 'Add Vectors',
  category: 'Vector',
  doc: 'A + B.',
  pins: const [
    VisualScriptPin(id: 'a', label: 'A', type: VisualScriptType.vector3),
    VisualScriptPin(id: 'b', label: 'B', type: VisualScriptType.vector3),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptVector(inputs['a']) + scriptVector(inputs['b'])}),
);

final VisualScriptNodeType scaleVector = VisualScriptNodeType(
  id: 'vector.scale',
  label: 'Scale Vector',
  category: 'Vector',
  doc: 'Multiplies a vector by a number.',
  pins: const [
    VisualScriptPin(id: 'a', label: 'Vector', type: VisualScriptType.vector3),
    VisualScriptPin(
      id: 'scale',
      label: 'Scale',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    VisualScriptPin(
      id: 'value',
      label: 'Result',
      type: VisualScriptType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptVector(inputs['a']).scaled(scriptNumber(inputs['scale'], 1)),
  }),
);

// ---------------------------------------------------------------------------
// Debug.
// ---------------------------------------------------------------------------

final VisualScriptNodeType printValue = VisualScriptNodeType(
  id: 'debug.print',
  label: 'Print',
  category: 'Debug',
  doc:
      'Writes a value to the host\'s log. The first thing to reach for when '
      'a graph is not doing what it looks like it should.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'label',
      label: 'Label',
      type: VisualScriptType.string,
      defaultValue: '',
    ),
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.any),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    final label = '${inputs['label'] ?? ''}';
    final text = scriptString(inputs['value']);
    context.host.log(label.isEmpty ? text : '$label: $text');
    return _then();
  },
);

/// Every node type in this library, in palette order.
/// {@category Visual scripting}
final List<VisualScriptNodeType> standardVisualScriptNodes = [
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

/// A registry preloaded with [standardVisualScriptNodes].
/// {@category Visual scripting}
VisualScriptRegistry standardVisualScriptRegistry() =>
    VisualScriptRegistry()..registerAll(standardVisualScriptNodes);
