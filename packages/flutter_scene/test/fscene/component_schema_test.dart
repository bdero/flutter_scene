import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_test/flutter_test.dart';

bool _propEq(PropertyValue a, PropertyValue b) {
  if (a is DoubleValue && b is DoubleValue) return a.value == b.value;
  if (a is IntValue && b is IntValue) return a.value == b.value;
  if (a is BoolValue && b is BoolValue) return a.value == b.value;
  if (a is StringValue && b is StringValue) return a.value == b.value;
  if (a is Vec3Value && b is Vec3Value) {
    return a.value.x == b.value.x &&
        a.value.y == b.value.y &&
        a.value.z == b.value.z;
  }
  return false;
}

void main() {
  final registry = defaultComponentRegistry();

  test('the registry exposes the built-in component types', () {
    expect(registry.types, containsAll(['mesh', 'directionalLight', 'camera']));
  });

  // For codecs that derive serialize from their schema, realizing an empty
  // spec and serializing must reproduce exactly the schema's keys (in order)
  // and default values. This locks schema, realize defaults, and serialize
  // together so none can drift.
  for (final type in ['directionalLight', 'camera']) {
    test('$type schema, realize defaults, and serialize agree', () {
      final codec = registry.codecFor(type)!;
      final doc = SceneDocument();
      final realized = codec.realize(ComponentSpec(type), RealizeContext(doc))!;
      final spec = codec.serialize(realized, SerializeContext(doc))!;

      expect(
        spec.properties.keys.toList(),
        codec.propertySchema.map((d) => d.name).toList(),
        reason: 'serialized keys must match schema order',
      );
      for (final def in codec.propertySchema) {
        final serialized = spec.properties[def.name];
        expect(serialized, isNotNull, reason: 'missing ${def.name}');
        expect(
          _propEq(serialized!, def.defaultValue!),
          isTrue,
          reason: '$type.${def.name} default does not match realize/serialize',
        );
      }
    });
  }

  test('schema metadata is well-formed', () {
    for (final type in registry.types) {
      final codec = registry.codecFor(type)!;
      final names = <String>{};
      for (final def in codec.propertySchema) {
        expect(names.add(def.name), isTrue, reason: 'duplicate ${def.name}');
        if (def.resourceKind != null) {
          expect(def.kind, ComponentPropertyKind.resourceRef);
        }
        if (def.options != null) {
          expect(def.kind, ComponentPropertyKind.string);
        }
      }
    }
  });

  test('mesh declares its single-primitive resource references', () {
    final mesh = registry.codecFor('mesh')!;
    expect(mesh.propertySchema.map((d) => d.name), ['geometry', 'material']);
    for (final def in mesh.propertySchema) {
      expect(def.kind, ComponentPropertyKind.resourceRef);
      expect(def.defaultValue, isNull); // required, no default
    }
  });
}
