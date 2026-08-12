// Covers schema-aware property coercion: declared kinds resolve shape
// ambiguities, hard ranges clamp, enums validate, structured kinds coerce
// their members, and mismatches throw named errors. Shape-guessing remains
// for schema-less values.

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:test/test.dart';

void main() {
  const number = ComponentPropertyDef(
    'speed',
    ComponentPropertyKind.number,
    constraints: [Range(0, 10)],
  );
  const integer = ComponentPropertyDef(
    'count',
    ComponentPropertyKind.integer,
    constraints: [IntRange(1, 4)],
  );
  const vec2 = ComponentPropertyDef('uv', ComponentPropertyKind.vec2);
  const color = ComponentPropertyDef('tint', ComponentPropertyKind.color);
  const vec3 = ComponentPropertyDef('offset', ComponentPropertyKind.vec3);
  const options = ComponentPropertyDef(
    'mode',
    ComponentPropertyKind.string,
    options: ['alpha', 'additive'],
  );
  const matrix = ComponentPropertyDef('pose', ComponentPropertyKind.matrix4);
  const union = ComponentPropertyDef(
    'shape',
    ComponentPropertyKind.union,
    unionVariants: {
      'sphere': [
        ComponentPropertyDef(
          'radius',
          ComponentPropertyKind.number,
          constraints: [Range(0, null)],
        ),
      ],
      'box': [ComponentPropertyDef('halfExtents', ComponentPropertyKind.vec3)],
    },
  );

  test('kinds resolve shape ambiguities', () {
    // {x, y, z} would shape-guess to Vec3; the color def reads r/g/b.
    final tint = coercePropertyValue({'r': 1, 'g': 0.5, 'b': 0.25}, def: color);
    expect(tint, isA<ColorValue>());
    expect((tint as ColorValue).a, 1.0, reason: 'alpha defaults to opaque');

    final offset = coercePropertyValue({'x': 1, 'y': 2, 'z': 3}, def: vec3);
    expect(offset, isA<Vec3Value>());

    // vec2 has no guessable shape at all; the def makes it representable.
    final uv = coercePropertyValue({'x': 0.5, 'y': 1}, def: vec2);
    expect(uv, isA<Vec2Value>());
    expect((uv as Vec2Value).value.y, 1);
    expect(coercePropertyValue([0.25, 0.75], def: vec2), isA<Vec2Value>());
  });

  test('hard ranges clamp numbers and integers', () {
    expect((coercePropertyValue(25, def: number) as DoubleValue).value, 10);
    expect((coercePropertyValue(-5, def: number) as DoubleValue).value, 0);
    expect((coercePropertyValue(9, def: integer) as IntValue).value, 4);
    expect((coercePropertyValue(0, def: integer) as IntValue).value, 1);
  });

  test('enum options validate', () {
    expect(
      (coercePropertyValue('additive', def: options) as StringValue).value,
      'additive',
    );
    expect(
      () => coercePropertyValue('subtractive', def: options),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          contains('mode'),
        ),
      ),
    );
  });

  test('matrix4 coerces from a 16-element list', () {
    final pose = coercePropertyValue([
      for (var i = 0; i < 16; i++) i.toDouble(),
    ], def: matrix);
    expect(pose, isA<Matrix4Value>());
    expect((pose as Matrix4Value).value.storage[5], 5);
  });

  test('unions validate the tag and coerce variant fields', () {
    final sphere = coercePropertyValue({
      'kind': 'sphere',
      'radius': -2,
    }, def: union);
    expect(sphere, isA<MapValue>());
    final values = (sphere as MapValue).values;
    expect((values['kind']! as StringValue).value, 'sphere');
    expect(
      (values['radius']! as DoubleValue).value,
      0,
      reason: 'variant field constraints clamp',
    );

    expect(
      () => coercePropertyValue({'kind': 'torus'}, def: union),
      throwsA(isA<CommandException>()),
    );
  });

  test('kind mismatches throw named errors', () {
    expect(
      () => coercePropertyValue('fast', def: number),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          allOf(contains('speed'), contains('number')),
        ),
      ),
    );
  });

  test('schema-less coercion keeps shape-guessing', () {
    expect(coercePropertyValue({'x': 1, 'y': 2, 'z': 3}), isA<Vec3Value>());
    expect(
      coercePropertyValue({'r': 1, 'g': 1, 'b': 1, 'a': 1}),
      isA<ColorValue>(),
    );
    expect(coercePropertyValue([1, 2]), isA<ListValue>());
  });

  test('commands coerce against the session schema hook', () {
    final session = EditorSession.empty();
    session.componentSchemaLookup = (type) => type == 'testType'
        ? const ComponentSchema('testType', properties: [number, vec2])
        : null;
    final node = session.document.createNode(name: 'n', root: true);
    session.run('addComponent', {
      'nodeId': node.id.toToken(),
      'componentType': 'testType',
      'properties': {
        'speed': 99,
        'uv': {'x': 0.5, 'y': 0.5},
      },
    });
    final component = session.document.nodes[node.id]!.components.single;
    expect((component.properties['speed']! as DoubleValue).value, 10);
    expect(component.properties['uv'], isA<Vec2Value>());
  });
}
