/// Typed parameter coercion for commands.
///
/// Commands receive a loosely typed `Map<String, Object?>` (the same shape an
/// MCP tool call or a UI form produces) and pull validated, typed values out
/// through these helpers. A missing required value or a type mismatch throws
/// [CommandException], so a bad agent call fails loudly rather than corrupting
/// the document.
library;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:vector_math/vector_math.dart';

import 'command.dart';

Object? _get(Map<String, Object?> params, String key) => params[key];

Never _missing(String key) => throw CommandException('Missing param: $key');

/// Reads a required string [key].
String requireString(Map<String, Object?> params, String key) {
  final v = _get(params, key);
  if (v == null) _missing(key);
  if (v is! String) throw CommandException('Param $key must be a string');
  return v;
}

/// Reads an optional string [key], or [orElse] when absent.
String? optionalString(
  Map<String, Object?> params,
  String key, {
  String? orElse,
}) {
  final v = _get(params, key);
  if (v == null) return orElse;
  if (v is! String) throw CommandException('Param $key must be a string');
  return v;
}

/// Reads a required boolean [key].
bool requireBool(Map<String, Object?> params, String key) {
  final v = _get(params, key);
  if (v == null) _missing(key);
  if (v is! bool) throw CommandException('Param $key must be a boolean');
  return v;
}

/// Reads a required integer [key].
int requireInt(Map<String, Object?> params, String key) {
  final v = _get(params, key);
  if (v == null) _missing(key);
  if (v is! int) throw CommandException('Param $key must be an integer');
  return v;
}

/// Reads an optional integer [key], or null when absent.
int? optionalInt(Map<String, Object?> params, String key) {
  final v = _get(params, key);
  if (v == null) return null;
  if (v is! int) throw CommandException('Param $key must be an integer');
  return v;
}

/// Reads a required number [key] (accepts an int or a double).
double requireDouble(Map<String, Object?> params, String key) {
  final v = _get(params, key);
  if (v == null) _missing(key);
  if (v is! num) throw CommandException('Param $key must be a number');
  return v.toDouble();
}

/// Reads a required `{x, y, z}` vector [key].
Vector3 requireVec3(Map<String, Object?> params, String key) {
  final m = _requireObject(params, key);
  return Vector3(_num(m, key, 'x'), _num(m, key, 'y'), _num(m, key, 'z'));
}

/// Reads an optional `{x, y, z}` vector [key], or null when absent.
Vector3? optionalVec3(Map<String, Object?> params, String key) {
  if (_get(params, key) == null) return null;
  return requireVec3(params, key);
}

/// Reads a required `{x, y, z, w}` quaternion [key].
Quaternion requireQuaternion(Map<String, Object?> params, String key) {
  final m = _requireObject(params, key);
  return Quaternion(
    _num(m, key, 'x'),
    _num(m, key, 'y'),
    _num(m, key, 'z'),
    _num(m, key, 'w'),
  );
}

/// Reads an optional quaternion [key], or null when absent.
Quaternion? optionalQuaternion(Map<String, Object?> params, String key) {
  if (_get(params, key) == null) return null;
  return requireQuaternion(params, key);
}

/// Reads a required node id token [key].
LocalId requireNodeId(Map<String, Object?> params, String key) =>
    _requireId(params, key, 'node');

/// Reads an optional node id token [key], or null when absent.
LocalId? optionalNodeId(Map<String, Object?> params, String key) =>
    _optionalId(params, key, 'node');

/// Reads a required list of node id tokens [key].
List<LocalId> requireNodeIdList(Map<String, Object?> params, String key) {
  final v = _get(params, key);
  if (v == null) _missing(key);
  if (v is! List) throw CommandException('Param $key must be a list');
  final out = <LocalId>[];
  for (final item in v) {
    if (item is! String) {
      throw CommandException('Each $key item must be a node id token');
    }
    try {
      out.add(LocalId.parse(item));
    } catch (_) {
      throw CommandException('Param $key has an invalid node id token: $item');
    }
  }
  return out;
}

/// Reads a required resource id token [key].
LocalId requireResourceId(Map<String, Object?> params, String key) =>
    _requireId(params, key, 'resource');

/// Reads an optional resource id token [key], or null when absent.
LocalId? optionalResourceId(Map<String, Object?> params, String key) =>
    _optionalId(params, key, 'resource');

/// Reads a required asset path key [key] as an [AssetRef].
AssetRef requireAssetRef(Map<String, Object?> params, String key) =>
    AssetRef(requireString(params, key));

/// Reads an optional property bag [key] (a JSON object of typed values),
/// coercing each entry through [coercePropertyValue]. Returns an empty map
/// when absent.
Map<String, PropertyValue> optionalPropertyMap(
  Map<String, Object?> params,
  String key,
) {
  final v = _get(params, key);
  if (v == null) return {};
  if (v is! Map) throw CommandException('Param $key must be an object');
  return {
    for (final entry in v.entries)
      '${entry.key}': coercePropertyValue(entry.value),
  };
}

/// Reads an optional override list [key] (`{target, path, value}` objects).
/// Returns an empty list when absent.
List<PropertyOverride> optionalOverrides(
  Map<String, Object?> params,
  String key,
) {
  final v = _get(params, key);
  if (v == null) return [];
  if (v is! List) throw CommandException('Param $key must be a list');
  final result = <PropertyOverride>[];
  for (final item in v) {
    if (item is! Map) {
      throw CommandException('Each $key item must be an object');
    }
    final target = item['target'];
    final path = item['path'];
    if (target is! String || path is! String) {
      throw CommandException('Each $key item needs string target and path');
    }
    result.add(
      PropertyOverride(
        target: LocalId.parse(target),
        path: path,
        value: coercePropertyValue(item['value']),
      ),
    );
  }
  return result;
}

/// Coerces a loosely typed JSON value into a [PropertyValue].
///
/// Scalars map directly. Objects are inspected for tagged forms (`{$resource}`,
/// `{$node}`, `{$quat}`), then color (`{r, g, b, a}`) and vector (`{x, y, z}`
/// or `{x, y, z, w}`) shapes, otherwise a nested [MapValue]. Lists become a
/// [ListValue].
PropertyValue coercePropertyValue(Object? value) {
  switch (value) {
    case bool v:
      return BoolValue(v);
    case int v:
      return IntValue(v);
    case double v:
      return DoubleValue(v);
    case String v:
      return StringValue(v);
    case List<Object?> v:
      return ListValue([for (final e in v) coercePropertyValue(e)]);
    case Map<Object?, Object?> v:
      return _coerceObject(v.map((k, val) => MapEntry('$k', val)));
    case null:
      throw const CommandException('A property value cannot be null');
    default:
      throw CommandException('Unsupported property value: $value');
  }
}

PropertyValue _coerceObject(Map<String, Object?> m) {
  if (m['\$resource'] case final String token) {
    return ResourceRefValue(LocalId.parse(token));
  }
  if (m['\$node'] case final String token) {
    return NodeRefValue(LocalId.parse(token));
  }
  if (m['\$quat'] case final Map<Object?, Object?> q) {
    final qm = q.map((k, v) => MapEntry('$k', v));
    return QuaternionValue(
      Quaternion(
        _num(qm, r'$quat', 'x'),
        _num(qm, r'$quat', 'y'),
        _num(qm, r'$quat', 'z'),
        _num(qm, r'$quat', 'w'),
      ),
    );
  }
  bool has(String k) => m[k] is num;
  if (has('r') && has('g') && has('b') && has('a')) {
    return ColorValue(
      (m['r']! as num).toDouble(),
      (m['g']! as num).toDouble(),
      (m['b']! as num).toDouble(),
      (m['a']! as num).toDouble(),
    );
  }
  if (has('x') && has('y') && has('z')) {
    final x = (m['x']! as num).toDouble();
    final y = (m['y']! as num).toDouble();
    final z = (m['z']! as num).toDouble();
    if (has('w')) {
      return Vec4Value(Vector4(x, y, z, (m['w']! as num).toDouble()));
    }
    return Vec3Value(Vector3(x, y, z));
  }
  return MapValue({
    for (final entry in m.entries) entry.key: coercePropertyValue(entry.value),
  });
}

Map<String, Object?> _requireObject(Map<String, Object?> params, String key) {
  final v = _get(params, key);
  if (v == null) _missing(key);
  if (v is! Map) throw CommandException('Param $key must be an object');
  return v.map((k, value) => MapEntry('$k', value));
}

double _num(Map<String, Object?> m, String key, String field) {
  final v = m[field];
  if (v is! num) throw CommandException('Param $key.$field must be a number');
  return v.toDouble();
}

LocalId _requireId(Map<String, Object?> params, String key, String kind) {
  final token = requireString(params, key);
  try {
    return LocalId.parse(token);
  } catch (_) {
    throw CommandException('Param $key is not a valid $kind id: $token');
  }
}

LocalId? _optionalId(Map<String, Object?> params, String key, String kind) {
  if (_get(params, key) == null) return null;
  return _requireId(params, key, kind);
}
