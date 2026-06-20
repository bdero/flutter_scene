// Covers the stage's skybox / sky-lighting serialization: the JSON round
// trip, the compose-time stage copy, the diff's stage comparison, and the
// fmat parameter-override application. All GPU-free; applying a stage to a
// live Scene (realizeStage / serializeStage) is GPU-bound and verified via
// the example app.

import 'dart:typed_data';

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/fscene/compose/compose.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/fscene/reload/diff.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

SceneDocument _skyDocument() {
  final doc = SceneDocument();
  doc.createNode(name: 'thing', root: true);
  doc.stage
    ..exposure = 1.5
    ..toneMapping = 'aces'
    ..skybox = SkyboxSpec(
      GradientSkySpec(zenithColor: Vector3(0.1, 0.2, 0.3), sunSharpness: 250.0),
      intensity: 2.0,
    )
    ..skyEnvironment = SkyEnvironmentSpec(
      FmatSkySpec(
        const AssetRef('assets/sky.fmat'),
        properties: {'sun_height': const DoubleValue(0.7)},
      ),
      refresh: 'interval',
      intervalSeconds: 2.5,
      faceResolution: 64,
      equirectWidth: 256,
    );
  return doc;
}

EnvironmentVolumeSpec _skyVolume() => EnvironmentVolumeSpec(
  name: 'lagoon',
  skyEnvironment: SkyEnvironmentSpec(GradientSkySpec(), castShadows: true),
  bounds: BoxBoundsSpec(center: Vector3(1, 0, 0)),
);

void main() {
  group('stage sky JSON', () {
    test('skybox and sky environment round-trip', () {
      final restored = readFscene(writeFscene(_skyDocument()));

      final skybox = restored.stage.skybox!;
      expect(skybox.intensity, 2.0);
      final gradient = skybox.source as GradientSkySpec;
      expect(gradient.zenithColor.x, closeTo(0.1, 1e-6));
      expect(gradient.zenithColor.z, closeTo(0.3, 1e-6));
      expect(gradient.sunSharpness, 250.0);

      final skyEnv = restored.stage.skyEnvironment!;
      expect(skyEnv.refresh, 'interval');
      expect(skyEnv.intervalSeconds, 2.5);
      expect(skyEnv.faceResolution, 64);
      expect(skyEnv.equirectWidth, 256);
      final fmat = skyEnv.source as FmatSkySpec;
      expect(fmat.asset.key, 'assets/sky.fmat');
      expect((fmat.properties['sun_height'] as DoubleValue).value, 0.7);
    });

    test('sky-driven shadow flag round-trips', () {
      final doc = SceneDocument();
      doc.stage.skyEnvironment = SkyEnvironmentSpec(
        GradientSkySpec(),
        castShadows: true,
      );
      var restored = readFscene(writeFscene(doc));
      expect(restored.stage.skyEnvironment!.castShadows, isTrue);

      // The default (off) stays off and is omitted from the JSON.
      doc.stage.skyEnvironment = SkyEnvironmentSpec(GradientSkySpec());
      expect(writeFscene(doc).contains('castShadows'), isFalse);
      restored = readFscene(writeFscene(doc));
      expect(restored.stage.skyEnvironment!.castShadows, isFalse);
    });

    test('environment and physical sky sources round-trip', () {
      final doc = SceneDocument();
      doc.stage.skybox = SkyboxSpec(EnvironmentSkySpec(blurriness: 0.4));
      var restored = readFscene(writeFscene(doc));
      final envSky = restored.stage.skybox!.source as EnvironmentSkySpec;
      expect(envSky.blurriness, 0.4);

      doc.stage.skybox = SkyboxSpec(
        PhysicalSkySpec(
          sunDirection: Vector3(0, 1, 0),
          turbidity: 4.0,
          energy: 1.5,
        ),
      );
      restored = readFscene(writeFscene(doc));
      final physical = restored.stage.skybox!.source as PhysicalSkySpec;
      expect(physical.sunDirection.y, 1.0);
      expect(physical.turbidity, 4.0);
      expect(physical.energy, 1.5);
    });

    test('a stage without a sky stays empty', () {
      final restored = readFscene(writeFscene(SceneDocument()));
      expect(restored.stage.skybox, isNull);
      expect(restored.stage.skyEnvironment, isNull);
    });
  });

  group('environment volumes JSON', () {
    EnvironmentVolumeSpec boxVolume() => EnvironmentVolumeSpec(
      name: 'cave',
      environment: const EmptyEnvironment(),
      exposure: 0.5,
      toneMapping: 'aces',
      radianceCubeSize: 1024,
      skybox: SkyboxSpec(PhysicalSkySpec(turbidity: 6.0)),
      bounds: BoxBoundsSpec(
        center: Vector3(1, 2, 3),
        halfExtents: Vector3(4, 5, 6),
      ),
      priority: 2.0,
      weight: 0.75,
      blendDistance: 1.5,
    );

    test('a box volume round-trips with its look and bounds', () {
      final doc = SceneDocument()..stage.volumes.add(boxVolume());
      final restored = readFscene(writeFscene(doc));

      expect(restored.stage.volumes, hasLength(1));
      final v = restored.stage.volumes.single;
      expect(v.name, 'cave');
      expect(v.environment, isA<EmptyEnvironment>());
      expect(v.exposure, 0.5);
      expect(v.toneMapping, 'aces');
      expect(v.radianceCubeSize, 1024);
      expect((v.skybox!.source as PhysicalSkySpec).turbidity, 6.0);
      expect(v.priority, 2.0);
      expect(v.weight, 0.75);
      expect(v.blendDistance, 1.5);
      final box = v.bounds as BoxBoundsSpec;
      expect(box.center, Vector3(1, 2, 3));
      expect(box.halfExtents, Vector3(4, 5, 6));
    });

    test('a sphere bound and a global volume round-trip', () {
      final doc = SceneDocument()
        ..stage.volumes.addAll([
          EnvironmentVolumeSpec(
            bounds: SphereBoundsSpec(center: Vector3(0, 1, 0), radius: 3.5),
          ),
          EnvironmentVolumeSpec(exposure: 2.0), // global (no bounds)
        ]);
      final restored = readFscene(writeFscene(doc));

      expect(restored.stage.volumes, hasLength(2));
      final sphere = restored.stage.volumes.first.bounds as SphereBoundsSpec;
      expect(sphere.center, Vector3(0, 1, 0));
      expect(sphere.radius, 3.5);
      expect(restored.stage.volumes[1].bounds, isNull);
      expect(restored.stage.volumes[1].exposure, 2.0);
    });

    test('no volumes stays empty and is omitted from the JSON', () {
      expect(writeFscene(SceneDocument()).contains('volumes'), isFalse);
      expect(readFscene(writeFscene(SceneDocument())).stage.volumes, isEmpty);
    });

    test('the base reflection size round-trips', () {
      final doc = SceneDocument()..stage.radianceCubeSize = 512;
      expect(readFscene(writeFscene(doc)).stage.radianceCubeSize, 512);
      // Null (the engine default) is omitted.
      expect(
        writeFscene(SceneDocument()).contains('radianceCubeSize'),
        isFalse,
      );
    });

    test('a volume change flags stageChanged', () {
      final base = SceneDocument()..stage.volumes.add(boxVolume());
      final next = SceneDocument()..stage.volumes.add(boxVolume());
      expect(diffScene(base, next).stageChanged, isFalse);
      next.stage.volumes.single.weight = 0.1;
      expect(diffScene(base, next).stageChanged, isTrue);
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

  test('compose deep-copies the stage volumes', () {
    final host = SceneDocument()..stage.volumes.add(_skyVolume());
    final prefab = SceneDocument()..createNode(name: 'p', root: true);
    host.createNode(name: 'inst', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );

    final composed = composeScene(host, resolve: (_) => prefab);
    final copied = composed.stage.volumes.single;
    expect(copied.name, 'lagoon');
    expect((copied.bounds as BoxBoundsSpec).center, Vector3(1, 0, 0));
    // Mutating the source does not leak into the composed copy.
    (host.stage.volumes.single.bounds as BoxBoundsSpec).center.setValues(
      9,
      9,
      9,
    );
    expect((copied.bounds as BoxBoundsSpec).center.x, isNot(9));
  });

  test('compose deep-copies the stage sky', () {
    final host = _skyDocument();
    // Give the host an instance so compose produces a new document.
    final prefab = SceneDocument();
    prefab.createNode(name: 'p', root: true);
    host.createNode(name: 'inst', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );

    final composed = composeScene(host, resolve: (_) => prefab);
    final copied = composed.stage.skybox!.source as GradientSkySpec;
    final original = host.stage.skybox!.source as GradientSkySpec;
    expect(copied.zenithColor, original.zenithColor);
    original.zenithColor.setValues(9, 9, 9);
    expect(copied.zenithColor.x, isNot(9));
    expect(composed.stage.skyEnvironment!.refresh, 'interval');
  });

  group('diffScene stage comparison', () {
    test('identical stages do not flag a change', () {
      expect(diffScene(_skyDocument(), _skyDocument()).stageChanged, isFalse);
    });

    test('a sky tweak flags stageChanged', () {
      final next = _skyDocument();
      (next.stage.skybox!.source as GradientSkySpec).sunSharpness = 100.0;
      final diff = diffScene(_skyDocument(), next);
      expect(diff.stageChanged, isTrue);
      expect(diff.isEmpty, isFalse);
      expect(diff.changed, isEmpty); // no node changes
    });

    test('an exposure tweak flags stageChanged', () {
      final next = _skyDocument();
      next.stage.exposure = 3.0;
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
