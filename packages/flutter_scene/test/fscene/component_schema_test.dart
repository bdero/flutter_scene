import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Properties that exist only on one variant of their component, keyed by
/// component type. The delta probe below changes one property at a time
/// against an otherwise-default component, which cannot reach these: a camera
/// realized from `{height: ...}` alone is a perspective camera, and a
/// perspective lens has no height.
const _variantProperties = <String, Set<String>>{
  'camera': {'height'},
};

void main() {
  final registry = defaultComponentRegistry();

  test('the registry exposes the built-in component types', () {
    expect(
      registry.types,
      containsAll([
        'mesh',
        'directionalLight',
        'pointLight',
        'spotLight',
        'camera',
      ]),
    );
  });

  // Serialization is delta-vs-default: realizing an empty spec (all defaults)
  // and serializing must produce an EMPTY property bag, and a component with
  // one changed value must serialize exactly that key. This locks schema
  // defaults, realize fallbacks, and serialize together so none can drift.
  // dollyCameraController is absent on purpose: its path is required and has
  // no default, so an all-defaults instance is not a thing that exists (the
  // mesh codec's geometry is required the same way).
  for (final type in [
    'directionalLight',
    'pointLight',
    'spotLight',
    'camera',
    'orbitCameraController',
    'flyCameraController',
    'followCameraController',
    'firstPersonCameraController',
    'rtsCameraController',
    'cameraDirector',
    'cameraSequence',
    'pathFollower',
  ]) {
    test('$type round-trips as a delta against schema defaults', () {
      final codec = registry.codecFor(type)!;
      final doc = SceneDocument();
      final realized = codec.realize(ComponentSpec(type), RealizeContext(doc))!;
      final spec = codec.serialize(realized, SerializeContext(doc))!;

      expect(
        spec.properties,
        isEmpty,
        reason:
            'an all-defaults $type must serialize empty (delta persistence); '
            'got ${spec.properties.keys}',
      );

      // Round-trip one non-default value per declared writable property kind.
      for (final def in codec.propertySchema) {
        // A property that only exists on one variant of its component is out
        // of reach here: probing it alone realizes the default variant, which
        // does not have it. Those get a variant-aware test of their own.
        if (_variantProperties[type]?.contains(def.name) ?? false) continue;
        final defaultValue = def.defaultValue;
        if (defaultValue == null) continue;
        // Stay inside any hard clamp, or the (correct) write-side clamping
        // folds the value back to the default.
        final hardMax = def.hardMax;
        final hardMin = def.hardMin;
        final changed = switch (defaultValue) {
          DoubleValue(:final value) => DoubleValue(
            hardMax == null || value + 0.25 <= hardMax
                ? value + 0.25
                : value - 0.25,
          ),
          IntValue(:final value) => IntValue(
            hardMax == null || value + 1 <= hardMax ? value + 1 : value - 1,
          ),
          BoolValue(:final value) => BoolValue(!value),
          StringValue() when def.options != null => StringValue(
            def.options!.firstWhere(
              (option) => option != (defaultValue).value,
              orElse: () => (defaultValue).value,
            ),
          ),
          _ => null,
        };
        if (changed == null) continue;
        if (changed is StringValue &&
            changed.value == (defaultValue as StringValue).value) {
          continue;
        }
        if (changed is DoubleValue &&
            hardMin != null &&
            changed.value < hardMin) {
          continue;
        }
        final modified = codec.realize(
          ComponentSpec(type, properties: {def.name: changed}),
          RealizeContext(doc),
        )!;
        final reserialized = codec.serialize(modified, SerializeContext(doc))!;
        expect(reserialized.properties.keys, [
          def.name,
        ], reason: '$type.${def.name} should serialize exactly the delta');
        expect(
          propertyValuesEqual(reserialized.properties[def.name], changed),
          isTrue,
          reason: '$type.${def.name} did not round-trip',
        );
      }
    });
  }

  test('registry serialization applies the universal enabled property', () {
    final codec = registry.codecFor('pointLight')!;
    final doc = SceneDocument();
    final realized = registry.realize(
      ComponentSpec(
        'pointLight',
        properties: {'enabled': const BoolValue(false)},
      ),
      RealizeContext(doc),
    )!;
    expect(realized.enabled, isFalse, reason: 'realize applies enabled');

    final spec = registry.serialize(realized, SerializeContext(doc))!;
    expect(spec.properties['enabled'], isA<BoolValue>());
    expect((spec.properties['enabled']! as BoolValue).value, isFalse);

    realized.enabled = true;
    final enabledSpec = registry.serialize(realized, SerializeContext(doc))!;
    expect(
      enabledSpec.properties.containsKey('enabled'),
      isFalse,
      reason: 'enabled=true is the default and serializes as a delta',
    );
    expect(codec.schema.type, 'pointLight');
  });

  test('aimed directional lights round-trip their local direction', () {
    final codec = registry.codecFor('directionalLight')!;
    final doc = SceneDocument();
    final aimed = codec.realize(
      ComponentSpec(
        'directionalLight',
        properties: {'localDirection': Vec3Value(Vector3(1, 0, 0))},
      ),
      RealizeContext(doc),
    )!;
    final spec = codec.serialize(aimed, SerializeContext(doc))!;
    final direction = spec.properties['localDirection'];
    expect(direction, isA<Vec3Value>());
    expect((direction! as Vec3Value).value.x, 1);
  });

  test('camera activation round-trips', () {
    final codec = registry.codecFor('camera')!;
    final doc = SceneDocument();
    final active = codec.realize(
      ComponentSpec(
        'camera',
        properties: {'activateOnMount': const BoolValue(true)},
      ),
      RealizeContext(doc),
    )!;
    final spec = codec.serialize(active, SerializeContext(doc))!;
    expect((spec.properties['activateOnMount']! as BoolValue).value, isTrue);
  });

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
        // Every declared schema must survive the portable JSON round-trip.
        final reread = ComponentPropertyDef.fromJson(def.toJson());
        expect(reread.name, def.name);
        expect(reread.kind, def.kind);
        expect(reread.constraints.length, def.constraints.length);
      }
    }
  });

  test('mesh declares its resource references', () {
    final mesh = registry.codecFor('mesh')!;
    expect(mesh.propertySchema.map((d) => d.name), [
      'geometry',
      'material',
      'primitives',
      'morphWeights',
    ]);
    expect(mesh.propertySchema[0].kind, ComponentPropertyKind.resourceRef);
    expect(mesh.propertySchema[0].defaultValue, isNull); // required
    expect(mesh.propertySchema[2].kind, ComponentPropertyKind.list);
    expect(mesh.propertySchema[2].itemDef, isNotNull);
    expect(mesh.propertySchema[3].kind, ComponentPropertyKind.list);
    expect(mesh.propertySchema[3].itemDef!.kind, ComponentPropertyKind.number);
  });

  test('directional light is rotation-aimed and preserves shadow controls', () {
    final directional = registry.codecFor('directionalLight')!;
    final names = directional.propertySchema.map((d) => d.name).toSet();

    expect(names, isNot(contains('direction')));
    expect(
      names,
      containsAll({
        'priority',
        'cacheStaticShadows',
        'shadowAmbientStrength',
        'shadowFilter',
        'shadowCasterFaces',
      }),
    );
  });

  test('spot lights declare caster faces and angle constraints', () {
    final spot = registry.codecFor('spotLight')!;
    final names = spot.propertySchema.map((d) => d.name).toSet();
    expect(names, contains('shadowCasterFaces'));
    final outer = spot.propertySchema.firstWhere(
      (d) => d.name == 'outerConeAngle',
    );
    expect(outer.constraint<AngleRadians>(), isNotNull);
    expect(outer.hardMin, 0);
  });

  test('the camera projection renders as a fixed-option dropdown', () {
    final camera = registry.codecFor('camera')!;
    final projection = camera.propertySchema.firstWhere(
      (d) => d.name == 'projection',
    );
    expect(projection.options, ['perspective', 'orthographic']);
    final fov = camera.propertySchema.firstWhere(
      (d) => d.name == 'fovRadiansY',
    );
    expect(fov.hardMin, greaterThan(0));
    expect(fov.hardMax, lessThan(3.15));
  });

  // Covers what _variantProperties excludes from the generic delta probe.
  test('an orthographic camera round-trips as a delta', () {
    final codec = registry.codecFor('camera')!;
    final doc = SceneDocument();

    ComponentSpec roundTrip(Map<String, PropertyValue> properties) =>
        codec.serialize(
          codec.realize(
            ComponentSpec('camera', properties: properties),
            RealizeContext(doc),
          )!,
          SerializeContext(doc),
        )!;

    // The lens tag is the only non-default, so it is the whole delta: an
    // orthographic camera at its default size writes no size key.
    expect(
      roundTrip({
        'projection': const StringValue('orthographic'),
      }).properties.keys,
      ['projection'],
    );

    final sized = roundTrip({
      'projection': const StringValue('orthographic'),
      'height': const DoubleValue(20),
    });
    expect(sized.properties.keys, unorderedEquals(['projection', 'height']));
    expect((sized.properties['height']! as DoubleValue).value, 20);
    // The perspective-only key must not ride along on an orthographic lens.
    expect(sized.properties, isNot(contains('fovRadiansY')));
  });

  test('builtin visual components declare gizmos that survive JSON', () {
    for (final type in [
      'directionalLight',
      'pointLight',
      'spotLight',
      'rectAreaLight',
      'camera',
      'environmentVolume',
      'audioSource',
      'audioListener',
      'collider',
      'particleEmitter',
      'meshParticleEmitter',
    ]) {
      final schema = registry.codecFor(type)!.schema;
      expect(schema.gizmo, isNotNull, reason: type);
      expect(schema.gizmo!.primitives, isNotEmpty, reason: type);
      final reread = ComponentSchema.fromJson(schema.toJson());
      expect(reread.gizmo!.toJson(), schema.gizmo!.toJson(), reason: type);
    }
    expect(registry.codecFor('mesh')!.schema.gizmo, isNull);
  });

  test('the spot cone binds its aim to the direction property', () {
    final gizmo = registry.codecFor('spotLight')!.schema.gizmo!;
    final cones = gizmo.primitives.whereType<GizmoWireCone>().toList();
    expect(cones, hasLength(2));
    for (final cone in cones) {
      expect(cone.axisBind, 'direction');
    }
  });
}
