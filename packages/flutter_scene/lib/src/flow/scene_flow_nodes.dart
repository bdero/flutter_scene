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
  callAction,
];

/// A registry holding the standard node types and the scene-facing ones.
/// {@category Flow}
FlowRegistry sceneFlowRegistry() =>
    standardFlowRegistry()..registerAll(sceneFlowNodes);
