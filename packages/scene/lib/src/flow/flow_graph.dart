/// The visual scripting graph: nodes, the pins they expose, and the links
/// between them.
///
/// A graph is plain data. It knows nothing about how it runs, which is what
/// lets the same document be edited by a canvas, walked by a validator, and
/// executed by a runtime that never sees the editor.
///
/// Two kinds of wire, and the distinction is the whole model. An **exec** link
/// says what happens next; a **data** link says where a value comes from. Exec
/// pushes forward from an event, data pulls backward from whoever needs it.
library;

import 'package:vector_math/vector_math.dart';

/// What travels along a pin.
/// {@category Flow}
enum FlowType {
  /// Control flow: no value, only an ordering. Drawn as the thick white wire.
  exec('Exec'),

  boolean('Boolean'),
  number('Number'),
  integer('Integer'),
  string('String'),
  vector3('Vector'),

  /// A reference to a scene node, by the document id the host resolves.
  nodeRef('Node'),

  /// Accepts anything. A pin of this type connects to any other, and what
  /// actually arrives is whatever the source produced.
  any('Any');

  const FlowType(this.label);

  /// The name shown on a pin's tooltip and in an error.
  final String label;

  /// Whether a link from a pin of this type may land on [target].
  ///
  /// Exec only ever connects to exec. [any] connects both ways, which is what
  /// lets a Print or a Branch condition take whatever is to hand. Integer
  /// flows into number, because every integer is a number; the reverse is not
  /// allowed, since silently truncating an index is the kind of thing that
  /// shows up three systems later.
  bool connectsTo(FlowType target) {
    if (this == FlowType.exec || target == FlowType.exec) {
      return this == target;
    }
    if (this == FlowType.any || target == FlowType.any) return true;
    if (this == target) return true;
    return this == FlowType.integer && target == FlowType.number;
  }
}

/// One pin on a node: a place a wire can land.
/// {@category Flow}
class FlowPin {
  const FlowPin({
    required this.id,
    required this.label,
    required this.type,
    this.isInput = true,
    this.defaultValue,
    this.doc = '',
  });

  /// Stable within its node type, so a saved link survives a relabelling.
  final String id;

  /// What the pin is called on the canvas.
  final String label;

  final FlowType type;

  /// Whether the pin takes a wire (input) or provides one (output).
  final bool isInput;

  /// The value an unconnected input reads, so a node with sensible defaults
  /// works with nothing wired to it.
  final Object? defaultValue;

  /// One line on what the pin means, shown on hover.
  final String doc;
}

/// One node in a graph: an instance of a registered node type.
/// {@category Flow}
class FlowNodeSpec {
  FlowNodeSpec({
    required this.id,
    required this.type,
    Vector2? position,
    Map<String, Object?>? literals,
  }) : position = position ?? Vector2.zero(),
       literals = literals ?? {};

  /// Unique within the graph.
  final int id;

  /// The registered node type's id.
  final String type;

  /// Where the node sits on the canvas. Layout only; the runtime ignores it.
  final Vector2 position;

  /// Values typed directly into unconnected input pins, keyed by pin id.
  ///
  /// A literal loses to a wire: if something is connected, that wins, and the
  /// literal stays as what the pin falls back to when the wire is removed.
  final Map<String, Object?> literals;
}

/// A wire from one node's output pin to another's input pin.
/// {@category Flow}
class FlowLink {
  const FlowLink({
    required this.fromNode,
    required this.fromPin,
    required this.toNode,
    required this.toPin,
  });

  final int fromNode;
  final String fromPin;
  final int toNode;
  final String toPin;

  @override
  bool operator ==(Object other) =>
      other is FlowLink &&
      other.fromNode == fromNode &&
      other.fromPin == fromPin &&
      other.toNode == toNode &&
      other.toPin == toPin;

  @override
  int get hashCode => Object.hash(fromNode, fromPin, toNode, toPin);

  @override
  String toString() => '$fromNode.$fromPin -> $toNode.$toPin';
}

/// A graph's own variables: named values that persist across a run.
/// {@category Flow}
class FlowVariable {
  FlowVariable({required this.name, required this.type, this.initial});

  /// The name Get and Set nodes reference.
  final String name;

  final FlowType type;

  /// The value the variable holds when a graph starts.
  final Object? initial;
}

/// A visual script: nodes, the wires between them, and its variables.
/// {@category Flow}
class FlowGraph {
  FlowGraph({
    List<FlowNodeSpec>? nodes,
    List<FlowLink>? links,
    List<FlowVariable>? variables,
    this.nextNodeId = 1,
  }) : nodes = nodes ?? [],
       links = links ?? [],
       variables = variables ?? [];

  final List<FlowNodeSpec> nodes;
  final List<FlowLink> links;
  final List<FlowVariable> variables;

  /// The id the next added node takes. Kept on the graph rather than derived
  /// from the highest id in use, so deleting the newest node does not hand
  /// its id to the next one and silently reconnect a stale wire.
  int nextNodeId;

  FlowNodeSpec? node(int id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  FlowVariable? variable(String name) {
    for (final variable in variables) {
      if (variable.name == name) return variable;
    }
    return null;
  }

  /// Adds [node] with a fresh id and returns it.
  FlowNodeSpec add(String type, {Vector2? position}) {
    final node = FlowNodeSpec(id: nextNodeId++, type: type, position: position);
    nodes.add(node);
    return node;
  }

  /// Removes node [id] and every wire touching it.
  void removeNode(int id) {
    nodes.removeWhere((node) => node.id == id);
    links.removeWhere((link) => link.fromNode == id || link.toNode == id);
  }

  /// Connects two pins, replacing whatever the input already had.
  ///
  /// An input takes one wire: two sources for one value is a question with no
  /// answer. An output feeds as many inputs as want it, and an exec output
  /// likewise takes one, since "what happens next" is singular. That
  /// asymmetry is why the exec case is handled here rather than left to the
  /// caller.
  void connect(FlowLink link, {bool execOutputIsSingular = true}) {
    links.removeWhere(
      (existing) =>
          (existing.toNode == link.toNode && existing.toPin == link.toPin) ||
          (execOutputIsSingular &&
              existing.fromNode == link.fromNode &&
              existing.fromPin == link.fromPin),
    );
    links.add(link);
  }

  /// Removes a specific wire.
  void disconnect(FlowLink link) => links.remove(link);

  /// The link feeding input pin ([node], [pin]), or null.
  FlowLink? inputTo(int node, String pin) {
    for (final link in links) {
      if (link.toNode == node && link.toPin == pin) return link;
    }
    return null;
  }

  /// Every link leaving output pin ([node], [pin]).
  List<FlowLink> outputsFrom(int node, String pin) => [
    for (final link in links)
      if (link.fromNode == node && link.fromPin == pin) link,
  ];

  /// A deep copy, so an editor can edit one and keep the other to revert to.
  FlowGraph copy() => FlowGraph(
    nodes: [
      for (final node in nodes)
        FlowNodeSpec(
          id: node.id,
          type: node.type,
          position: node.position.clone(),
          literals: Map.of(node.literals),
        ),
    ],
    links: List.of(links),
    variables: [
      for (final variable in variables)
        FlowVariable(
          name: variable.name,
          type: variable.type,
          initial: variable.initial,
        ),
    ],
    nextNodeId: nextNodeId,
  );
}
