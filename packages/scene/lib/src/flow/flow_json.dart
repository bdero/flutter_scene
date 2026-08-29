/// A [FlowGraph]'s text form.
///
/// Plain JSON rather than the document's binary payloads: a graph is source,
/// people diff it, and a merge conflict in a level's logic should be readable.
library;

import 'dart:convert';

import 'package:vector_math/vector_math.dart';

import 'flow_graph.dart';

/// The format version written, so a reader can tell an old file from a
/// corrupt one.
const int flowGraphVersion = 1;

/// Encodes [graph] as a JSON object.
/// {@category Flow}
Map<String, Object?> encodeFlowGraph(FlowGraph graph) => {
  'version': flowGraphVersion,
  'nextNodeId': graph.nextNodeId,
  'nodes': [
    for (final node in graph.nodes)
      {
        'id': node.id,
        'type': node.type,
        'x': node.position.x,
        'y': node.position.y,
        if (node.literals.isNotEmpty)
          'literals': {
            for (final entry in node.literals.entries)
              entry.key: _encodeValue(entry.value),
          },
      },
  ],
  'links': [
    for (final link in graph.links)
      {
        'from': link.fromNode,
        'fromPin': link.fromPin,
        'to': link.toNode,
        'toPin': link.toPin,
      },
  ],
  if (graph.variables.isNotEmpty)
    'variables': [
      for (final variable in graph.variables)
        {
          'name': variable.name,
          'type': variable.type.name,
          if (variable.initial != null)
            'initial': _encodeValue(variable.initial),
        },
    ],
};

/// Decodes a graph written by [encodeFlowGraph].
///
/// Lenient about what it does not recognize: an unknown pin literal or a
/// variable of a type this build does not have is kept rather than dropped
/// where it can be, because a graph opened by an older editor and saved again
/// should not quietly lose half of itself.
/// {@category Flow}
FlowGraph decodeFlowGraph(Map<String, Object?> json) {
  final graph = FlowGraph(
    nextNodeId: json['nextNodeId'] is num
        ? (json['nextNodeId']! as num).toInt()
        : 1,
  );
  for (final raw in (json['nodes'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final map = raw.cast<String, Object?>();
    final id = map['id'];
    final type = map['type'];
    if (id is! num || type is! String) continue;
    graph.nodes.add(
      FlowNodeSpec(
        id: id.toInt(),
        type: type,
        position: Vector2(_double(map['x']), _double(map['y'])),
        literals: {
          for (final entry in ((map['literals'] as Map?) ?? const {}).entries)
            '${entry.key}': _decodeValue(entry.value),
        },
      ),
    );
  }
  for (final raw in (json['links'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final map = raw.cast<String, Object?>();
    final from = map['from'];
    final to = map['to'];
    if (from is! num || to is! num) continue;
    if (map['fromPin'] is! String || map['toPin'] is! String) continue;
    graph.links.add(
      FlowLink(
        fromNode: from.toInt(),
        fromPin: map['fromPin']! as String,
        toNode: to.toInt(),
        toPin: map['toPin']! as String,
      ),
    );
  }
  for (final raw in (json['variables'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final map = raw.cast<String, Object?>();
    final name = map['name'];
    if (name is! String) continue;
    graph.variables.add(
      FlowVariable(
        name: name,
        type: FlowType.values.firstWhere(
          (candidate) => candidate.name == map['type'],
          orElse: () => FlowType.any,
        ),
        initial: _decodeValue(map['initial']),
      ),
    );
  }
  // A hand-edited file can leave the counter behind the ids in use, which
  // would hand a fresh node an id a wire already points at.
  for (final node in graph.nodes) {
    if (node.id >= graph.nextNodeId) graph.nextNodeId = node.id + 1;
  }
  return graph;
}

/// [encodeFlowGraph] as an indented JSON string.
/// {@category Flow}
String writeFlowGraph(FlowGraph graph) =>
    const JsonEncoder.withIndent('  ').convert(encodeFlowGraph(graph));

/// Parses a graph from [writeFlowGraph] output.
/// {@category Flow}
FlowGraph readFlowGraph(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('A flow graph must be a JSON object');
  }
  return decodeFlowGraph(decoded.cast<String, Object?>());
}

/// Vectors are the one value that is not already JSON, so they are tagged
/// rather than written as a bare list, which would decode as a list.
Object? _encodeValue(Object? value) => switch (value) {
  Vector3 v => {
    r'$vec3': [v.x, v.y, v.z],
  },
  _ => value,
};

Object? _decodeValue(Object? value) {
  if (value is Map) {
    final tagged = value[r'$vec3'];
    if (tagged is List && tagged.length >= 3) {
      return Vector3(
        _double(tagged[0]),
        _double(tagged[1]),
        _double(tagged[2]),
      );
    }
  }
  return value;
}

double _double(Object? value) => value is num ? value.toDouble() : 0;
