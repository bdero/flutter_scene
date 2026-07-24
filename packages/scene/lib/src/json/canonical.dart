import 'dart:convert';

/// Thrown when a value cannot be encoded to canonical `.fscene` JSON.
class FsceneEncodeException implements Exception {
  /// Creates an encode exception with the given [message].
  FsceneEncodeException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'FsceneEncodeException: $message';
}

/// Writes [value] (a JSON tree of maps, lists, and primitives) as canonical
/// `.fscene` text.
///
/// The output is deterministic for a given tree: maps keep the encoder's key
/// order, objects and object-arrays are pretty-printed with [indent], and
/// arrays of numbers and booleans (vectors, matrices, colors) are kept inline
/// on one line so diffs stay tight. Doubles are written with a decimal or
/// exponent so they round-trip back to doubles; non-finite numbers are
/// rejected and `-0.0` is normalized to `0.0`.
String canonicalJson(Object? value, {String indent = '  '}) {
  final sb = StringBuffer();
  _write(sb, value, indent, 0);
  sb.write('\n');
  return sb.toString();
}

void _write(StringBuffer sb, Object? v, String indent, int depth) {
  if (v == null) {
    sb.write('null');
  } else if (v is bool) {
    sb.write(v ? 'true' : 'false');
  } else if (v is int) {
    sb.write(v.toString());
  } else if (v is double) {
    sb.write(_formatDouble(v));
  } else if (v is String) {
    sb.write(jsonEncode(v));
  } else if (v is List) {
    _writeList(sb, v, indent, depth);
  } else if (v is Map) {
    _writeMap(sb, v, indent, depth);
  } else {
    throw FsceneEncodeException('Cannot encode value of type ${v.runtimeType}');
  }
}

String _formatDouble(double d) {
  if (d.isNaN || d.isInfinite) {
    throw FsceneEncodeException('Cannot encode non-finite number: $d');
  }
  if (d == 0.0) return '0.0'; // normalizes -0.0
  final s = d.toString();
  // Dart prints whole doubles as `1.0`; ensure a decimal or exponent so the
  // value decodes back to a double rather than an int.
  return s.contains('.') || s.contains('e') || s.contains('E') ? s : '$s.0';
}

bool _isScalar(Object? v) => v == null || v is num || v is bool;

void _writeList(StringBuffer sb, List<Object?> v, String indent, int depth) {
  if (v.isEmpty) {
    sb.write('[]');
    return;
  }
  if (v.every(_isScalar)) {
    sb.write('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) sb.write(', ');
      _write(sb, v[i], indent, depth);
    }
    sb.write(']');
    return;
  }
  final pad = indent * (depth + 1);
  sb.write('[\n');
  for (var i = 0; i < v.length; i++) {
    sb.write(pad);
    _write(sb, v[i], indent, depth + 1);
    if (i < v.length - 1) sb.write(',');
    sb.write('\n');
  }
  sb
    ..write(indent * depth)
    ..write(']');
}

void _writeMap(
  StringBuffer sb,
  Map<Object?, Object?> v,
  String indent,
  int depth,
) {
  if (v.isEmpty) {
    sb.write('{}');
    return;
  }
  final pad = indent * (depth + 1);
  sb.write('{\n');
  final keys = v.keys.toList();
  for (var i = 0; i < keys.length; i++) {
    final k = keys[i];
    sb
      ..write(pad)
      ..write(jsonEncode(k.toString()))
      ..write(': ');
    _write(sb, v[k], indent, depth + 1);
    if (i < keys.length - 1) sb.write(',');
    sb.write('\n');
  }
  sb
    ..write(indent * depth)
    ..write('}');
}
