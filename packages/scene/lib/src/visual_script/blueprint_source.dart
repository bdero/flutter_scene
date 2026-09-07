/// A blueprint as text you can read and edit.
///
/// A graph is JSON on disk, which is the right thing for a machine and the
/// wrong thing for a person: nobody reviews a diff of node ids, and nobody
/// fixes a typo in a wire by editing `{"from":7,"fromPin":"then"}`. This is
/// the same graph written as source — one statement per node, wires written
/// as `from.pin -> to.pin` — so a blueprint can be opened as code, edited as
/// code, and handed back to the editor as a graph.
///
/// The round trip is the whole point, so the format is deliberately explicit
/// rather than clever. Nesting a data source inside the statement that uses it
/// reads better right up until the value is used twice, and then it either
/// silently duplicates the node or needs a rule about when it does not. Every
/// node gets its own line and its own name, and every wire is written out.
///
/// **Identity.** Node ids are an implementation detail and do not survive: the
/// text names nodes, and parsing assigns fresh ids in the order the names
/// appear. Two graphs that print the same are the same blueprint, which is
/// the equivalence that matters — [blueprintEquivalent] is that comparison.
library;

import 'package:vector_math/vector_math.dart';

import 'visual_script_graph.dart';

/// The format version written at the top of every blueprint.
const int blueprintSourceVersion = 1;

/// One problem found while reading a blueprint.
/// {@category Flow}
class BlueprintDiagnostic {
  const BlueprintDiagnostic({
    required this.line,
    required this.message,
    this.text = '',
  });

  /// The 1-based line it was found on.
  final int line;

  /// What is wrong, phrased for whoever is looking at the line.
  final String message;

  /// The line itself, as written.
  final String text;

  @override
  String toString() => 'line $line: $message';
}

/// What reading a blueprint produced.
///
/// A graph is returned even when there are problems: a blueprint with one bad
/// wire in it is still mostly a blueprint, and dropping the whole thing
/// because of a typo is how an editor loses somebody's afternoon.
/// {@category Flow}
class BlueprintParseResult {
  const BlueprintParseResult({required this.graph, required this.diagnostics});

  final VisualScriptGraph graph;
  final List<BlueprintDiagnostic> diagnostics;

  /// Whether it read cleanly.
  bool get isClean => diagnostics.isEmpty;
}

// --- printing ----------------------------------------------------------------

/// A readable, unique name for every node, keyed by node id.
///
/// Derived from the type's last segment, so `scene.setPosition` is
/// `setPosition`, and numbered only where a name would otherwise repeat.
Map<int, String> _namesFor(VisualScriptGraph graph) {
  final names = <int, String>{};
  final used = <String, int>{};
  for (final node in graph.nodes) {
    final dot = node.type.lastIndexOf('.');
    var base = dot < 0 ? node.type : node.type.substring(dot + 1);
    base = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    if (base.isEmpty) base = 'node';
    final seen = (used[base] ?? 0) + 1;
    used[base] = seen;
    names[node.id] = seen == 1 ? base : '$base$seen';
  }
  return names;
}

String _number(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? value.toStringAsFixed(0)
    : '$value';

/// A value as it is written in source.
String _printValue(Object? value) => switch (value) {
  null => 'null',
  bool() => '$value',
  int() => '$value',
  double() => _number(value),
  String() => '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"',
  Vector3() =>
    'vec3(${_number(value.x)}, ${_number(value.y)}, ${_number(value.z)})',
  Vector2() => 'vec2(${_number(value.x)}, ${_number(value.y)})',
  _ => '"$value"',
};

/// Writes [graph] as blueprint source.
///
/// [name] is written as the blueprint's own name; it is documentation rather
/// than structure, and reading it back does not change the graph.
/// {@category Flow}
String printBlueprint(VisualScriptGraph graph, {String name = ''}) {
  final names = _namesFor(graph);
  final out = StringBuffer()..writeln('blueprint $blueprintSourceVersion');
  if (name.isNotEmpty) out.writeln('name $name');

  if (graph.variables.isNotEmpty) {
    out.writeln();
    for (final variable in graph.variables) {
      out.write('var ${variable.name}: ${variable.type.name}');
      if (variable.initial != null) {
        out.write(' = ${_printValue(variable.initial)}');
      }
      out.writeln();
    }
  }

  if (graph.nodes.isNotEmpty) {
    out.writeln();
    for (final node in graph.nodes) {
      final literals = [
        for (final key in node.literals.keys.toList()..sort())
          '$key: ${_printValue(node.literals[key])}',
      ];
      out.writeln(
        '${names[node.id]} = ${node.type}(${literals.join(', ')}) '
        '@ ${_number(node.position.x)}, ${_number(node.position.y)}',
      );
    }
  }

  if (graph.links.isNotEmpty) {
    out.writeln();
    for (final link in graph.links) {
      final from = names[link.fromNode];
      final to = names[link.toNode];
      // A wire to or from a node that is not in the graph cannot be named, so
      // it is dropped rather than written as a dangling reference that would
      // not read back.
      if (from == null || to == null) continue;
      out.writeln('$from.${link.fromPin} -> $to.${link.toPin}');
    }
  }

  return out.toString();
}

// --- parsing -----------------------------------------------------------------

final RegExp _varPattern = RegExp(
  r'^var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z][A-Za-z0-9]*)\s*'
  r'(?:=\s*(.+))?$',
);

final RegExp _nodePattern = RegExp(
  r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z0-9_.]+)\s*(?:\((.*)\))?\s*'
  r'(?:@\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+))?$',
);

final RegExp _linkPattern = RegExp(
  r'^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z0-9_]+)\s*->\s*'
  r'([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z0-9_]+)$',
);

final RegExp _vec3Pattern = RegExp(
  r'^vec3\(\s*(-?[0-9.eE+-]+)\s*,\s*(-?[0-9.eE+-]+)\s*,\s*(-?[0-9.eE+-]+)\s*\)$',
);

final RegExp _vec2Pattern = RegExp(
  r'^vec2\(\s*(-?[0-9.eE+-]+)\s*,\s*(-?[0-9.eE+-]+)\s*\)$',
);

/// Reads a value written by [_printValue].
Object? _parseValue(String raw) {
  final text = raw.trim();
  if (text == 'null') return null;
  if (text == 'true') return true;
  if (text == 'false') return false;
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    return text
        .substring(1, text.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
  }
  final vec3 = _vec3Pattern.firstMatch(text);
  if (vec3 != null) {
    return Vector3(
      double.parse(vec3.group(1)!),
      double.parse(vec3.group(2)!),
      double.parse(vec3.group(3)!),
    );
  }
  final vec2 = _vec2Pattern.firstMatch(text);
  if (vec2 != null) {
    return Vector2(double.parse(vec2.group(1)!), double.parse(vec2.group(2)!));
  }
  final number = num.tryParse(text);
  if (number != null) return number is int ? number : number.toDouble();
  // Anything else is taken as the text it is, so a value this build does not
  // know about survives being read and written rather than becoming null.
  return text;
}

/// Splits an argument list on commas that are not inside quotes or brackets.
List<String> _splitArguments(String source) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (final rune in source.runes) {
    final char = String.fromCharCode(rune);
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      buffer.write(char);
      escaped = true;
      continue;
    }
    if (char == '"') quoted = !quoted;
    if (!quoted) {
      if (char == '(' || char == '[') depth++;
      if (char == ')' || char == ']') depth--;
      if (char == ',' && depth == 0) {
        parts.add(buffer.toString());
        buffer.clear();
        continue;
      }
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// Reads blueprint [source] into a graph.
///
/// Never throws: everything it cannot make sense of becomes a diagnostic and
/// the rest of the blueprint is read. A line it does not recognize at all is
/// reported and skipped, so one bad line costs one node rather than the file.
/// {@category Flow}
BlueprintParseResult parseBlueprint(String source) {
  final graph = VisualScriptGraph();
  final diagnostics = <BlueprintDiagnostic>[];
  final ids = <String, int>{};
  // Wires are resolved after every node is named, so a blueprint that wires
  // forward reads the same as one that wires backward.
  final pendingLinks = <({int line, String text, Match match})>[];

  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final number = i + 1;
    var text = lines[i];
    // A comment runs to the end of the line, unless it is inside a string.
    final comment = _commentStart(text);
    if (comment >= 0) text = text.substring(0, comment);
    text = text.trim();
    if (text.isEmpty) continue;

    if (text.startsWith('blueprint ') || text == 'blueprint') continue;
    if (text.startsWith('name ')) continue;

    final variable = _varPattern.firstMatch(text);
    if (variable != null) {
      final typeName = variable.group(2)!;
      final type = VisualScriptType.values
          .where((t) => t.name == typeName)
          .firstOrNull;
      if (type == null) {
        diagnostics.add(
          BlueprintDiagnostic(
            line: number,
            message: 'unknown variable type "$typeName"',
            text: text,
          ),
        );
        continue;
      }
      final initial = variable.group(3);
      graph.variables.add(
        VisualScriptVariable(
          name: variable.group(1)!,
          type: type,
          initial: initial == null ? null : _parseValue(initial),
        ),
      );
      continue;
    }

    final link = _linkPattern.firstMatch(text);
    if (link != null) {
      pendingLinks.add((line: number, text: text, match: link));
      continue;
    }

    final node = _nodePattern.firstMatch(text);
    if (node != null) {
      final name = node.group(1)!;
      if (ids.containsKey(name)) {
        diagnostics.add(
          BlueprintDiagnostic(
            line: number,
            message: 'a node is already called "$name"',
            text: text,
          ),
        );
        continue;
      }
      final literals = <String, Object?>{};
      for (final argument in _splitArguments(node.group(3) ?? '')) {
        final colon = argument.indexOf(':');
        if (colon <= 0) {
          diagnostics.add(
            BlueprintDiagnostic(
              line: number,
              message: 'an argument needs a pin name, as "pin: value"',
              text: argument,
            ),
          );
          continue;
        }
        literals[argument.substring(0, colon).trim()] = _parseValue(
          argument.substring(colon + 1),
        );
      }
      final spec = graph.add(
        node.group(2)!,
        position: Vector2(
          double.tryParse(node.group(4) ?? '') ?? 0,
          double.tryParse(node.group(5) ?? '') ?? 0,
        ),
      );
      spec.literals.addAll(literals);
      ids[name] = spec.id;
      continue;
    }

    diagnostics.add(
      BlueprintDiagnostic(
        line: number,
        message: 'not a variable, a node, or a wire',
        text: text,
      ),
    );
  }

  for (final pending in pendingLinks) {
    final match = pending.match;
    final from = ids[match.group(1)!];
    final to = ids[match.group(3)!];
    if (from == null || to == null) {
      diagnostics.add(
        BlueprintDiagnostic(
          line: pending.line,
          message:
              'this wire names ${from == null ? match.group(1) : match.group(3)}'
              ', which is not a node in this blueprint',
          text: pending.text,
        ),
      );
      continue;
    }
    // Straight onto the list rather than through connect(), which would drop
    // a wire that shares an endpoint with one already read. Source says what
    // the graph is; it is not an editing gesture.
    graph.links.add(
      VisualScriptLink(
        fromNode: from,
        fromPin: match.group(2)!,
        toNode: to,
        toPin: match.group(4)!,
      ),
    );
  }

  return BlueprintParseResult(graph: graph, diagnostics: diagnostics);
}

/// Where a `//` comment starts on [line], or -1 when there is none.
///
/// Skips one inside a string, so a path or a message with slashes in it is not
/// cut in half.
int _commentStart(String line) {
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') quoted = !quoted;
    if (!quoted && char == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return i;
    }
  }
  return -1;
}

// --- comparing ---------------------------------------------------------------

/// Whether [a] and [b] are the same blueprint.
///
/// Compares what a blueprint *is* rather than the ids it happens to use: the
/// same nodes in the same order with the same literals and positions, wired
/// the same way, over the same variables. Ids are an implementation detail,
/// and reading source back assigns fresh ones.
/// {@category Flow}
bool blueprintEquivalent(VisualScriptGraph a, VisualScriptGraph b) =>
    printBlueprint(a) == printBlueprint(b);
