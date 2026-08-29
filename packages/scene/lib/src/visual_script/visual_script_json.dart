/// A [VisualScriptGraph]'s text form.
///
/// Plain JSON rather than the document's binary payloads: a graph is source,
/// people diff it, and a merge conflict in a level's logic should be readable.
library;

import 'dart:convert';

import 'package:vector_math/vector_math.dart';

import 'blueprint.dart';
import 'visual_script_graph.dart';

/// The format version written, so a reader can tell an old file from a
/// corrupt one.
const int visualScriptVersion = 1;

/// Encodes [graph] as a JSON object.
/// {@category Visual scripting}
Map<String, Object?> encodeVisualScript(VisualScriptGraph graph) => {
  'version': visualScriptVersion,
  'nextNodeId': graph.nextNodeId,
  if (graph.name.isNotEmpty) 'name': graph.name,
  if (graph.kind != VisualScriptGraphKind.eventGraph) 'kind': graph.kind.name,
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

/// Decodes a graph written by [encodeVisualScript].
///
/// Lenient about what it does not recognize: an unknown pin literal or a
/// variable of a type this build does not have is kept rather than dropped
/// where it can be, because a graph opened by an older editor and saved again
/// should not quietly lose half of itself.
/// {@category Visual scripting}
VisualScriptGraph decodeVisualScript(Map<String, Object?> json) {
  final graph = VisualScriptGraph(
    nextNodeId: json['nextNodeId'] is num
        ? (json['nextNodeId']! as num).toInt()
        : 1,
    name: json['name'] is String ? json['name']! as String : '',
    // A graph written before kinds existed is an event graph, which is what
    // every graph was.
    kind:
        VisualScriptGraphKind.values
            .where((kind) => kind.name == json['kind'])
            .firstOrNull ??
        VisualScriptGraphKind.eventGraph,
  );
  for (final raw in (json['nodes'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final map = raw.cast<String, Object?>();
    final id = map['id'];
    final type = map['type'];
    if (id is! num || type is! String) continue;
    graph.nodes.add(
      VisualScriptNodeSpec(
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
      VisualScriptLink(
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
      VisualScriptVariable(
        name: name,
        type: VisualScriptType.values.firstWhere(
          (candidate) => candidate.name == map['type'],
          orElse: () => VisualScriptType.any,
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

/// [encodeVisualScript] as an indented JSON string.
/// {@category Visual scripting}
String writeVisualScript(VisualScriptGraph graph) =>
    const JsonEncoder.withIndent('  ').convert(encodeVisualScript(graph));

/// Parses a graph from [writeVisualScript] output.
/// {@category Visual scripting}
VisualScriptGraph readVisualScript(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('A flow graph must be a JSON object');
  }
  return decodeVisualScript(decoded.cast<String, Object?>());
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

/// Encodes [blueprint] as a JSON object.
///
/// The graphs carry their own kinds and names; the variables sit on the
/// blueprint, because that is where they belong once there is more than one
/// graph to share them.
/// {@category Visual scripting}
Map<String, Object?> encodeBlueprint(Blueprint blueprint) => {
  'version': visualScriptVersion,
  if (blueprint.name.isNotEmpty) 'name': blueprint.name,
  if (blueprint.variables.isNotEmpty)
    'variables': [
      for (final variable in blueprint.variables)
        {
          'name': variable.name,
          'type': variable.type.name,
          if (variable.initial != null)
            'initial': _encodeValue(variable.initial),
        },
    ],
  'graphs': [for (final graph in blueprint.graphs) encodeVisualScript(graph)],
};

/// Decodes a blueprint written by [encodeBlueprint].
///
/// A document holding a bare graph rather than a blueprint reads as a
/// blueprint with that one event graph in it, which is what it was.
/// {@category Visual scripting}
Blueprint decodeBlueprint(Map<String, Object?> json) {
  final raw = json['graphs'];
  if (raw is! List) return Blueprint.of(decodeVisualScript(json));
  final blueprint = Blueprint(
    name: json['name'] is String ? json['name']! as String : '',
  );
  for (final entry in raw) {
    if (entry is! Map) continue;
    blueprint.graphs.add(decodeVisualScript(entry.cast<String, Object?>()));
  }
  for (final entry in (json['variables'] as List? ?? const [])) {
    if (entry is! Map) continue;
    final map = entry.cast<String, Object?>();
    final name = map['name'];
    if (name is! String) continue;
    blueprint.variables.add(
      VisualScriptVariable(
        name: name,
        type:
            VisualScriptType.values
                .where((type) => type.name == map['type'])
                .firstOrNull ??
            VisualScriptType.any,
        initial: _decodeValue(map['initial']),
      ),
    );
  }
  return blueprint;
}

/// [blueprint] as its canonical JSON text.
/// {@category Visual scripting}
String writeBlueprint(Blueprint blueprint) =>
    jsonEncode(encodeBlueprint(blueprint));

/// Reads a blueprint from [source].
/// {@category Visual scripting}
Blueprint readBlueprint(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('A blueprint is a JSON object');
  }
  return decodeBlueprint(decoded.cast<String, Object?>());
}
