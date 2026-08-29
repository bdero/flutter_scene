/// The node types that only make sense with a scene: reading and writing a
/// node's transform, aiming it, playing its animations, and removing it.
///
/// Every one of them goes through the [FlowHost] rather than touching a
/// `Node` directly, so a graph stays testable against a stub and an
/// application can substitute its own host to bound what a graph may do.
library;

import 'package:scene/flow.dart';

FlowResult _out(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>[]);
FlowResult _then() =>
    (outputs: const <String, Object?>{}, next: const <String>['then']);

const FlowPin _execIn = FlowPin(id: 'exec', label: '', type: FlowType.exec);
const FlowPin _execOut = FlowPin(
  id: 'then',
  label: '',
  type: FlowType.exec,
  isInput: false,
);
const FlowPin _target = FlowPin(
  id: 'target',
  label: 'Target',
  type: FlowType.string,
  defaultValue: '',
  doc:
      'A descendant by name, as "turret". Empty is the node the graph is '
      'attached to.',
);

/// Joins a target name and a property into the path a host resolves.
String _path(Object? target, String property) {
  final name = '${target ?? ''}';
  if (name.isEmpty) return property;
  return name.endsWith('/') ? '$name$property' : '$name/$property';
}

final FlowNodeType getPosition = FlowNodeType(
  id: 'scene.getPosition',
  label: 'Get Position',
  category: 'Scene',
  doc: "Reads a node's local position.",
  pins: const [
    _target,
    FlowPin(
      id: 'value',
      label: 'Position',
      type: FlowType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': flowVector(context.host.read(_path(inputs['target'], 'position'))),
  }),
);

final FlowNodeType setPosition = FlowNodeType(
  id: 'scene.setPosition',
  label: 'Set Position',
  category: 'Scene',
  doc: "Writes a node's local position.",
  pins: const [
    _execIn,
    _target,
    FlowPin(id: 'value', label: 'Position', type: FlowType.vector3),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    final path = _path(inputs['target'], 'position');
    if (!context.host.write(path, inputs['value'])) {
      context.host.log('Nothing at "$path" to write a position to.');
    }
    return _then();
  },
);

final FlowNodeType getScale = FlowNodeType(
  id: 'scene.getScale',
  label: 'Get Scale',
  category: 'Scene',
  doc: "Reads a node's local scale.",
  pins: const [
    _target,
    FlowPin(
      id: 'value',
      label: 'Scale',
      type: FlowType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': flowVector(context.host.read(_path(inputs['target'], 'scale'))),
  }),
);

final FlowNodeType setScale = FlowNodeType(
  id: 'scene.setScale',
  label: 'Set Scale',
  category: 'Scene',
  doc: "Writes a node's local scale.",
  pins: const [
    _execIn,
    _target,
    FlowPin(id: 'value', label: 'Scale', type: FlowType.vector3),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.write(_path(inputs['target'], 'scale'), inputs['value']);
    return _then();
  },
);

final FlowNodeType setVisible = FlowNodeType(
  id: 'scene.setVisible',
  label: 'Set Visible',
  category: 'Scene',
  doc: 'Shows or hides a node and its subtree.',
  pins: const [
    _execIn,
    _target,
    FlowPin(
      id: 'value',
      label: 'Visible',
      type: FlowType.boolean,
      defaultValue: true,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.write(_path(inputs['target'], 'visible'), inputs['value']);
    return _then();
  },
);

final FlowNodeType translateNode = FlowNodeType(
  id: 'scene.translate',
  label: 'Translate',
  category: 'Scene',
  doc:
      'Moves the node by an offset. Multiply by Delta Seconds for a rate '
      'rather than a per-frame jump, or the speed follows the frame rate.',
  pins: const [
    _execIn,
    FlowPin(id: 'by', label: 'By', type: FlowType.vector3),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.invoke('translate', {'by': inputs['by']});
    return _then();
  },
);

final FlowNodeType lookAtPoint = FlowNodeType(
  id: 'scene.lookAt',
  label: 'Look At',
  category: 'Scene',
  doc: 'Aims the node at a world-space point.',
  pins: const [
    _execIn,
    FlowPin(id: 'target', label: 'Point', type: FlowType.vector3),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.invoke('lookAt', {'target': inputs['target']});
    return _then();
  },
);

final FlowNodeType playAnimation = FlowNodeType(
  id: 'scene.playAnimation',
  label: 'Play Animation',
  category: 'Scene',
  doc: "Starts one of the node's parsed animations.",
  pins: const [
    _execIn,
    FlowPin(id: 'name', label: 'Name', type: FlowType.string, defaultValue: ''),
    FlowPin(
      id: 'loop',
      label: 'Loop',
      type: FlowType.boolean,
      defaultValue: false,
    ),
    FlowPin(
      id: 'speed',
      label: 'Speed',
      type: FlowType.number,
      defaultValue: 1.0,
    ),
    _execOut,
    FlowPin(
      id: 'found',
      label: 'Found',
      type: FlowType.boolean,
      isInput: false,
      doc: 'False when the node carries no animation by that name.',
    ),
  ],
  evaluate: (context, node, inputs) => (
    outputs: {
      'found': context.host.invoke('playAnimation', {
        'name': inputs['name'],
        'loop': inputs['loop'],
        'speed': inputs['speed'],
      }),
    },
    next: const <String>['then'],
  ),
);

final FlowNodeType stopAnimation = FlowNodeType(
  id: 'scene.stopAnimation',
  label: 'Stop Animation',
  category: 'Scene',
  doc: 'Unbinds a clip this graph started, so the node returns to its pose.',
  pins: const [
    _execIn,
    FlowPin(id: 'name', label: 'Name', type: FlowType.string, defaultValue: ''),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.invoke('stopAnimation', {'name': inputs['name']});
    return _then();
  },
);

final FlowNodeType destroyNode = FlowNodeType(
  id: 'scene.destroy',
  label: 'Destroy',
  category: 'Scene',
  doc: 'Detaches the node from its parent. Everything after this still runs.',
  pins: const [_execIn, _execOut],
  evaluate: (context, node, inputs) {
    context.host.invoke('destroy', const {});
    return _then();
  },
);

final FlowNodeType callAction = FlowNodeType(
  id: 'scene.call',
  label: 'Call Action',
  category: 'Scene',
  doc:
      'Calls a named action on the host, which is how an application hands a '
      'graph something the built-in nodes do not cover.',
  pins: const [
    _execIn,
    FlowPin(
      id: 'action',
      label: 'Action',
      type: FlowType.string,
      defaultValue: '',
    ),
    FlowPin(id: 'value', label: 'Value', type: FlowType.any),
    _execOut,
    FlowPin(id: 'result', label: 'Result', type: FlowType.any, isInput: false),
  ],
  evaluate: (context, node, inputs) => (
    outputs: {
      'result': context.host.invoke('${inputs['action']}', {
        'value': inputs['value'],
      }),
    },
    next: const <String>['then'],
  ),
);

final FlowNodeType setWeather = FlowNodeType(
  id: 'scene.setWeather',
  label: 'Set Weather',
  category: 'Scene',
  doc:
      "Puts the scene's sky into a named weather state. The scene needs a "
      'weather sky for there to be clouds to change.',
  pins: const [
    _execIn,
    FlowPin(
      id: 'weather',
      label: 'Weather',
      type: FlowType.string,
      defaultValue: 'clear',
      doc:
          'One of clear, fair, overcast, fog, rain, storm, snow. The same '
          'names the editor offers.',
    ),
    _execOut,
    FlowPin(
      id: 'changed',
      label: 'Changed',
      type: FlowType.boolean,
      isInput: false,
      doc: 'False when the name is unknown or the sky has no clouds.',
    ),
  ],
  evaluate: (context, node, inputs) => (
    outputs: {
      'changed': context.host.invoke('setWeather', {
        'weather': inputs['weather'],
      }),
    },
    next: const <String>['then'],
  ),
);

final FlowNodeType setTimeOfDay = FlowNodeType(
  id: 'scene.setTimeOfDay',
  label: 'Set Time of Day',
  category: 'Scene',
  doc: "Points the sky's sun at an hour on the clock.",
  pins: const [
    _execIn,
    FlowPin(
      id: 'hour',
      label: 'Hour',
      type: FlowType.number,
      defaultValue: 12.0,
      doc: '0 to 24. 12 is noon; 6 and 18 are the two horizons.',
    ),
    FlowPin(
      id: 'tilt',
      label: 'Arc tilt',
      type: FlowType.number,
      defaultValue: 0.35,
      doc:
          "How far off vertical the sun's arc runs, which is what makes a "
          'latitude and a season.',
    ),
    _execOut,
    FlowPin(
      id: 'changed',
      label: 'Changed',
      type: FlowType.boolean,
      isInput: false,
      doc: 'False when the scene\'s sky has no sun.',
    ),
  ],
  evaluate: (context, node, inputs) => (
    outputs: {
      'changed': context.host.invoke('setTimeOfDay', {
        'hour': inputs['hour'],
        'tilt': inputs['tilt'],
      }),
    },
    next: const <String>['then'],
  ),
);

const FlowPin _animatorName = FlowPin(
  id: 'name',
  label: 'Parameter',
  type: FlowType.string,
  defaultValue: '',
  doc: 'The name a transition condition reads.',
);

const FlowPin _animatorSet = FlowPin(
  id: 'set',
  label: 'Set',
  type: FlowType.boolean,
  isInput: false,
  doc: 'False when the node carries no animator.',
);

final FlowNodeType setAnimatorNumber = FlowNodeType(
  id: 'animator.setNumber',
  label: 'Set Animator Number',
  category: 'Animation',
  doc:
      "Sets a number the machine's conditions read. A graph drives a "
      'character by saying what is true, not by saying which clip to play.',
  pins: const [
    _execIn,
    _animatorName,
    FlowPin(
      id: 'value',
      label: 'Value',
      type: FlowType.number,
      defaultValue: 0.0,
    ),
    _execOut,
    _animatorSet,
  ],
  evaluate: (context, node, inputs) => (
    outputs: {
      'set': context.host.invoke('setAnimatorNumber', {
        'name': inputs['name'],
        'value': inputs['value'],
      }),
    },
    next: const <String>['then'],
  ),
);

final FlowNodeType setAnimatorFlag = FlowNodeType(
  id: 'animator.setFlag',
  label: 'Set Animator Flag',
  category: 'Animation',
  doc: "Sets a flag the machine's conditions read. It holds until changed.",
  pins: const [
    _execIn,
    _animatorName,
    FlowPin(
      id: 'value',
      label: 'Value',
      type: FlowType.boolean,
      defaultValue: true,
    ),
    _execOut,
    _animatorSet,
  ],
  evaluate: (context, node, inputs) => (
    outputs: {
      'set': context.host.invoke('setAnimatorFlag', {
        'name': inputs['name'],
        'value': inputs['value'],
      }),
    },
    next: const <String>['then'],
  ),
);

final FlowNodeType animatorTrigger = FlowNodeType(
  id: 'animator.trigger',
  label: 'Trigger Animator',
  category: 'Animation',
  doc:
      'Raises a trigger until a transition consumes it, which is what makes '
      '"jump" fire once rather than for every frame the button is held.',
  pins: const [_execIn, _animatorName, _execOut, _animatorSet],
  evaluate: (context, node, inputs) => (
    outputs: {
      'set': context.host.invoke('animatorTrigger', {'name': inputs['name']}),
    },
    next: const <String>['then'],
  ),
);

final FlowNodeType animatorState = FlowNodeType(
  id: 'animator.state',
  label: 'Animator State',
  category: 'Animation',
  doc: 'The state the machine is currently in.',
  pins: const [
    FlowPin(
      id: 'layer',
      label: 'Layer',
      type: FlowType.string,
      defaultValue: '',
      doc: 'Empty reads the base layer.',
    ),
    FlowPin(id: 'state', label: 'State', type: FlowType.string, isInput: false),
  ],
  evaluate: (context, node, inputs) => _out({
    'state': context.host.invoke('animatorState', {'layer': inputs['layer']}),
  }),
);

/// The scene-facing node types, in palette order.
/// {@category Flow}
final List<FlowNodeType> sceneFlowNodes = [
  getPosition,
  setPosition,
  getScale,
  setScale,
  setVisible,
  translateNode,
  lookAtPoint,
  playAnimation,
  stopAnimation,
  destroyNode,
  setWeather,
  setTimeOfDay,
  setAnimatorNumber,
  setAnimatorFlag,
  animatorTrigger,
  animatorState,
  callAction,
];

/// A registry holding the standard node types and the scene-facing ones.
/// {@category Flow}
FlowRegistry sceneFlowRegistry() =>
    standardFlowRegistry()..registerAll(sceneFlowNodes);
