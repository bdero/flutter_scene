// Covers the stage's skybox / sky-lighting serialization: the JSON round
// trip, the compose-time stage copy, the diff's stage comparison, and the
// fmat parameter-override application. All GPU-free; applying a stage to a
// live Scene (realizeStage / serializeStage) is GPU-bound and verified via
// the example app.

import 'dart:typed_data';

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// The stage's global look lives in an environment resource it references.
EnvironmentResource _stageEnv(SceneDocument doc) =>
    doc.resources[doc.stage.environmentRef!]! as EnvironmentResource;

// A document whose stage references an environment resource carrying a sky look.
// A fixed allocator makes two calls produce identical ids, so the diff tests can
// compare independent builds.
SceneDocument _skyDocument() {
  final doc = SceneDocument(allocator: IdAllocator(session: 7));
  doc.createNode(name: 'thing', root: true);
  final env = doc.addResource(
    EnvironmentResource(
      doc.newId(),
      exposure: 1.5,
      toneMapping: 'aces',
      skybox: SkyboxSpec(
        GradientSkySpec(
          zenithColor: Vector3(0.1, 0.2, 0.3),
          sunSharpness: 250.0,
        ),
        intensity: 2.0,
      ),
      skyEnvironment: SkyEnvironmentSpec(
        FmatSkySpec(
          const AssetRef('assets/sky.fmat'),
          properties: {'sun_height': const DoubleValue(0.7)},
        ),
        refresh: 'interval',
        intervalSeconds: 2.5,
        faceResolution: 64,
        equirectWidth: 256,
      ),
    ),
  );
  doc.stage.environmentRef = env.id;
  return doc;
}

// A document whose stage references an environment resource built by [look].
SceneDocument _envDocument(void Function(EnvironmentResource) look) {
  final doc = SceneDocument();
  final env = doc.addResource(EnvironmentResource(doc.newId()));
  look(env);
  doc.stage.environmentRef = env.id;
  return doc;
}

void main() {
  group('stage environment-resource sky JSON', () {
    test('skybox and sky environment round-trip', () {
      final restored = readFscene(writeFscene(_skyDocument()));
      final env = _stageEnv(restored);

      final skybox = env.skybox!;
      expect(skybox.intensity, 2.0);
      final gradient = skybox.source as GradientSkySpec;
      expect(gradient.zenithColor.x, closeTo(0.1, 1e-6));
      expect(gradient.zenithColor.z, closeTo(0.3, 1e-6));
      expect(gradient.sunSharpness, 250.0);

      final skyEnv = env.skyEnvironment!;
      expect(skyEnv.refresh, 'interval');
      expect(skyEnv.intervalSeconds, 2.5);
      expect(skyEnv.faceResolution, 64);
      expect(skyEnv.equirectWidth, 256);
      final fmat = skyEnv.source as FmatSkySpec;
      expect(fmat.asset.key, 'assets/sky.fmat');
      expect((fmat.properties['sun_height'] as DoubleValue).value, 0.7);
    });

    test('sky-driven shadow flag round-trips', () {
      final doc = _envDocument(
        (e) => e.skyEnvironment = SkyEnvironmentSpec(
          GradientSkySpec(),
          castShadows: true,
        ),
      );
      expect(
        _stageEnv(readFscene(writeFscene(doc))).skyEnvironment!.castShadows,
        isTrue,
      );

      // The default (off) stays off and is omitted from the JSON.
      _stageEnv(doc).skyEnvironment = SkyEnvironmentSpec(GradientSkySpec());
      expect(writeFscene(doc).contains('castShadows'), isFalse);
      expect(
        _stageEnv(readFscene(writeFscene(doc))).skyEnvironment!.castShadows,
        isFalse,
      );
    });

    test('environment and physical sky sources round-trip', () {
      final doc = _envDocument(
        (e) => e.skybox = SkyboxSpec(EnvironmentSkySpec(blurriness: 0.4)),
      );
      final envSky =
          _stageEnv(readFscene(writeFscene(doc))).skybox!.source
              as EnvironmentSkySpec;
      expect(envSky.blurriness, 0.4);

      _stageEnv(doc).skybox = SkyboxSpec(
        PhysicalSkySpec(
          sunDirection: Vector3(0, 1, 0),
          turbidity: 4.0,
          energy: 1.5,
        ),
      );
      final physical =
          _stageEnv(readFscene(writeFscene(doc))).skybox!.source
              as PhysicalSkySpec;
      expect(physical.sunDirection.y, 1.0);
      expect(physical.turbidity, 4.0);
      expect(physical.energy, 1.5);
    });

    test('an environment without a sky stays empty', () {
      final doc = _envDocument((_) {});
      final env = _stageEnv(readFscene(writeFscene(doc)));
      expect(env.skybox, isNull);
      expect(env.skyEnvironment, isNull);
    });
  });

  group('stage environment JSON', () {
    test('the reflection size round-trips', () {
      final doc = _envDocument((e) => e.radianceCubeSize = 512);
      expect(_stageEnv(readFscene(writeFscene(doc))).radianceCubeSize, 512);
      // Null (the engine default) is omitted.
      expect(
        writeFscene(_envDocument((_) {})).contains('radianceCubeSize'),
        isFalse,
      );
    });

    test('the stage environment-resource reference round-trips', () {
      final doc = SceneDocument();
      final env = doc.addResource(
        EnvironmentResource(doc.newId(), name: 'global'),
      );
      doc.stage.environmentRef = env.id;
      final restored = readFscene(writeFscene(doc));
      expect(restored.stage.environmentRef, env.id);
      expect(restored.resources[env.id], isA<EnvironmentResource>());
    });
  });

  test('compose deep-copies the stage environment sky', () {
    final host = _skyDocument();
    // Give the host an instance so compose produces a new document.
    final prefab = SceneDocument();
    prefab.createNode(name: 'p', root: true);
    host.createNode(name: 'inst', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );

    final composed = composeScene(host, resolve: (_) => prefab);
    final copied = _stageEnv(composed).skybox!.source as GradientSkySpec;
    final original = _stageEnv(host).skybox!.source as GradientSkySpec;
    expect(copied.zenithColor, original.zenithColor);
    original.zenithColor.setValues(9, 9, 9);
    expect(copied.zenithColor.x, isNot(9));
    expect(_stageEnv(composed).skyEnvironment!.refresh, 'interval');
  });

  group('diffScene stage comparison', () {
    test('identical stages do not flag a change', () {
      expect(diffScene(_skyDocument(), _skyDocument()).stageChanged, isFalse);
    });

    test('a sky tweak flags stageChanged', () {
      final next = _skyDocument();
      (_stageEnv(next).skybox!.source as GradientSkySpec).sunSharpness = 100.0;
      final diff = diffScene(_skyDocument(), next);
      expect(diff.stageChanged, isTrue);
      expect(diff.isEmpty, isFalse);
      expect(diff.changed, isEmpty); // no node changes
    });

    test('an exposure tweak flags stageChanged', () {
      final next = _skyDocument();
      _stageEnv(next).exposure = 3.0;
      expect(diffScene(_skyDocument(), next).stageChanged, isTrue);
    });
  });

  group('applyFmatParameterOverrides', () {
    MaterialParameters params() => MaterialParameters.withLayout(
      blockName: 'MaterialParams',
      blockSizeBytes: 48,
      parameters: {
        'tint': (type: FmatType.vec4, offset: 0, sourceColor: false),
        'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
        'steps': (type: FmatType.int_, offset: 20, sourceColor: false),
        'dir': (type: FmatType.vec3, offset: 32, sourceColor: false),
      },
    );

    test('applies typed values at the declared offsets', () {
      final p = params();
      applyFmatParameterOverrides(p, {
        'gloss': const DoubleValue(0.5),
        'steps': const IntValue(4),
        'dir': Vec3Value(Vector3(1, 2, 3)),
        'tint': const ColorValue(0.1, 0.2, 0.3, 1.0),
      });
      expect(p.rawBlock.getFloat32(16, Endian.host), 0.5);
      expect(p.rawBlock.getInt32(20, Endian.host), 4);
      expect(p.rawBlock.getFloat32(32, Endian.host), 1.0);
      expect(p.rawBlock.getFloat32(40, Endian.host), 3.0);
      expect(p.rawBlock.getFloat32(0, Endian.host), closeTo(0.1, 1e-6));
    });

    test('skips unknown names and unresolvable textures without failing', () {
      final p = params();
      applyFmatParameterOverrides(p, {
        'not_a_param': const DoubleValue(1.0),
        'gloss': const StringValue('wrong type'),
        'tint': const ResourceRefValue(LocalId(1, 1)),
      });
      // The block is untouched and no exception escaped.
      expect(p.rawBlock.getFloat32(16, Endian.host), 0.0);
    });

    test('assigned values round-trip back to property values', () {
      final p = params();
      final overrides = <String, PropertyValue>{
        'gloss': const DoubleValue(0.5),
        'steps': const IntValue(4),
        'dir': Vec3Value(Vector3(1, 2, 3)),
        'tint': const ColorValue(0.1, 0.2, 0.3, 1.0),
      };
      applyFmatParameterOverrides(p, overrides);

      final serialized = serializeFmatParameterOverrides(p.assignedValues);
      expect((serialized['gloss'] as DoubleValue).value, 0.5);
      expect((serialized['steps'] as IntValue).value, 4);
      expect((serialized['dir'] as Vec3Value).value, Vector3(1, 2, 3));
      final tint = serialized['tint'] as ColorValue;
      expect(tint.r, closeTo(0.1, 1e-6));
      expect(tint.a, 1.0);

      // Defaults are not recorded; only explicit assignments serialize.
      expect(serialized.keys.toSet(), overrides.keys.toSet());

      // Re-applying the serialized form reproduces the same block bytes.
      final replay = params();
      applyFmatParameterOverrides(replay, serialized);
      expect(
        replay.rawBlock.buffer.asUint8List(),
        p.rawBlock.buffer.asUint8List(),
      );
    });
  });
}
