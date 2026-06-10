/// Applies serialized `.fmat` parameter overrides to a loaded material's or
/// sky's typed parameters.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material_parameters.dart';

/// Applies [properties] to [parameters] by name, dispatching each
/// [PropertyValue] to the matching typed setter. A texture reference is
/// resolved through [resolveTexture] when supplied. An override that does not
/// match a declared parameter (or whose type disagrees with the declaration)
/// is skipped with a warning rather than failing the load.
void applyFmatParameterOverrides(
  MaterialParameters parameters,
  Map<String, PropertyValue> properties, {
  gpu.Texture? Function(LocalId id)? resolveTexture,
}) {
  for (final entry in properties.entries) {
    final name = entry.key;
    try {
      switch (entry.value) {
        case BoolValue(:final value):
          parameters.setInt(name, value ? 1 : 0);
        case IntValue(:final value):
          parameters.setInt(name, value);
        case DoubleValue(:final value):
          parameters.setFloat(name, value);
        case Vec2Value(:final value):
          parameters.setVec2(name, value);
        case Vec3Value(:final value):
          parameters.setVec3(name, value);
        case Vec4Value(:final value):
          parameters.setVec4(name, value);
        case ColorValue(:final r, :final g, :final b, :final a):
          parameters.setColor(
            name,
            Color.from(alpha: a, red: r, green: g, blue: b),
          );
        case Matrix4Value(:final value):
          parameters.setMat4(name, value);
        case ResourceRefValue(:final id):
          final texture = resolveTexture?.call(id);
          if (texture == null) {
            debugPrint(
              'fscene: fmat parameter "$name" references texture $id, which '
              'could not be resolved here; skipping',
            );
          } else {
            parameters.setTexture(name, texture);
          }
        default:
          debugPrint(
            'fscene: unsupported fmat parameter override type for "$name"; '
            'skipping',
          );
      }
    } catch (e) {
      debugPrint('fscene: failed to apply fmat parameter "$name": $e');
    }
  }
}

/// Maps the values recorded by `MaterialParameters.assignedValues` back to
/// their serialized [PropertyValue] form, the reverse of
/// [applyFmatParameterOverrides]. A texture value is resolved through
/// [resolveTexture]; when that is absent (or returns null) the texture is
/// skipped with a warning.
Map<String, PropertyValue> serializeFmatParameterOverrides(
  Map<String, Object> assignedValues, {
  LocalId? Function(gpu.Texture texture)? resolveTexture,
}) {
  final properties = <String, PropertyValue>{};
  assignedValues.forEach((name, value) {
    switch (value) {
      case double v:
        properties[name] = DoubleValue(v);
      case int v:
        properties[name] = IntValue(v);
      case Vector2 v:
        properties[name] = Vec2Value(v.clone());
      case Vector3 v:
        properties[name] = Vec3Value(v.clone());
      case Vector4 v:
        properties[name] = Vec4Value(v.clone());
      case Matrix4 v:
        properties[name] = Matrix4Value(v.clone());
      case Color c:
        properties[name] = ColorValue(c.r, c.g, c.b, c.a);
      case gpu.Texture t:
        final id = resolveTexture?.call(t);
        if (id == null) {
          debugPrint(
            'fscene: fmat texture parameter "$name" cannot be serialized '
            'here; skipping',
          );
        } else {
          properties[name] = ResourceRefValue(id);
        }
      default:
        debugPrint(
          'fscene: fmat parameter "$name" has an unserializable value '
          '(${value.runtimeType}); skipping',
        );
    }
  });
  return properties;
}
