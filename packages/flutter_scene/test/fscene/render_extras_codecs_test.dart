// Covers the mesh-derived rendering-extras codecs: trail delta round-trips
// including the optional curve/gradient shaping, LOD level lists (resource
// recovery through origin tags, descending-threshold validation, the
// schema-side sorted constraint), and splat asset stamping with the crop
// object. Trail tests are GPU-gated (the ribbon geometry uploads at
// construction); LOD and splat tests run GPU-free through fakes and
// procedurally built splat sets.

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/lod_component.dart';
import 'package:flutter_scene/src/components/splat_component.dart';
import 'package:flutter_scene/src/components/trail_component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
import 'package:flutter_scene/src/fscene/realize/render_extras_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/splat_geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/splats/gaussian_splats.dart';
import 'package:flutter_scene/src/splats/splat_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:vector_math/vector_math.dart';

class _FakeGeometry implements Geometry {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMaterial implements Material {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRealizer implements ResourceRealizer {
  _FakeRealizer({this.geometries = const {}, this.materials = const {}});

  final Map<LocalId, Geometry> geometries;
  final Map<LocalId, Material> materials;

  @override
  Geometry geometry(LocalId id) => geometries[id]!;

  @override
  Material material(LocalId id) => materials[id]!;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Map<String, PropertyValue> _serialized(
  ComponentCodec codec,
  Component component, {
  SceneDocument? document,
}) {
  final spec = codec.serialize(
    component,
    SerializeContext(document ?? SceneDocument()),
  );
  expect(spec, isNotNull);
  return spec!.properties;
}

GaussianSplats _splats() => GaussianSplats.fromData(SplatData.zeroed(4));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrailCodec', () {
    final codec = TrailCodec();

    bool gpuAvailable;
    try {
      TrailComponent();
      gpuAvailable = true;
    } catch (_) {
      gpuAvailable = false;
    }
    final skip = gpuAvailable
        ? false
        : 'trail geometry uploads need a GPU context';

    test('an empty spec realizes the defaults and serializes empty', () {
      final trail =
          codec.realize(ComponentSpec('trail'), RealizeContext(SceneDocument()))
              as TrailComponent;
      expect(trail.width, 0.25);
      expect(trail.lifetime, 0.6);
      expect(trail.minVertexDistance, 0.05);
      expect(trail.maxPoints, 48);
      expect(trail.widthOverTrail, isNull);
      expect(trail.colorOverTrail, isNull);
      expect(trail.emitting, isTrue);
      expect(_serialized(codec, trail), isEmpty);
    }, skip: skip);

    test('configured values, curve, and gradient round trip', () {
      final spec = ComponentSpec(
        'trail',
        properties: {
          'width': const DoubleValue(0.5),
          'lifetime': const DoubleValue(1.5),
          'minVertexDistance': const DoubleValue(0.2),
          'maxPoints': const IntValue(16),
          'widthOverTrail': encodeParticleCurve(
            ParticleCurve.linear(from: 1, to: 0.2),
          ),
          'colorOverTrail': encodeColorGradient(
            ColorGradient([
              ColorStop(0.0, Vector4(1, 0, 0, 1)),
              ColorStop(1.0, Vector4(0, 0, 1, 0)),
            ]),
          ),
          'emitting': const BoolValue(false),
        },
      );
      final trail =
          codec.realize(spec, RealizeContext(SceneDocument()))
              as TrailComponent;
      expect(trail.width, 0.5);
      expect(trail.lifetime, 1.5);
      expect(trail.minVertexDistance, 0.2);
      expect(trail.maxPoints, 16);
      expect(trail.emitting, isFalse);
      expect(trail.widthOverTrail!.sample(0.0), closeTo(1.0, 1e-6));
      expect(trail.widthOverTrail!.sample(1.0), closeTo(0.2, 1e-6));
      final out = Vector4.zero();
      trail.colorOverTrail!.sample(1.0, out);
      expect(out.z, closeTo(1.0, 1e-6));
      expect(out.w, closeTo(0.0, 1e-6));

      final props = _serialized(codec, trail);
      expect(
        props.keys,
        unorderedEquals([
          'width',
          'lifetime',
          'minVertexDistance',
          'maxPoints',
          'widthOverTrail',
          'colorOverTrail',
          'emitting',
        ]),
      );
      final again =
          codec.realize(
                ComponentSpec('trail', properties: props),
                RealizeContext(SceneDocument()),
              )
              as TrailComponent;
      expect(again.widthOverTrail!.sample(1.0), closeTo(0.2, 1e-6));
      expect(again.maxPoints, 16);
    }, skip: skip);

    test('a maxPoints below the geometry minimum is clamped', () {
      final trail =
          codec.realize(
                ComponentSpec(
                  'trail',
                  properties: {'maxPoints': const IntValue(0)},
                ),
                RealizeContext(SceneDocument()),
              )
              as TrailComponent;
      expect(trail.maxPoints, 2);
    }, skip: skip);
  });

  group('LodCodec', () {
    final codec = LodCodec();

    // Two levels backed by document resources, with the live objects tagged
    // the way the resource realizer would tag them.
    ({
      SceneDocument source,
      ComponentSpec spec,
      Map<LocalId, Geometry> geometries,
      Map<LocalId, Material> materials,
    })
    fixture() {
      final source = SceneDocument();
      final high = source.addResource(
        GeometryResource(
          source.newId(),
          procedural: CuboidGeometrySpec(extents: Vector3(1, 1, 1)),
        ),
      );
      final low = source.addResource(
        GeometryResource(
          source.newId(),
          procedural: CuboidGeometrySpec(extents: Vector3(2, 2, 2)),
        ),
      );
      final material = source.addResource(
        MaterialResource(source.newId(), type: 'unlit'),
      );
      final geometries = <LocalId, Geometry>{
        high.id: tagResourceOrigin(_FakeGeometry(), source, high.id),
        low.id: tagResourceOrigin(_FakeGeometry(), source, low.id),
      };
      final materials = <LocalId, Material>{
        material.id: tagResourceOrigin(_FakeMaterial(), source, material.id),
      };
      final spec = ComponentSpec(
        'lod',
        properties: {
          'levels': ListValue([
            MapValue({
              'geometry': ResourceRefValue(high.id),
              'material': ResourceRefValue(material.id),
              'screenSize': const DoubleValue(0.4),
            }),
            MapValue({
              'geometry': ResourceRefValue(low.id),
              'material': ResourceRefValue(material.id),
              'screenSize': const DoubleValue(0.1),
            }),
          ]),
        },
      );
      return (
        source: source,
        spec: spec,
        geometries: geometries,
        materials: materials,
      );
    }

    test('the levels schema carries the list constraints', () {
      final levels = codec.propertySchema.first;
      expect(levels.name, 'levels');
      expect(levels.constraint<MinCount>()!.count, 1);
      expect(levels.constraint<SortedDescending>()!.fieldName, 'screenSize');
    });

    test('levels realize through the resource realizer and round trip', () {
      final f = fixture();
      final context = RealizeContext(
        f.source,
        resources: _FakeRealizer(
          geometries: f.geometries,
          materials: f.materials,
        ),
      );
      final lod = codec.realize(f.spec, context) as LodComponent;
      expect(lod.levels, hasLength(2));
      expect(lod.levels[0].screenSize, 0.4);
      expect(lod.levels[1].screenSize, 0.1);
      expect(lod.lodBias, 1.0);
      expect(lod.hysteresis, 0.1);
      expect(lod.blendRange, 0.0);

      // All-defaults policy serializes only the levels list.
      final dest = SceneDocument();
      final props = _serialized(codec, lod, document: dest);
      expect(props.keys, ['levels']);
      final entries = (props['levels']! as ListValue).values;
      expect(entries, hasLength(2));
      final first = (entries.first as MapValue).values;
      expect((first['screenSize']! as DoubleValue).value, 0.4);
      // The copied resources landed in the destination document.
      final ref = first['geometry']! as ResourceRefValue;
      expect(dest.resource(ref.id), isA<GeometryResource>());
    });

    test('policy values round trip as a delta', () {
      final f = fixture();
      f.spec.properties['lodBias'] = const DoubleValue(1.5);
      f.spec.properties['hysteresis'] = const DoubleValue(0.2);
      f.spec.properties['blendRange'] = const DoubleValue(0.05);
      final context = RealizeContext(
        f.source,
        resources: _FakeRealizer(
          geometries: f.geometries,
          materials: f.materials,
        ),
      );
      final lod = codec.realize(f.spec, context) as LodComponent;
      expect(lod.lodBias, 1.5);
      expect(lod.hysteresis, 0.2);
      expect(lod.blendRange, 0.05);
      final props = _serialized(codec, lod);
      expect(
        props.keys,
        unorderedEquals(['levels', 'lodBias', 'hysteresis', 'blendRange']),
      );
    });

    test('non-descending thresholds skip the component', () {
      final f = fixture();
      final entries = (f.spec.properties['levels']! as ListValue).values;
      (entries.first as MapValue).values['screenSize'] = const DoubleValue(
        0.05,
      );
      final context = RealizeContext(
        f.source,
        resources: _FakeRealizer(
          geometries: f.geometries,
          materials: f.materials,
        ),
      );
      expect(codec.realize(f.spec, context), isNull);
    });

    test('a missing resource realizer skips the component', () {
      final f = fixture();
      expect(codec.realize(f.spec, RealizeContext(f.source)), isNull);
    });

    test('hand-built levels (no origin tags) do not serialize', () {
      final lod = LodComponent([
        LodLevel(
          geometry: _FakeGeometry(),
          material: _FakeMaterial(),
          screenSize: 0.2,
        ),
      ]);
      expect(codec.serialize(lod, SerializeContext(SceneDocument())), isNull);
    });
  });

  group('SplatCodec', () {
    final codec = SplatCodec();

    test('realize defers the asset load and serializes back losslessly', () {
      final spec = ComponentSpec(
        'splat',
        properties: {
          'splats': const StringValue('assets/garden.ply'),
          'opacity': const DoubleValue(0.5),
        },
      );
      final deferred = codec.realize(spec, RealizeContext(SceneDocument()));
      expect(deferred, isNotNull);
      // The asset decodes asynchronously (on mount), so realize returns a
      // stand-in rather than the live component.
      expect(deferred, isNot(isA<SplatComponent>()));
      expect(codec.claims(deferred!), isTrue);

      final props = _serialized(codec, deferred);
      expect(props.keys.toSet(), spec.properties.keys.toSet());
      for (final key in spec.properties.keys) {
        expect(propertyValuesEqual(props[key], spec.properties[key]), isTrue);
      }
    });

    test('a missing asset skips the component', () {
      expect(
        codec.realize(ComponentSpec('splat'), RealizeContext(SceneDocument())),
        isNull,
      );
    });

    test('buildSplatComponent applies properties and stamps the asset', () {
      final box = Matrix4.identity()..setTranslation(Vector3(1, 2, 3));
      final component = SplatCodec.buildSplatComponent(_splats(), {
        'splats': const StringValue('assets/garden.ply'),
        'opacity': const DoubleValue(0.5),
        'splatScale': const DoubleValue(2.0),
        'tint': Vec4Value(Vector4(1, 0.5, 0.25, 1)),
        'shDegree': const IntValue(0),
        'antialiased': const BoolValue(false),
        'crop': MapValue({
          'mode': const StringValue('exclude'),
          'box': Matrix4Value(box),
        }),
      });
      expect(component.opacity, 0.5);
      expect(component.splatScale, 2.0);
      expect(component.tint.y, closeTo(0.5, 1e-6));
      expect(component.shDegree, 0);
      expect(component.antialiased, isFalse);
      expect(component.cropMode, SplatCropMode.exclude);
      expect(component.cropBox!.getTranslation().x, closeTo(1.0, 1e-6));

      final props = _serialized(codec, component);
      expect(
        props.keys,
        unorderedEquals([
          'splats',
          'opacity',
          'splatScale',
          'tint',
          'shDegree',
          'antialiased',
          'crop',
        ]),
      );
      expect((props['splats']! as StringValue).value, 'assets/garden.ply');
      final crop = (props['crop']! as MapValue).values;
      expect((crop['mode']! as StringValue).value, 'exclude');
      expect(
        (crop['box']! as Matrix4Value).value.getTranslation().z,
        closeTo(3.0, 1e-6),
      );
    });

    test('all defaults serialize to the asset alone', () {
      final component = SplatCodec.buildSplatComponent(_splats(), {
        'splats': const StringValue('assets/garden.ply'),
      });
      // A zeroed set carries no rest SH, so the clamped degree reads 0 and
      // must persist (the schema default is 2).
      expect(_serialized(codec, component).keys, ['splats', 'shDegree']);
    });

    test(
      'a hand-built splat component (no asset stamp) does not serialize',
      () {
        final component = SplatComponent(_splats());
        expect(
          codec.serialize(component, SerializeContext(SceneDocument())),
          isNull,
        );
      },
    );
  });
}
