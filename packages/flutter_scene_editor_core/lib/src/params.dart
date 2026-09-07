/// Typed parameter coercion for commands.
///
/// Commands receive a loosely typed `Map<String, Object?>` (the same shape an
/// MCP tool call or a UI form produces) and pull validated, typed values out
/// through these helpers. A missing required value or a type mismatch throws
/// [CommandException], so a bad agent call fails loudly rather than corrupting
/// the document.
library;

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
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
  String key, {
  ComponentSchema? schema,
}) {
  final v = _get(params, key);
  if (v == null) return {};
  if (v is! Map) throw CommandException('Param $key must be an object');
  return {
    for (final entry in v.entries)
      '${entry.key}': coercePropertyValue(
        entry.value,
        def: schema?.property('${entry.key}'),
      ),
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
/// With a [def], the declared kind drives the conversion (resolving shape
/// ambiguities such as vec3 versus color channels, and enabling vec2 and
/// matrix4 which have no guessable shape), hard [Range]/[IntRange]
/// constraints clamp numeric values, and a mismatched shape throws a
/// [CommandException] naming the property and expected kind.
///
/// Without a [def], shape-guessing applies: scalars map directly, objects
/// are inspected for tagged forms (`{$resource}`, `{$node}`, `{$quat}`),
/// then color (`{r, g, b, a}`) and vector (`{x, y, z}` or `{x, y, z, w}`)
/// shapes, otherwise a nested [MapValue]; lists become a [ListValue].
PropertyValue coercePropertyValue(Object? value, {ComponentPropertyDef? def}) {
  // An already-typed value needs no coercion, and is the shape a caller
  // seeding a component from one built in code has: a preset effect
  // serialized through its own codec comes back as PropertyValues, not as
  // the JSON a tool or an agent would have sent.
  if (value is PropertyValue) return value;
  if (def != null) return _coerceAgainst(value, def);
  return _coerceByShape(value);
}

PropertyValue _coerceByShape(Object? value) {
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
      return ListValue([for (final e in v) _coerceByShape(e)]);
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
    for (final entry in m.entries) entry.key: _coerceByShape(entry.value),
  });
}

/// Schema-driven coercion; see [coercePropertyValue].
PropertyValue _coerceAgainst(Object? value, ComponentPropertyDef def) {
  CommandException mismatch() => CommandException(
    'Property ${def.name} expects ${def.kind.name}, got '
    '${value.runtimeType}',
  );

  Map<String, Object?>? asMap(Object? v) =>
      v is Map ? v.map((k, entry) => MapEntry('$k', entry)) : null;

  double clampNumber(double number) {
    final min = def.hardMin;
    final max = def.hardMax;
    if (min != null && number < min) number = min;
    if (max != null && number > max) number = max;
    return number;
  }

  List<double>? components(Object? v, List<String> names) {
    final m = asMap(v);
    if (m != null) {
      final out = <double>[];
      for (final name in names) {
        final component = m[name];
        if (component is! num) return null;
        out.add(component.toDouble());
      }
      return out;
    }
    if (v is List && v.length == names.length) {
      final out = <double>[];
      for (final component in v) {
        if (component is! num) return null;
        out.add(component.toDouble());
      }
      return out;
    }
    return null;
  }

  switch (def.kind) {
    case ComponentPropertyKind.boolean:
      if (value is bool) return BoolValue(value);
      throw mismatch();
    case ComponentPropertyKind.integer:
      if (value is num) {
        return IntValue(clampNumber(value.toDouble()).round());
      }
      throw mismatch();
    case ComponentPropertyKind.number:
      if (value is num) return DoubleValue(clampNumber(value.toDouble()));
      throw mismatch();
    case ComponentPropertyKind.string:
    case ComponentPropertyKind.assetRef:
      if (value is String) {
        final options = def.options;
        if (options != null && !options.contains(value)) {
          throw CommandException(
            'Property ${def.name} expects one of $options, got "$value"',
          );
        }
        return StringValue(value);
      }
      throw mismatch();
    case ComponentPropertyKind.vec2:
      final v = components(value, const ['x', 'y']);
      if (v != null) return Vec2Value(Vector2(v[0], v[1]));
      throw mismatch();
    case ComponentPropertyKind.vec3:
      final v = components(value, const ['x', 'y', 'z']);
      if (v != null) return Vec3Value(Vector3(v[0], v[1], v[2]));
      throw mismatch();
    case ComponentPropertyKind.vec4:
      final v = components(value, const ['x', 'y', 'z', 'w']);
      if (v != null) return Vec4Value(Vector4(v[0], v[1], v[2], v[3]));
      throw mismatch();
    case ComponentPropertyKind.quaternion:
      final tagged = asMap(value)?[r'$quat'];
      final v = components(tagged ?? value, const ['x', 'y', 'z', 'w']);
      if (v != null) {
        return QuaternionValue(Quaternion(v[0], v[1], v[2], v[3]));
      }
      throw mismatch();
    case ComponentPropertyKind.matrix4:
      if (value is List && value.length == 16) {
        final storage = <double>[];
        for (final component in value) {
          if (component is! num) throw mismatch();
          storage.add(component.toDouble());
        }
        return Matrix4Value(Matrix4.fromList(storage));
      }
      throw mismatch();
    case ComponentPropertyKind.color:
      var rgba = components(value, const ['r', 'g', 'b', 'a']);
      if (rgba == null) {
        final rgb = components(value, const ['r', 'g', 'b']);
        if (rgb != null) rgba = [...rgb, 1.0];
      }
      if (rgba != null) {
        return ColorValue(rgba[0], rgba[1], rgba[2], rgba[3]);
      }
      throw mismatch();
    case ComponentPropertyKind.resourceRef:
      final tagged = asMap(value)?[r'$resource'];
      final token = tagged ?? value;
      if (token is String) return ResourceRefValue(LocalId.parse(token));
      throw mismatch();
    case ComponentPropertyKind.nodeRef:
      final tagged = asMap(value)?[r'$node'];
      final token = tagged ?? value;
      if (token is String) return NodeRefValue(LocalId.parse(token));
      throw mismatch();
    case ComponentPropertyKind.list:
      if (value is List) {
        final itemDef = def.itemDef;
        return ListValue([
          for (final item in value)
            itemDef == null
                ? _coerceByShape(item)
                : _coerceAgainst(item, itemDef),
        ]);
      }
      throw mismatch();
    case ComponentPropertyKind.object:
      final m = asMap(value);
      if (m != null) {
        final fields = def.objectFields ?? const <ComponentPropertyDef>[];
        ComponentPropertyDef? fieldDef(String name) {
          for (final field in fields) {
            if (field.name == name || field.formerNames.contains(name)) {
              return field;
            }
          }
          return null;
        }

        return MapValue({
          for (final entry in m.entries)
            entry.key: () {
              final field = fieldDef(entry.key);
              return field == null
                  ? _coerceByShape(entry.value)
                  : _coerceAgainst(entry.value, field);
            }(),
        });
      }
      throw mismatch();
    case ComponentPropertyKind.union:
      final m = asMap(value);
      if (m != null) {
        final tag = m[def.unionTag];
        final variants = def.unionVariants ?? const {};
        if (tag is! String || !variants.containsKey(tag)) {
          throw CommandException(
            'Property ${def.name} expects a ${def.unionTag} of '
            '${variants.keys.toList()}, got "$tag"',
          );
        }
        final fields = variants[tag]!;
        ComponentPropertyDef? fieldDef(String name) {
          for (final field in fields) {
            if (field.name == name || field.formerNames.contains(name)) {
              return field;
            }
          }
          return null;
        }

        return MapValue({
          def.unionTag: StringValue(tag),
          for (final entry in m.entries)
            if (entry.key != def.unionTag)
              entry.key: () {
                final field = fieldDef(entry.key);
                return field == null
                    ? _coerceByShape(entry.value)
                    : _coerceAgainst(entry.value, field);
              }(),
        });
      }
      throw mismatch();
    case ComponentPropertyKind.map:
    case ComponentPropertyKind.distribution:
    case ComponentPropertyKind.curve:
    case ComponentPropertyKind.gradient:
      if (value is Map) {
        return _coerceByShape(value);
      }
      throw mismatch();
  }
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
