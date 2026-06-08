import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';

/// Resolves a referenced [LocalId] to the text token written for it (a
/// kind-prefixed token such as `geo:7A3F...` for readability). The decoder
/// strips the prefix, so any resolver that produces a parseable token works.
typedef IdTokenResolver = String Function(LocalId id);

/// Encodes [value] as a self-describing JSON tree (a single-key tagged
/// object), using [idToken] to render any referenced ids.
///
/// The tag form round-trips the generic typed model without a per-component
/// schema. Component codecs may later emit a cleaner schema-driven form for
/// known types; this is the general fallback.
Object encodePropertyValue(PropertyValue value, IdTokenResolver idToken) {
  switch (value) {
    case BoolValue(:final value):
      return {'b': value};
    case IntValue(:final value):
      return {'i': value};
    case DoubleValue(:final value):
      return {'d': value};
    case StringValue(:final value):
      return {'s': value};
    case Vec2Value(:final value):
      return {
        'v2': [value.x, value.y],
      };
    case Vec3Value(:final value):
      return {
        'v3': [value.x, value.y, value.z],
      };
    case Vec4Value(:final value):
      return {
        'v4': [value.x, value.y, value.z, value.w],
      };
    case QuaternionValue(:final value):
      return {
        'q': [value.x, value.y, value.z, value.w],
      };
    case Matrix4Value(:final value):
      return {'m4': value.storage.toList()};
    case ColorValue(:final r, :final g, :final b, :final a):
      return {
        'c': [r, g, b, a],
      };
    case ResourceRefValue(:final id):
      return {'rref': idToken(id)};
    case NodeRefValue(:final id):
      return {'nref': idToken(id)};
    case ListValue(:final values):
      return {
        'list': [for (final v in values) encodePropertyValue(v, idToken)],
      };
    case MapValue(:final values):
      return {
        'map': {
          for (final e in values.entries)
            e.key: encodePropertyValue(e.value, idToken),
        },
      };
  }
}

/// Decodes a [PropertyValue] from a tagged JSON tree produced by
/// [encodePropertyValue]. Referenced ids are parsed with [LocalId.parse],
/// which ignores any readability prefix.
PropertyValue decodePropertyValue(Object? json) {
  if (json is! Map || json.length != 1) {
    throw FormatException('Expected a single-key tagged value, got $json');
  }
  final tag = json.keys.first as String;
  final payload = json.values.first;
  switch (tag) {
    case 'b':
      return BoolValue(payload as bool);
    case 'i':
      return IntValue(payload as int);
    case 'd':
      return DoubleValue((payload as num).toDouble());
    case 's':
      return StringValue(payload as String);
    case 'v2':
      final l = payload as List;
      return Vec2Value(Vector2(_d(l[0]), _d(l[1])));
    case 'v3':
      final l = payload as List;
      return Vec3Value(Vector3(_d(l[0]), _d(l[1]), _d(l[2])));
    case 'v4':
      final l = payload as List;
      return Vec4Value(Vector4(_d(l[0]), _d(l[1]), _d(l[2]), _d(l[3])));
    case 'q':
      final l = payload as List;
      return QuaternionValue(
        Quaternion(_d(l[0]), _d(l[1]), _d(l[2]), _d(l[3])),
      );
    case 'm4':
      final l = payload as List;
      return Matrix4Value(Matrix4.fromList([for (final e in l) _d(e)]));
    case 'c':
      final l = payload as List;
      return ColorValue(_d(l[0]), _d(l[1]), _d(l[2]), _d(l[3]));
    case 'rref':
      return ResourceRefValue(LocalId.parse(payload as String));
    case 'nref':
      return NodeRefValue(LocalId.parse(payload as String));
    case 'list':
      return ListValue([
        for (final e in payload as List) decodePropertyValue(e),
      ]);
    case 'map':
      return MapValue({
        for (final e in (payload as Map).entries)
          e.key as String: decodePropertyValue(e.value),
      });
    default:
      throw FormatException('Unknown property value tag: $tag');
  }
}

double _d(Object? v) => (v as num).toDouble();
