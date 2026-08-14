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

  group('gizmo specs', () {
    test('every primitive round-trips through tagged JSON', () {
      const spec = GizmoSpec([
        GizmoIcon(
          glyph: 'light-sun',
          size: 32,
          color: GizmoColor.bind('color'),
        ),
        GizmoArrow(axis: [0, 0, 1], length: GizmoScalar(1.2)),
        GizmoLines(
          [0, 0, 0, 1, 0, 0],
          visibility: GizmoVisibility.selected,
          color: GizmoColor(1, 1, 1, 0.35),
        ),
        GizmoWireSphere(
          radius: GizmoScalar.bind('range'),
          center: [0, 1, 0],
          xray: false,
        ),
        GizmoWireBox(
          halfExtentsBind: 'shape.halfExtents',
          inflate: GizmoScalar.bind('blendDistance'),
        ),
        GizmoWireBox(halfExtents: [1, 2, 3], center: [0, 0, 1]),
        GizmoWireRect(
          width: GizmoScalar.bind('width'),
          height: GizmoScalar.bind('height'),
        ),
        GizmoWireCircle(radius: GizmoScalar(0.25), axis: [0, 1, 0]),
        GizmoWireCone(
          angle: GizmoScalar.bind('outerConeAngle'),
          range: GizmoScalar.bind('range', scale: 0.5),
          when: GizmoCondition('shape.kind', 'cone'),
        ),
        GizmoWireCapsule(
          radius: GizmoScalar.bind('shape.radius'),
          halfHeight: GizmoScalar.bind('shape.halfHeight'),
        ),
        GizmoFrustum(
          fovY: GizmoScalar.bind('fovRadiansY'),
          near: GizmoScalar.bind('near'),
          far: GizmoScalar.bind('far'),
          visibility: GizmoVisibility.selected,
        ),
      ]);
      final reread = GizmoSpec.fromJson(spec.toJson())!;
      expect(reread.primitives, hasLength(spec.primitives.length));
      for (var i = 0; i < spec.primitives.length; i++) {
        expect(
          reread.primitives[i].toJson(),
          spec.primitives[i].toJson(),
          reason: spec.primitives[i].kind,
        );
        expect(
          reread.primitives[i].runtimeType,
          spec.primitives[i].runtimeType,
        );
      }
    });

    test('scalar and color parameters encode compactly', () {
      expect(const GizmoScalar(2.5).toJson(), 2.5);
      expect(const GizmoScalar.bind('range').toJson(), {'bind': 'range'});
      expect(const GizmoScalar.bind('range', scale: 2).toJson(), {
        'bind': 'range',
        'scale': 2,
      });
      expect(const GizmoColor(1, 0.5, 0, 1).toJson(), [1, 0.5, 0, 1]);
      expect(const GizmoColor.bind('color').toJson(), {'bind': 'color'});
      expect(GizmoColor.fromJson([1, 0, 0])!.a, 1);
    });

    test('unknown primitive kinds are skipped', () {
      final spec = GizmoSpec.fromJson({
        'primitives': [
          {'kind': 'icon'},
          {'kind': 'holoField', 'wobble': 3},
          'not a map',
          {'kind': 'lines', 'points': 'malformed'},
        ],
      })!;
      expect(spec.primitives, hasLength(1));
      expect(spec.primitives.single, isA<GizmoIcon>());
    });

    test('component schemas carry the gizmo block', () {
      const schema = ComponentSchema(
        'pointLight',
        gizmo: GizmoSpec([
          GizmoIcon(color: GizmoColor.bind('color')),
          GizmoWireSphere(
            radius: GizmoScalar.bind('range'),
            visibility: GizmoVisibility.selected,
          ),
        ]),
      );
      final reread = ComponentSchema.fromJson(schema.toJson());
      expect(reread.gizmo, isNotNull);
      expect(reread.gizmo!.primitives, hasLength(2));
      expect(reread.gizmo!.toJson(), schema.gizmo!.toJson());
      expect(
        ComponentSchema.fromJson(const ComponentSchema('bare').toJson()).gizmo,
        isNull,
      );
    });
  });
}
