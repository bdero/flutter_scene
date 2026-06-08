// Covers the .fscene JSON encoding: canonical write, tolerant (JSONC) read,
// round-trip fidelity, the version/migration framework, and feature gating.

import 'dart:math';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/canonical.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/json/jsonc.dart';
import 'package:flutter_scene/src/fscene/json/property_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Builds a small but representative document deterministically.
SceneDocument _sampleDocument() {
  final doc = SceneDocument(
    documentId: DocumentId.generate(Random(99)),
    allocator: IdAllocator(session: 7),
  );
  doc.generator = 'test';
  doc.featuresRequired.add('skinning');
  doc.stage
    ..exposure = 2.5
    ..toneMapping = 'pbrNeutral'
    ..environment = const AssetEnvironment(AssetRef('assets/env.png'));

  final payload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: 'unskinned',
      length: 480,
    ),
  );
  final geo = doc.addResource(
    GeometryResource(
      doc.newId(),
      payload: payload.id,
      bounds: BoundsSpec(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1)),
    ),
  );
  final mat = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(1, 0.5, 0.25, 1),
        'metallic': const DoubleValue(0.0),
      },
    ),
  );

  final root = doc.createNode(name: 'root', root: true);
  root.transform = TrsTransform(translation: Vector3(0, 1, 0));
  final car = doc.createNode(
    name: 'Car',
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(geo.id),
          'material': ResourceRefValue(mat.id),
        },
      ),
    ],
    layers: 3,
  );
  root.children.add(car.id);
  return doc;
}

// Compares two documents structurally enough to catch round-trip loss.
void _expectSameStructure(SceneDocument a, SceneDocument b) {
  expect(b.documentId, a.documentId);
  expect(b.formatVersion, a.formatVersion);
  expect(b.generator, a.generator);
  expect(b.featuresRequired, a.featuresRequired);
  expect(b.stage.exposure, a.stage.exposure);
  expect(b.stage.environment, isA<AssetEnvironment>());
  expect(b.nodes.keys.toSet(), a.nodes.keys.toSet());
  expect(b.roots, a.roots);
  expect(b.resources.keys.toSet(), a.resources.keys.toSet());
  expect(b.payloads.keys.toSet(), a.payloads.keys.toSet());

  for (final id in a.nodes.keys) {
    final an = a.nodes[id]!;
    final bn = b.nodes[id]!;
    expect(bn.name, an.name);
    expect(bn.layers, an.layers);
    expect(bn.children, an.children);
    expect(bn.components.length, an.components.length);
    expect(bn.transform.toMatrix4(), an.transform.toMatrix4());
  }
}

void main() {
  group('canonicalJson', () {
    test('inlines number arrays and rejects non-finite numbers', () {
      final out = canonicalJson({
        'v': [1.0, 2.0, 3.0],
        'n': 5,
      });
      expect(out, contains('[1.0, 2.0, 3.0]'));
      expect(out.endsWith('\n'), isTrue);
      expect(
        () => canonicalJson(double.nan),
        throwsA(isA<FsceneEncodeException>()),
      );
      expect(
        () => canonicalJson(double.infinity),
        throwsA(isA<FsceneEncodeException>()),
      );
    });

    test('normalizes negative zero', () {
      expect(canonicalJson(-0.0).trim(), '0.0');
    });
  });

  group('stripJsonc', () {
    test('removes comments and trailing commas, keeping string contents', () {
      const src = '''
{
  // a line comment
  "a": 1, /* block */
  "b": "http://x/y, // not a comment",
  "c": [1, 2,],
}
''';
      final stripped = stripJsonc(src);
      expect(stripped, isNot(contains('line comment')));
      expect(stripped, isNot(contains('block')));
      expect(stripped, contains('http://x/y, // not a comment'));
      expect(stripped.replaceAll(RegExp(r'\s'), ''), isNot(contains(',}')));
      expect(stripped.replaceAll(RegExp(r'\s'), ''), isNot(contains(',]')));
    });
  });

  group('property values', () {
    test('every variant round-trips through JSON', () {
      String token(LocalId id) => 'r:${id.toToken()}';
      final values = <PropertyValue>[
        const BoolValue(true),
        const IntValue(-7),
        const DoubleValue(1.5),
        const StringValue('hi'),
        Vec3Value(Vector3(1, 2, 3)),
        QuaternionValue(Quaternion(0, 0, 0, 1)),
        Matrix4Value(Matrix4.identity()),
        const ColorValue(1, 0, 0, 1),
        const ResourceRefValue(LocalId(5, 9)),
        const NodeRefValue(LocalId(5, 10)),
        ListValue([const IntValue(1), const StringValue('x')]),
        MapValue({'k': const BoolValue(false)}),
      ];
      for (final v in values) {
        final decoded = decodePropertyValue(encodePropertyValue(v, token));
        expect(decoded.runtimeType, v.runtimeType);
      }
      // Spot-check a reference's id survives the prefix round-trip.
      final ref = decodePropertyValue(
        encodePropertyValue(const ResourceRefValue(LocalId(5, 9)), token),
      );
      expect((ref as ResourceRefValue).id, const LocalId(5, 9));
    });
  });

  group('document round-trip', () {
    test('write then read reproduces the document', () {
      final doc = _sampleDocument();
      final text = writeFscene(doc);
      final back = readFscene(text);
      _expectSameStructure(doc, back);
    });

    test('canonical write is stable across two passes', () {
      final doc = _sampleDocument();
      final first = writeFscene(doc);
      final second = writeFscene(readFscene(first));
      expect(second, first);
    });

    test('reads through a JSONC superset', () {
      final text = writeFscene(_sampleDocument());
      final loose =
          '// header comment\n${text.replaceFirst('{', '{\n  /* note */')}';
      expect(() => readFscene(loose), returnsNormally);
    });

    test('ignores unknown fields', () {
      final text = writeFscene(_sampleDocument());
      final withExtra = text.replaceFirst('{', '{\n  "futureField": 123,');
      expect(() => readFscene(withExtra), returnsNormally);
    });
  });

  group('versioning', () {
    test('refuses a newer-than-supported version', () {
      final text = writeFscene(
        _sampleDocument(),
      ).replaceFirst('"fscene": 1', '"fscene": 999');
      expect(() => readFscene(text), throwsA(isA<FsceneVersionException>()));
    });

    test('runs the migration chain to the current version', () {
      // A version-0 document plus a single v0 -> v1 migration step.
      final v1Text = writeFscene(_sampleDocument());
      final v0Text = v1Text.replaceFirst('"fscene": 1', '"fscene": 0');
      // Without a migration, version 0 cannot load.
      expect(() => readFscene(v0Text), throwsA(isA<FsceneVersionException>()));
      // With one, it migrates and loads.
      final migrated = readFscene(v0Text, migrations: [(json) => json]);
      expect(migrated.formatVersion, currentFsceneVersion);
    });

    test('refuses an unsupported required feature', () {
      final doc = _sampleDocument();
      doc.featuresRequired.add('timeTravel');
      final text = writeFscene(doc);
      expect(
        () => readFscene(text),
        throwsA(isA<FsceneUnsupportedFeatureException>()),
      );
    });
  });

  group('procedural geometry', () {
    test('cuboid/plane/sphere resources round-trip through JSON', () {
      final doc = SceneDocument(
        documentId: DocumentId.generate(Random(1)),
        allocator: IdAllocator(session: 2),
      );
      doc.createNode(name: 'root', root: true);
      final cuboid = doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: CuboidGeometrySpec(
            extents: Vector3(2, 1, 0.5),
            debugColors: true,
          ),
        ),
      );
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: PlaneGeometrySpec(width: 4, depth: 4, segmentsZ: 3),
        ),
      );
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: SphereGeometrySpec(radius: 0.7, segments: 12, rings: 6),
        ),
      );

      final back = readFscene(writeFscene(doc));
      expect(back.resources, hasLength(3));
      final shape =
          (back.resource(cuboid.id) as GeometryResource).procedural
              as CuboidGeometrySpec;
      expect(shape.extents, Vector3(2, 1, 0.5));
      expect(shape.debugColors, isTrue);
    });
  });
}
