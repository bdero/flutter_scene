/// The node types that only make sense with a scene: reading and writing a
/// node's transform, aiming it, playing its animations, and removing it.
///
/// Every one of them goes through the [VisualScriptHost] rather than touching a
/// `Node` directly, so a graph stays testable against a stub and an
/// application can substitute its own host to bound what a graph may do.
library;

import 'package:scene/visual_script.dart';

VisualScriptResult _out(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>[]);
VisualScriptResult _then() =>
    (outputs: const <String, Object?>{}, next: const <String>['then']);

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
const VisualScriptPin _target = VisualScriptPin(
  id: 'target',
  label: 'Target',
  type: VisualScriptType.string,
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

final VisualScriptNodeType getPosition = VisualScriptNodeType(
  id: 'scene.getPosition',
  label: 'Get Position',
  category: 'Scene',
  doc: "Reads a node's local position.",
  pins: const [
    _target,
    VisualScriptPin(
      id: 'value',
      label: 'Position',
      type: VisualScriptType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptVector(
      context.host.read(_path(inputs['target'], 'position')),
    ),
  }),
);

final VisualScriptNodeType setPosition = VisualScriptNodeType(
  id: 'scene.setPosition',
  label: 'Set Position',
  category: 'Scene',
  doc: "Writes a node's local position.",
  pins: const [
    _execIn,
    _target,
    VisualScriptPin(
      id: 'value',
      label: 'Position',
      type: VisualScriptType.vector3,
    ),
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

final VisualScriptNodeType getScale = VisualScriptNodeType(
  id: 'scene.getScale',
  label: 'Get Scale',
  category: 'Scene',
  doc: "Reads a node's local scale.",
  pins: const [
    _target,
    VisualScriptPin(
      id: 'value',
      label: 'Scale',
      type: VisualScriptType.vector3,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptVector(context.host.read(_path(inputs['target'], 'scale'))),
  }),
);

final VisualScriptNodeType setScale = VisualScriptNodeType(
  id: 'scene.setScale',
  label: 'Set Scale',
  category: 'Scene',
  doc: "Writes a node's local scale.",
  pins: const [
    _execIn,
    _target,
    VisualScriptPin(
      id: 'value',
      label: 'Scale',
      type: VisualScriptType.vector3,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.write(_path(inputs['target'], 'scale'), inputs['value']);
    return _then();
  },
);

final VisualScriptNodeType setVisible = VisualScriptNodeType(
  id: 'scene.setVisible',
  label: 'Set Visible',
  category: 'Scene',
  doc: 'Shows or hides a node and its subtree.',
  pins: const [
    _execIn,
    _target,
    VisualScriptPin(
      id: 'value',
      label: 'Visible',
      type: VisualScriptType.boolean,
      defaultValue: true,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.write(_path(inputs['target'], 'visible'), inputs['value']);
    return _then();
  },
);

final VisualScriptNodeType translateNode = VisualScriptNodeType(
  id: 'scene.translate',
  label: 'Translate',
  category: 'Scene',
  doc:
      'Moves the node by an offset. Multiply by Delta Seconds for a rate '
      'rather than a per-frame jump, or the speed follows the frame rate.',
  pins: const [
    _execIn,
    VisualScriptPin(id: 'by', label: 'By', type: VisualScriptType.vector3),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.invoke('translate', {'by': inputs['by']});
    return _then();
  },
);

final VisualScriptNodeType lookAtPoint = VisualScriptNodeType(
  id: 'scene.lookAt',
  label: 'Look At',
  category: 'Scene',
  doc: 'Aims the node at a world-space point.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'target',
      label: 'Point',
      type: VisualScriptType.vector3,
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.invoke('lookAt', {'target': inputs['target']});
    return _then();
  },
);

final VisualScriptNodeType playAnimation = VisualScriptNodeType(
  id: 'scene.playAnimation',
  label: 'Play Animation',
  category: 'Scene',
  doc: "Starts one of the node's parsed animations.",
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'name',
      label: 'Name',
      type: VisualScriptType.string,
      defaultValue: '',
    ),
    VisualScriptPin(
      id: 'loop',
      label: 'Loop',
      type: VisualScriptType.boolean,
      defaultValue: false,
    ),
    VisualScriptPin(
      id: 'speed',
      label: 'Speed',
      type: VisualScriptType.number,
      defaultValue: 1.0,
    ),
    _execOut,
    VisualScriptPin(
      id: 'found',
      label: 'Found',
      type: VisualScriptType.boolean,
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

final VisualScriptNodeType stopAnimation = VisualScriptNodeType(
  id: 'scene.stopAnimation',
  label: 'Stop Animation',
  category: 'Scene',
  doc: 'Unbinds a clip this graph started, so the node returns to its pose.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'name',
      label: 'Name',
      type: VisualScriptType.string,
      defaultValue: '',
    ),
    _execOut,
  ],
  evaluate: (context, node, inputs) {
    context.host.invoke('stopAnimation', {'name': inputs['name']});
    return _then();
  },
);

final VisualScriptNodeType destroyNode = VisualScriptNodeType(
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

final VisualScriptNodeType callAction = VisualScriptNodeType(
  id: 'scene.call',
  label: 'Call Action',
  category: 'Scene',
  doc:
      'Calls a named action on the host, which is how an application hands a '
      'graph something the built-in nodes do not cover.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'action',
      label: 'Action',
      type: VisualScriptType.string,
      defaultValue: '',
    ),
    VisualScriptPin(id: 'value', label: 'Value', type: VisualScriptType.any),
    _execOut,
    VisualScriptPin(
      id: 'result',
      label: 'Result',
      type: VisualScriptType.any,
      isInput: false,
    ),
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

final VisualScriptNodeType setWeather = VisualScriptNodeType(
  id: 'scene.setWeather',
  label: 'Set Weather',
  category: 'Scene',
  doc:
      "Puts the scene's sky into a named weather state. The scene needs a "
      'weather sky for there to be clouds to change.',
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'weather',
      label: 'Weather',
      type: VisualScriptType.string,
      defaultValue: 'clear',
      doc:
          'One of clear, fair, overcast, fog, rain, storm, snow. The same '
          'names the editor offers.',
    ),
    _execOut,
    VisualScriptPin(
      id: 'changed',
      label: 'Changed',
      type: VisualScriptType.boolean,
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

final VisualScriptNodeType setTimeOfDay = VisualScriptNodeType(
  id: 'scene.setTimeOfDay',
  label: 'Set Time of Day',
  category: 'Scene',
  doc: "Points the sky's sun at an hour on the clock.",
  pins: const [
    _execIn,
    VisualScriptPin(
      id: 'hour',
      label: 'Hour',
      type: VisualScriptType.number,
      defaultValue: 12.0,
      doc: '0 to 24. 12 is noon; 6 and 18 are the two horizons.',
    ),
    VisualScriptPin(
      id: 'tilt',
      label: 'Arc tilt',
      type: VisualScriptType.number,
      defaultValue: 0.35,
      doc:
          "How far off vertical the sun's arc runs, which is what makes a "
          'latitude and a season.',
    ),
    _execOut,
    VisualScriptPin(
      id: 'changed',
      label: 'Changed',
      type: VisualScriptType.boolean,
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

const VisualScriptPin _animatorName = VisualScriptPin(
  id: 'name',
  label: 'Parameter',
  type: VisualScriptType.string,
  defaultValue: '',
  doc: 'The name a transition condition reads.',
);

const VisualScriptPin _animatorSet = VisualScriptPin(
  id: 'set',
  label: 'Set',
  type: VisualScriptType.boolean,
  isInput: false,
  doc: 'False when the node carries no animator.',
);

final VisualScriptNodeType setAnimatorNumber = VisualScriptNodeType(
  id: 'animator.setNumber',
  label: 'Set Animator Number',
  category: 'Animation',
  doc:
      "Sets a number the machine's conditions read. A graph drives a "
      'character by saying what is true, not by saying which clip to play.',
  pins: const [
    _execIn,
    _animatorName,
    VisualScriptPin(
      id: 'value',
      label: 'Value',
      type: VisualScriptType.number,
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

final VisualScriptNodeType setAnimatorFlag = VisualScriptNodeType(
  id: 'animator.setFlag',
  label: 'Set Animator Flag',
  category: 'Animation',
  doc: "Sets a flag the machine's conditions read. It holds until changed.",
  pins: const [
    _execIn,
    _animatorName,
    VisualScriptPin(
      id: 'value',
      label: 'Value',
      type: VisualScriptType.boolean,
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

final VisualScriptNodeType animatorTrigger = VisualScriptNodeType(
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

final VisualScriptNodeType animatorState = VisualScriptNodeType(
  id: 'animator.state',
  label: 'Animator State',
  category: 'Animation',
  doc: 'The state the machine is currently in.',
  pins: const [
    VisualScriptPin(
      id: 'layer',
      label: 'Layer',
      type: VisualScriptType.string,
      defaultValue: '',
      doc: 'Empty reads the base layer.',
    ),
    VisualScriptPin(
      id: 'state',
      label: 'State',
      type: VisualScriptType.string,
      isInput: false,
    ),
  ],
  evaluate: (context, node, inputs) => _out({
    'state': context.host.invoke('animatorState', {'layer': inputs['layer']}),
  }),
);

/// The scene-facing node types, in palette order.
/// {@category Visual scripting}
final List<VisualScriptNodeType> sceneVisualScriptNodes = [
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
/// {@category Visual scripting}
VisualScriptRegistry sceneVisualScriptRegistry() =>
    standardVisualScriptRegistry()..registerAll(sceneVisualScriptNodes);
