import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('setStageProperties updates only given keys and reverts', () {
    final session = EditorSession.empty();
    StageMetadata stage() => session.document.stage;
    expect(stage().exposure, 1.0);
    expect(stage().toneMapping, 'pbrNeutral');
    expect(stage().environment, isA<StudioEnvironment>());

    session.run('setStageProperties', {
      'properties': {
        'exposure': 2.5,
        'toneMapping': 'aces',
        'environmentIntensity': 0.5,
        'environment': 'empty',
      },
    });
    expect(stage().exposure, 2.5);
    expect(stage().toneMapping, 'aces');
    expect(stage().environmentIntensity, 0.5);
    expect(stage().environment, isA<EmptyEnvironment>());
    // Untouched keys keep their defaults.
    expect(stage().renderScale, 1.0);

    session.undo();
    expect(stage().exposure, 1.0);
    expect(stage().toneMapping, 'pbrNeutral');
    expect(stage().environment, isA<StudioEnvironment>());
  });

  test('setSkybox sets a procedural sky + sky lighting and reverts', () {
    final session = EditorSession.empty();
    StageMetadata stage() => session.document.stage;
    expect(stage().skybox, isNull);

    session.run('setSkybox', {
      'sky': 'gradient',
      'sunDirection': {'x': 0.2, 'y': 0.8, 'z': 0.1},
      'lightScene': true,
    });
    expect(stage().skybox?.source, isA<GradientSkySpec>());
    expect(stage().skyEnvironment, isNotNull);

    // Turning lighting off keeps the skybox but drops the sky environment.
    session.run('setSkybox', {'sky': 'gradient', 'lightScene': false});
    expect(stage().skybox?.source, isA<GradientSkySpec>());
    expect(stage().skyEnvironment, isNull);

    session.undo();
    session.undo();
    expect(stage().skybox, isNull);
    expect(stage().skyEnvironment, isNull);
  });

  test('setSkybox keeps tuned parameters across a lighting toggle', () {
    final session = EditorSession.empty();
    StageMetadata stage() => session.document.stage;

    session.run('setSkybox', {'sky': 'physical', 'lightScene': true});
    session.run('setSkyParameters', {
      'properties': {'turbidity': 4.0, 'energy': 2.0},
    });
    expect((stage().skybox!.source as PhysicalSkySpec).turbidity, 4.0);

    // Toggling lighting off (no sky param given) must not reset the sky.
    session.run('setSkybox', {'sky': 'physical', 'lightScene': false});
    final sky = stage().skybox!.source as PhysicalSkySpec;
    expect(sky.turbidity, 4.0);
    expect(sky.energy, 2.0);
    expect(stage().skyEnvironment, isNull);
  });

  test('setSkyParameters tunes both the skybox and sky lighting, reverts', () {
    final session = EditorSession.empty();
    StageMetadata stage() => session.document.stage;

    session.run('setSkybox', {'sky': 'gradient', 'lightScene': true});
    final before = (stage().skybox!.source as GradientSkySpec).sunSharpness;

    session.run('setSkyParameters', {
      'properties': {
        'sunSharpness': 900.0,
        'sunColor': {'x': 4.0, 'y': 3.0, 'z': 2.0},
      },
    });
    final skybox = stage().skybox!.source as GradientSkySpec;
    final lighting = stage().skyEnvironment!.source as GradientSkySpec;
    expect(skybox.sunSharpness, 900.0);
    expect(skybox.sunColor.x, 4.0);
    // The lighting source mirrors the same parameters.
    expect(lighting.sunSharpness, 900.0);
    expect(lighting.sunColor.z, 2.0);

    session.undo();
    expect((stage().skybox!.source as GradientSkySpec).sunSharpness, before);
  });

  test('setSkyParameters without a skybox throws', () {
    final session = EditorSession.empty();
    expect(
      () => session.run('setSkyParameters', {
        'properties': {'energy': 2.0},
      }),
      throwsA(isA<CommandException>()),
    );
  });

  test('setSkybox toggles sky-driven shadows and they survive tuning', () {
    final session = EditorSession.empty();
    StageMetadata stage() => session.document.stage;

    session.run('setSkybox', {
      'sky': 'physical',
      'lightScene': true,
      'castShadows': true,
    });
    expect(stage().skyEnvironment!.castShadows, isTrue);

    // Tuning a parameter keeps shadows on.
    session.run('setSkyParameters', {
      'properties': {'energy': 2.0},
    });
    expect(stage().skyEnvironment!.castShadows, isTrue);

    // Turning shadows off keeps the sky lighting.
    session.run('setSkybox', {'sky': 'physical', 'castShadows': false});
    expect(stage().skyEnvironment, isNotNull);
    expect(stage().skyEnvironment!.castShadows, isFalse);

    // Shadows require sky lighting; dropping it drops the binding entirely.
    session.run('setSkybox', {
      'sky': 'physical',
      'lightScene': false,
      'castShadows': true,
    });
    expect(stage().skyEnvironment, isNull);
  });

  test('setSkybox carries the sun direction across a type switch', () {
    final session = EditorSession.empty();
    StageMetadata stage() => session.document.stage;

    session.run('setSkybox', {
      'sky': 'gradient',
      'sunDirection': {'x': 0.1, 'y': 0.9, 'z': 0.2},
    });
    session.run('setSkybox', {'sky': 'physical'});
    final sky = stage().skybox!.source as PhysicalSkySpec;
    expect(sky.sunDirection.x, closeTo(0.1, 1e-6));
    expect(sky.sunDirection.y, closeTo(0.9, 1e-6));
    expect(sky.sunDirection.z, closeTo(0.2, 1e-6));
  });

  group('environment volumes', () {
    test('addEnvironmentVolume appends a default box volume and reverts', () {
      final session = EditorSession.empty();
      List<EnvironmentVolumeSpec> volumes() => session.document.stage.volumes;
      expect(volumes(), isEmpty);

      session.run('addEnvironmentVolume', {});
      expect(volumes(), hasLength(1));
      final v = volumes().single;
      expect(v.name, 'Volume 1');
      expect(v.bounds, isA<BoxBoundsSpec>());
      expect(v.blendDistance, 1.0);

      session.undo();
      expect(volumes(), isEmpty);
    });

    test('a new volume takes the next-highest priority', () {
      final session = EditorSession.empty();
      session.run('addEnvironmentVolume', {});
      session.run('setVolumeProperties', {
        'index': 0,
        'properties': {'priority': 5.0},
      });
      session.run('addEnvironmentVolume', {'bounds': 'sphere'});
      final volumes = session.document.stage.volumes;
      expect(volumes[1].bounds, isA<SphereBoundsSpec>());
      expect(volumes[1].priority, 6.0);
    });

    test('removeEnvironmentVolume removes by index and reverts', () {
      final session = EditorSession.empty();
      session.run('addEnvironmentVolume', {'name': 'a'});
      session.run('addEnvironmentVolume', {'name': 'b'});
      session.run('removeEnvironmentVolume', {'index': 0});
      expect(session.document.stage.volumes.single.name, 'b');
      session.undo();
      expect(session.document.stage.volumes.map((v) => v.name), ['a', 'b']);
    });

    test('setVolumeProperties edits region and blend, switching shape', () {
      final session = EditorSession.empty();
      session.run('addEnvironmentVolume', {});
      session.run('setVolumeProperties', {
        'index': 0,
        'properties': {
          'name': 'cave',
          'weight': 0.5,
          'blendDistance': 2.0,
          'center': {'x': 1.0, 'y': 2.0, 'z': 3.0},
          'halfExtents': {'x': 4.0, 'y': 4.0, 'z': 4.0},
        },
      });
      var v = session.document.stage.volumes.single;
      expect(v.name, 'cave');
      expect(v.weight, 0.5);
      expect(v.blendDistance, 2.0);
      expect((v.bounds as BoxBoundsSpec).center, Vector3(1, 2, 3));

      // Switching to a sphere carries the center.
      session.run('setVolumeProperties', {
        'index': 0,
        'properties': {'boundsType': 'sphere', 'radius': 7.0},
      });
      v = session.document.stage.volumes.single;
      final sphere = v.bounds as SphereBoundsSpec;
      expect(sphere.center, Vector3(1, 2, 3));
      expect(sphere.radius, 7.0);
    });

    test('look commands target a volume by index, not the base', () {
      final session = EditorSession.empty();
      StageMetadata stage() => session.document.stage;
      session.run('addEnvironmentVolume', {});

      session.run('setStageProperties', {
        'volume': 0,
        'properties': {'exposure': 4.0, 'environment': 'empty'},
      });
      // The volume changed; the base is untouched.
      expect(stage().volumes.single.exposure, 4.0);
      expect(stage().volumes.single.environment, isA<EmptyEnvironment>());
      expect(stage().exposure, 1.0);
      expect(stage().environment, isA<StudioEnvironment>());

      session.run('setSkybox', {
        'volume': 0,
        'sky': 'physical',
        'lightScene': true,
      });
      expect(stage().volumes.single.skybox?.source, isA<PhysicalSkySpec>());
      expect(stage().volumes.single.skyEnvironment, isNotNull);
      expect(stage().skybox, isNull);

      session.run('setSkyParameters', {
        'volume': 0,
        'properties': {'turbidity': 3.0},
      });
      expect(
        (stage().volumes.single.skybox!.source as PhysicalSkySpec).turbidity,
        3.0,
      );
    });

    test('reflection size sets and clears on the base and a volume', () {
      final session = EditorSession.empty();
      StageMetadata stage() => session.document.stage;
      session.run('addEnvironmentVolume', {});

      session.run('setStageProperties', {
        'properties': {'radianceCubeSize': 1024},
      });
      session.run('setStageProperties', {
        'volume': 0,
        'properties': {'radianceCubeSize': 256},
      });
      expect(stage().radianceCubeSize, 1024);
      expect(stage().volumes.single.radianceCubeSize, 256);

      // A non-positive value clears back to the engine default (null).
      session.run('setStageProperties', {
        'properties': {'radianceCubeSize': 0},
      });
      expect(stage().radianceCubeSize, isNull);
    });

    test('an out-of-range volume index throws', () {
      final session = EditorSession.empty();
      expect(
        () => session.run('removeEnvironmentVolume', {'index': 0}),
        throwsA(isA<CommandException>()),
      );
      expect(
        () => session.run('setStageProperties', {
          'volume': 3,
          'properties': {'exposure': 2.0},
        }),
        throwsA(isA<CommandException>()),
      );
    });
  });

  group('environment resources', () {
    EnvironmentResource only(EditorSession s) =>
        s.document.resources.values.whereType<EnvironmentResource>().single;

    test('create then edit the look, skybox, and sky parameters', () {
      final session = EditorSession.empty();
      session.run('createEnvironmentResource', {'name': 'cave'});
      final id = only(session).id;
      expect(only(session).name, 'cave');

      session.run('setEnvironmentProperties', {
        'environmentId': id.toToken(),
        'properties': {'exposure': 0.3, 'environment': 'empty'},
      });
      expect(only(session).exposure, 0.3);
      expect(only(session).environment, isA<EmptyEnvironment>());

      session.run('setEnvironmentSkybox', {
        'environmentId': id.toToken(),
        'sky': 'physical',
        'lightScene': true,
      });
      expect(only(session).skybox?.source, isA<PhysicalSkySpec>());
      expect(only(session).skyEnvironment, isNotNull);

      session.run('setEnvironmentSkyParameters', {
        'environmentId': id.toToken(),
        'properties': {'turbidity': 4.0},
      });
      expect((only(session).skybox!.source as PhysicalSkySpec).turbidity, 4.0);

      session.undo();
      expect(
        (only(session).skybox!.source as PhysicalSkySpec).turbidity,
        isNot(4.0),
      );
    });

    test('editing a non-environment resource throws', () {
      final session = EditorSession.empty();
      session.run('createMaterial', {'type': 'physicallyBased'});
      final material = session.document.resources.values
          .whereType<MaterialResource>()
          .single;
      expect(
        () => session.run('setEnvironmentProperties', {
          'environmentId': material.id.toToken(),
          'properties': {'exposure': 1.0},
        }),
        throwsA(isA<CommandException>()),
      );
    });
  });
}
