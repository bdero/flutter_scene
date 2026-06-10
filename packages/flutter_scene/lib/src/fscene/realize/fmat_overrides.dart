/// Applies serialized `.fmat` parameter overrides to a loaded material's or
/// sky's typed parameters.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

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
