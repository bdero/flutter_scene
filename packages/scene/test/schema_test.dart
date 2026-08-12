// Covers the component schema descriptor model: constraint tagged-JSON
// round-trips (including unknown-tag preservation), property descriptor and
// schema round-trips with typed defaults and nested structure, and
// former-name lookup.

import 'package:scene/schema.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('constraints', () {
    test('every constraint round-trips through tagged JSON', () {
      const constraints = <PropertyConstraint<Object?>>[
        Range(0, 10),
        Range(null, 5),
        Range.nonNegative(),
        SoftRange(0, 1),
        IntRange(1, 4),
        Step(0.5),
        PowerOfTwo(min: 16, max: 8192),
        AngleRadians(),
        Normalized(),
        LayerMask32(),
        Multiline(),
        TextPattern(r'^event:/.+'),
        AssetExtensions(['.png', '.hdr']),
        MinCount(1),
        SortedDescending('screenSize'),
      ];
      for (final constraint in constraints) {
        final decoded = PropertyConstraint.fromJson(constraint.toJson());
        expect(
          decoded.toJson(),
          constraint.toJson(),
          reason: '${constraint.runtimeType}',
        );
        expect(decoded.runtimeType, constraint.runtimeType);
      }
    });

    test('an unknown tag is preserved verbatim', () {
      final decoded = PropertyConstraint.fromJson({
        'holographic': {'shimmer': 3},
      });
      expect(decoded, isA<UnknownConstraint>());
      expect(decoded.toJson(), {
        'holographic': {'shimmer': 3},
      });
    });
  });

  group('property descriptors', () {
    test('round-trips typed defaults and metadata', () {
      final def = ComponentPropertyDef(
        'intensity',
        ComponentPropertyKind.number,
        defaultValue: const DoubleValue(3),
        doc: 'Light output.',
        group: 'Light',
        constraints: const [Range.nonNegative(), SoftRange(0, 10)],
        formerNames: const ['strength'],
      );
      final reread = ComponentPropertyDef.fromJson(def.toJson());
      expect(reread.name, 'intensity');
      expect(reread.kind, ComponentPropertyKind.number);
      expect((reread.defaultValue! as DoubleValue).value, 3);
      expect(reread.doc, 'Light output.');
      expect(reread.group, 'Light');
      expect(reread.hardMin, 0);
      expect(reread.constraint<SoftRange>()!.max, 10);
      expect(reread.formerNames, ['strength']);
    });

    test('round-trips vector and color defaults', () {
      final axis = ComponentPropertyDef(
        'axis',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3(0, 1, 0)),
      );
      final rereadAxis = ComponentPropertyDef.fromJson(axis.toJson());
      expect((rereadAxis.defaultValue! as Vec3Value).value.y, 1);

      final tint = ComponentPropertyDef(
        'tint',
        ComponentPropertyKind.color,
        defaultValue: const ColorValue(1, 0.5, 0.25, 1),
      );
      final rereadTint = ComponentPropertyDef.fromJson(tint.toJson());
      expect((rereadTint.defaultValue! as ColorValue).g, 0.5);
    });

    test('round-trips nested list, object, and union structure', () {
      final def = ComponentPropertyDef(
        'shape',
        ComponentPropertyKind.union,
        unionVariants: {
          'sphere': [
            const ComponentPropertyDef(
              'radius',
              ComponentPropertyKind.number,
              defaultValue: DoubleValue(0.5),
              constraints: [Range.nonNegative()],
            ),
          ],
          'compound': [
            const ComponentPropertyDef(
              'children',
              ComponentPropertyKind.list,
              itemDef: ComponentPropertyDef(
                'child',
                ComponentPropertyKind.object,
                objectFields: [
                  ComponentPropertyDef('weight', ComponentPropertyKind.number),
                ],
              ),
            ),
          ],
        },
      );
      final reread = ComponentPropertyDef.fromJson(def.toJson());
      expect(reread.unionVariants!.keys, ['sphere', 'compound']);
      expect(reread.unionVariants!['sphere']!.single.hardMin, 0);
      final children = reread.unionVariants!['compound']!.single;
      expect(children.kind, ComponentPropertyKind.list);
      expect(
        children.itemDef!.objectFields!.single.kind,
        ComponentPropertyKind.number,
      );
    });
  });

  group('component schemas', () {
    test('round-trips and resolves former names', () {
      const schema = ComponentSchema(
        'spotLight',
        doc: 'A cone light.',
        icon: 'light',
        formerTypes: ['coneLight'],
        properties: [
          ComponentPropertyDef(
            'outerConeAngle',
            ComponentPropertyKind.number,
            defaultValue: DoubleValue(0.7853981633974483),
            constraints: [AngleRadians()],
            formerNames: ['coneAngle'],
          ),
        ],
      );
      final reread = ComponentSchema.fromJson(schema.toJson());
      expect(reread.type, 'spotLight');
      expect(reread.formerTypes, ['coneLight']);
      expect(reread.property('outerConeAngle'), isNotNull);
      expect(
        reread.property('coneAngle')!.name,
        'outerConeAngle',
        reason: 'former names resolve to the current descriptor',
      );
      expect(reread.property('missing'), isNull);
    });

    test('schema lists skip malformed entries', () {
      final schemas = decodeComponentSchemas([
        const ComponentSchema('spin').toJson(),
        {'no type here': true},
        'not even a map',
      ]);
      expect(schemas, hasLength(1));
      expect(schemas.single.type, 'spin');
    });
  });
}
