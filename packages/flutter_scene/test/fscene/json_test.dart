// Covers the .fscene JSON encoding: canonical write, tolerant (JSONC) read,
// round-trip fidelity, the version/migration framework, and feature gating.

import 'dart:convert';
import 'dart:math';

import 'package:scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Builds a small but representative document deterministically.
SceneDocument _sampleDocument() {
  final doc = SceneDocument(
    documentId: DocumentId.generate(Random(99)),
    allocator: IdAllocator(session: 7),
  );
  doc.generator = 'test';
  doc.payloadSource = 'payloads/sample.fsceneb';
  doc.featuresRequired.add('skinning');
  final stageEnv = doc.addResource(
    EnvironmentResource(
      doc.newId(),
      exposure: 2.5,
      toneMapping: 'pbrNeutral',
      environment: const AssetEnvironment(AssetRef('assets/env.png')),
    ),
  );
  doc.stage.environmentRef = stageEnv.id;

  final payload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: 'unskinned',
      length: 480,
    ),
  );
  final indexPayload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.indexBuffer,
      format: 'uint16',
      length: 36,
    ),
  );
  final geo = doc.addResource(
    GeometryResource(
      doc.newId(),
      vertices: payload.id,
      indices: indexPayload.id,
      bounds: BoundsSpec(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1)),
    ),
  );
  final imagePayload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.image,
      format: 'rgba8',
      width: 2,
      height: 2,
      length: 16,
    ),
  );
  final albedo = doc.addResource(
    TextureResource(doc.newId(), payload: imagePayload.id),
  );
  final mat = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(1, 0.5, 0.25, 1),
        'metallic': const DoubleValue(0.0),
        'baseColorTexture': ResourceRefValue(albedo.id),
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
  expect(b.payloadSource, a.payloadSource);
  expect(b.featuresRequired, a.featuresRequired);
  expect(b.stage.environmentRef, a.stage.environmentRef);
  final envA = a.resources[a.stage.environmentRef!]! as EnvironmentResource;
  final envB = b.resources[b.stage.environmentRef!]! as EnvironmentResource;
  expect(envB.exposure, envA.exposure);
  expect(envB.environment, isA<AssetEnvironment>());
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
  test('prefab member components round-trip', () {
    final doc = SceneDocument();
    doc.createNode(root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p.fscene'),
      memberComponents: [
        MemberComponent(
          member: const LocalId(7, 2),
          component: ComponentSpec(
            'turntable',
            properties: {'speed': const DoubleValue(0.8)},
          ),
        ),
      ],
    );

    final back = readFscene(writeFscene(doc));
    final instance = back.rootNodes.single.instance!;
    final mc = instance.memberComponents.single;
    expect(mc.member, const LocalId(7, 2));
    expect(mc.component.type, 'turntable');
    expect((mc.component.properties['speed'] as DoubleValue).value, 0.8);
  });

  test('environment rendering effects round-trip', () {
    final document = SceneDocument();
    final environment = document.addResource(
      EnvironmentResource(
        document.newId(),
        environmentRotationY: 1.25,
        effects: EnvironmentEffectsSpec(
          colorGradingEnabled: true,
          saturation: 1.4,
          lift: Vector3(0.1, 0.2, 0.3),
          colorGradingLut: const AssetRef('looks/teal.cube'),
          colorGradingLutBlend: 0.6,
          bloomEnabled: true,
          bloomIntensity: 1.7,
          vignetteEnabled: true,
          chromaticAberrationEnabled: true,
          filmGrainEnabled: true,
          ambientOcclusionEnabled: true,
          ambientOcclusionSampleCount: 32,
          ambientOcclusionSpecularMode: 'simple',
          screenSpaceReflectionsEnabled: true,
          screenSpaceReflectionsResolutionScale: 0.5,
          fogEnabled: true,
          fogMode: 'linear',
          fogColor: Vector3(0.2, 0.3, 0.4),
          godRaysEnabled: true,
          godRaysStepCount: 48,
          depthOfFieldEnabled: true,
          depthOfFieldQuality: 'high',
          autoExposureEnabled: true,
          autoExposureCompensation: 1.5,
        ),
      ),
    );
    document.stage.environmentRef = environment.id;

    final decoded = readFscene(writeFscene(document));
    final result = decoded.resource(environment.id)! as EnvironmentResource;
    final effects = result.effects;
    expect(result.environmentRotationY, 1.25);
    expect(effects.colorGradingEnabled, isTrue);
    expect(effects.saturation, 1.4);
    expect(effects.lift, Vector3(0.1, 0.2, 0.3));
    expect(effects.colorGradingLut, const AssetRef('looks/teal.cube'));
    expect(effects.colorGradingLutBlend, 0.6);
    expect(effects.bloomEnabled, isTrue);
    expect(effects.bloomIntensity, 1.7);
    expect(effects.vignetteEnabled, isTrue);
    expect(effects.chromaticAberrationEnabled, isTrue);
    expect(effects.filmGrainEnabled, isTrue);
    expect(effects.ambientOcclusionEnabled, isTrue);
    expect(effects.ambientOcclusionSampleCount, 32);
    expect(effects.ambientOcclusionSpecularMode, 'simple');
    expect(effects.screenSpaceReflectionsEnabled, isTrue);
    expect(effects.screenSpaceReflectionsResolutionScale, 0.5);
    expect(effects.fogEnabled, isTrue);
    expect(effects.fogMode, 'linear');
    expect(effects.fogColor, Vector3(0.2, 0.3, 0.4));
    expect(effects.godRaysEnabled, isTrue);
    expect(effects.godRaysStepCount, 48);
    expect(effects.depthOfFieldEnabled, isTrue);
    expect(effects.depthOfFieldQuality, 'high');
    expect(effects.autoExposureEnabled, isTrue);
    expect(effects.autoExposureCompensation, 1.5);
  });

  test('environment effect override presence round-trips', () {
    final inherited = SceneDocument();
    final inheritedEnvironment = inherited.addResource(
      EnvironmentResource(inherited.newId(), overridesEffects: false),
    );
    final inheritedText = writeFscene(inherited);
    expect(inheritedText, isNot(contains('"effects"')));
    expect(
      (readFscene(inheritedText).resource(inheritedEnvironment.id)
              as EnvironmentResource)
          .overridesEffects,
      isFalse,
    );

    final authored = SceneDocument();
    final authoredEnvironment = authored.addResource(
      EnvironmentResource(authored.newId()),
    );
    final authoredText = writeFscene(authored);
    expect(authoredText, contains('"effects": {}'));
    expect(
      (readFscene(authoredText).resource(authoredEnvironment.id)
              as EnvironmentResource)
          .overridesEffects,
      isTrue,
    );
  });

  test('constant diffuse environment round-trips', () {
    final document = SceneDocument();
    final environment = document.addResource(
      EnvironmentResource(
        document.newId(),
        environment: ConstantEnvironment(Vector3(0.2, 0.3, 0.4)),
      ),
    );
    document.stage.environmentRef = environment.id;

    final decoded = readFscene(writeFscene(document));
    final decodedResource =
        decoded.resource(decoded.stage.environmentRef!)! as EnvironmentResource;
    final constant = decodedResource.environment as ConstantEnvironment;

    expect(constant.color, Vector3(0.2, 0.3, 0.4));
  });

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
      ).replaceFirst('"fscene": $currentFsceneVersion', '"fscene": 999');
      expect(() => readFscene(text), throwsA(isA<FsceneVersionException>()));
    });

    test('runs the migration chain to the current version', () {
      final currentText = writeFscene(_sampleDocument());
      final v0Text = currentText.replaceFirst(
        '"fscene": $currentFsceneVersion',
        '"fscene": 0',
      );
      expect(() => readFscene(v0Text), throwsA(isA<FsceneVersionException>()));
      final migrated = readFscene(
        v0Text,
        // One identity step per version hop, derived so the chain tracks
        // currentFsceneVersion instead of hardcoding its length.
        migrations: [
          for (var i = 0; i < currentFsceneVersion; i++) (json) => json,
        ],
      );
      expect(migrated.formatVersion, currentFsceneVersion);
    });

    test('migrates a left-handed version 1 document', () {
      final text = writeFscene(_sampleDocument())
          .replaceFirst('"fscene": $currentFsceneVersion', '"fscene": 1')
          .replaceFirst(
            '"stage": {',
            '"stage": {"handedness": "left", "unitsPerMeter": 1.0, '
                '"upAxis": "y",',
          );
      final document = readFscene(text);
      expect(document.formatVersion, currentFsceneVersion);
    });

    test('refuses a right-handed version 1 document with guidance', () {
      final text = writeFscene(_sampleDocument())
          .replaceFirst('"fscene": $currentFsceneVersion', '"fscene": 1')
          .replaceFirst(
            '"stage": {',
            '"stage": {"handedness": "right", "unitsPerMeter": 1.0, '
                '"upAxis": "y",',
          );
      expect(
        () => readFscene(text),
        throwsA(
          isA<FsceneVersionException>().having(
            (error) => error.message,
            'message',
            contains('Re-import the source glTF'),
          ),
        ),
      );
    });

    test('refuses a version 1 winding-parity exclusion with guidance', () {
      final json = jsonDecode(writeFscene(_sampleDocument())) as Map;
      json['fscene'] = 1;
      final stage = json['stage'] as Map;
      stage
        ..['handedness'] = 'left'
        ..['unitsPerMeter'] = 1.0
        ..['upAxis'] = 'y';
      final nodes = json['nodes'] as Map;
      final node = nodes.values.first as Map;
      node['excludeWindingParity'] = true;

      expect(
        () => readFscene(jsonEncode(json)),
        throwsA(
          isA<FsceneVersionException>().having(
            (error) => error.message,
            'message',
            contains('Re-import the source glTF'),
          ),
        ),
      );
    });

    test('migrates an explicit false winding-parity exclusion', () {
      final json = jsonDecode(writeFscene(_sampleDocument())) as Map;
      json['fscene'] = 1;
      final stage = json['stage'] as Map;
      stage
        ..['handedness'] = 'left'
        ..['unitsPerMeter'] = 1.0
        ..['upAxis'] = 'y';
      final nodes = json['nodes'] as Map;
      final node = nodes.values.first as Map;
      node['excludeWindingParity'] = false;

      final document = readFscene(jsonEncode(json));
      expect(document.formatVersion, currentFsceneVersion);
    });

    test('refuses a document without a format version', () {
      final text = writeFscene(
        _sampleDocument(),
      ).replaceFirst('"fscene": $currentFsceneVersion,', '');
      expect(() => readFscene(text), throwsA(isA<FsceneVersionException>()));
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

    test('migrates a version 4 document and marks legacy index winding', () {
      final doc = SceneDocument();
      final vId = doc.newId();
      final iId = doc.newId();
      doc.addPayload(
        PayloadSpec(
          vId,
          encoding: PayloadEncoding.vertexBuffer,
          layout: 'unskinned',
        ),
      );
      doc.addPayload(
        PayloadSpec(
          iId,
          encoding: PayloadEncoding.indexBuffer,
          format: 'uint16',
        ),
      );
      final geo = doc.addResource(
        GeometryResource(doc.newId(), vertices: vId, indices: iId),
      );

      final json = jsonDecode(writeFscene(doc)) as Map<String, dynamic>;
      json['fscene'] = 4;
      final text = jsonEncode(json);

      final read = readFscene(text);
      expect(read.formatVersion, currentFsceneVersion);
      final readGeo = read.resource(geo.id) as GeometryResource;
      expect(readGeo.legacyWinding, isTrue);
    });
  });

  group('procedural geometry', () {
    test('procedural geometry resources round-trip through JSON', () {
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
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: TorusGeometrySpec(
            radius: 2.5,
            tubeRadius: 0.08,
            radialSegments: 48,
            tubularSegments: 10,
          ),
        ),
      );
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: IcosphereGeometrySpec(radius: 1.75, subdivisions: 3),
        ),
      );

      final back = readFscene(writeFscene(doc));
      expect(back.resources, hasLength(5));
      final shape =
          (back.resource(cuboid.id) as GeometryResource).procedural
              as CuboidGeometrySpec;
      expect(shape.extents, Vector3(2, 1, 0.5));
      expect(shape.debugColors, isTrue);
      final torus = back.resources.values
          .whereType<GeometryResource>()
          .map((resource) => resource.procedural)
          .whereType<TorusGeometrySpec>()
          .single;
      expect(torus.radius, 2.5);
      expect(torus.tubeRadius, 0.08);
      expect(torus.radialSegments, 48);
      expect(torus.tubularSegments, 10);
      final icosphere = back.resources.values
          .whereType<GeometryResource>()
          .map((resource) => resource.procedural)
          .whereType<IcosphereGeometrySpec>()
          .single;
      expect(icosphere.radius, 1.75);
      expect(icosphere.subdivisions, 3);
    });

    test('the newer primitive shapes round-trip through JSON', () {
      final doc = SceneDocument();
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: CylinderGeometrySpec(
            bottomRadius: 0.9,
            topRadius: 0.0,
            height: 3.0,
            radialSegments: 12,
            heightSegments: 2,
            bottomCap: false,
            topCap: true,
          ),
        ),
      );
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: CapsuleGeometrySpec(
            radius: 0.4,
            height: 1.6,
            radialSegments: 20,
            capRings: 5,
          ),
        ),
      );
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: DiscGeometrySpec(radius: 2.25, segments: 64),
        ),
      );
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: WedgeGeometrySpec(size: Vector3(2, 1, 4)),
        ),
      );

      final back = readFscene(writeFscene(doc));
      T only<T extends ProceduralGeometry>() => back.resources.values
          .whereType<GeometryResource>()
          .map((resource) => resource.procedural)
          .whereType<T>()
          .single;

      final cylinder = only<CylinderGeometrySpec>();
      // A zero top radius is a cone, so it must survive as zero rather than
      // falling back to the default radius.
      expect(cylinder.topRadius, 0.0);
      expect(cylinder.bottomRadius, 0.9);
      expect(cylinder.height, 3.0);
      expect(cylinder.radialSegments, 12);
      expect(cylinder.heightSegments, 2);
      // Likewise false must survive rather than reverting to the default.
      expect(cylinder.bottomCap, isFalse);
      expect(cylinder.topCap, isTrue);

      final capsule = only<CapsuleGeometrySpec>();
      expect(capsule.radius, 0.4);
      expect(capsule.height, 1.6);
      expect(capsule.capRings, 5);

      expect(only<DiscGeometrySpec>().radius, 2.25);
      expect(only<DiscGeometrySpec>().segments, 64);
      expect(only<WedgeGeometrySpec>().size, Vector3(2, 1, 4));
    });

    test('a terrain round-trips its generator parameters', () {
      final doc = SceneDocument();
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: TerrainGeometrySpec(
            width: 128,
            depth: 96,
            columns: 129,
            rows: 97,
            amplitude: 12.5,
            frequency: 0.004,
            octaves: 6,
            seed: 4242,
          ),
        ),
      );

      final back = readFscene(writeFscene(doc));
      final terrain =
          (back.resources.values.single as GeometryResource).procedural
              as TerrainGeometrySpec;
      expect(terrain.width, 128);
      expect(terrain.depth, 96);
      expect(terrain.columns, 129);
      expect(terrain.rows, 97);
      expect(terrain.amplitude, 12.5);
      expect(terrain.frequency, 0.004);
      expect(terrain.octaves, 6);
      // The seed is the whole reason this is eight numbers and not a
      // megabyte, so it has to survive exactly.
      expect(terrain.seed, 4242);
    });

    test('a sculpted terrain keeps its heightmap reference', () {
      final doc = SceneDocument();
      final heights = doc.addPayload(
        PayloadSpec(doc.newId(), encoding: PayloadEncoding.floats),
      );
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: TerrainGeometrySpec(
            columns: 5,
            rows: 5,
            heights: heights.id,
          ),
        ),
      );

      final back = readFscene(writeFscene(doc));
      final terrain = back.resources.values
          .whereType<GeometryResource>()
          .map((resource) => resource.procedural)
          .whereType<TerrainGeometrySpec>()
          .single;
      expect(terrain.heights, heights.id);
      expect(terrain.isSculpted, isTrue);
    });

    test('a generated terrain carries no heightmap reference', () {
      final doc = SceneDocument();
      doc.addResource(
        GeometryResource(doc.newId(), procedural: TerrainGeometrySpec()),
      );
      final terrain = readFscene(writeFscene(doc)).resources.values
          .whereType<GeometryResource>()
          .map((resource) => resource.procedural)
          .whereType<TerrainGeometrySpec>()
          .single;
      expect(terrain.heights, isNull);
      expect(terrain.isSculpted, isFalse);
    });

    test('a malformed wedge size falls back rather than throwing', () {
      final doc = SceneDocument();
      doc.addResource(
        GeometryResource(
          doc.newId(),
          procedural: WedgeGeometrySpec(size: Vector3(2, 1, 4)),
        ),
      );
      // A hand-edited document can carry anything; a wrong-length size must
      // not take the whole load down.
      final json = jsonDecode(writeFscene(doc)) as Map<String, Object?>;
      final resources = json['resources']! as Map;
      ((resources.values.single as Map)['procedural'] as Map)['size'] = [1, 2];
      final back = readFscene(jsonEncode(json));
      final wedge =
          (back.resources.values.single as GeometryResource).procedural
              as WedgeGeometrySpec;
      expect(wedge.size, Vector3(1, 1, 1));
    });

    test('fmat materials and external/encoded textures round-trip', () {
      final doc = SceneDocument();
      final assetTexture = doc.addResource(
        TextureResource(doc.newId(), asset: const AssetRef('assets/x.png')),
      );
      final pngPayload = doc.addPayload(
        PayloadSpec(
          doc.newId(),
          encoding: PayloadEncoding.image,
          format: 'png',
          length: 4,
        ),
      );
      final encodedTexture = doc.addResource(
        TextureResource(doc.newId(), payload: pngPayload.id),
      );
      final fmat = doc.addResource(
        MaterialResource(
          doc.newId(),
          type: 'fmat',
          asset: const AssetRef('materials/toon.fmat'),
          properties: {'baseColorTexture': ResourceRefValue(assetTexture.id)},
        ),
      );

      final back = readFscene(writeFscene(doc));
      expect(
        (back.resource(assetTexture.id) as TextureResource).asset?.key,
        'assets/x.png',
      );
      expect(
        (back.resource(encodedTexture.id) as TextureResource).payload,
        pngPayload.id,
      );
      expect(back.payload(pngPayload.id)?.format, 'png');
      final material = back.resource(fmat.id) as MaterialResource;
      expect(material.type, 'fmat');
      expect(material.asset?.key, 'materials/toon.fmat');
    });

    test('texture content roles round-trip, with color left implicit', () {
      final doc = SceneDocument();
      final color = doc.addResource(
        TextureResource(doc.newId(), asset: const AssetRef('albedo.png')),
      );
      final normal = doc.addResource(
        TextureResource(
          doc.newId(),
          asset: const AssetRef('normal.png'),
          content: 'normal',
        ),
      );

      final json = writeFscene(doc);
      expect(json, isNot(contains('"content": "color"')));

      final back = readFscene(json);
      expect((back.resource(color.id) as TextureResource).content, 'color');
      expect((back.resource(normal.id) as TextureResource).content, 'normal');
    });
  });
}
