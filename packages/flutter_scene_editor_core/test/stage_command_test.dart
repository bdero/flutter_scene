import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

// The stage's global look lives in an environment resource the stage references;
// the stage-look commands (setSkybox/setSkyParameters) create and link one on
// first use.
EnvironmentResource _stageEnv(EditorSession s) =>
    s.document.resources[s.document.stage.environmentRef!]!
        as EnvironmentResource;

void main() {
  test('setStageProperties updates only given render keys and reverts', () {
    final session = EditorSession.empty();
    StageMetadata stage() => session.document.stage;
    expect(stage().renderScale, 1.0);
    expect(stage().antiAliasingMode, 'auto');

    session.run('setStageProperties', {
      'properties': {'renderScale': 0.5, 'antiAliasingMode': 'fxaa'},
    });
    expect(stage().renderScale, 0.5);
    expect(stage().antiAliasingMode, 'fxaa');
    // Untouched keys keep their defaults.
    expect(stage().filterQuality, 'medium');

    session.undo();
    expect(stage().renderScale, 1.0);
    expect(stage().antiAliasingMode, 'auto');
  });

  test('setSkybox sets a procedural sky + sky lighting and reverts', () {
    final session = EditorSession.empty();
    expect(session.document.stage.environmentRef, isNull);

    session.run('setSkybox', {
      'sky': 'gradient',
      'sunDirection': {'x': 0.2, 'y': 0.8, 'z': 0.1},
      'lightScene': true,
    });
    expect(_stageEnv(session).skybox?.source, isA<GradientSkySpec>());
    expect(_stageEnv(session).skyEnvironment, isNotNull);

    // Turning lighting off keeps the skybox but drops the sky environment.
    session.run('setSkybox', {'sky': 'gradient', 'lightScene': false});
    expect(_stageEnv(session).skybox?.source, isA<GradientSkySpec>());
    expect(_stageEnv(session).skyEnvironment, isNull);

    // Undoing both edits reverts the create, so the stage has no resource again.
    session.undo();
    session.undo();
    expect(session.document.stage.environmentRef, isNull);
    expect(
      session.document.resources.values.whereType<EnvironmentResource>(),
      isEmpty,
    );
  });

  test('setSkybox keeps tuned parameters across a lighting toggle', () {
    final session = EditorSession.empty();

    session.run('setSkybox', {'sky': 'physical', 'lightScene': true});
    session.run('setSkyParameters', {
      'properties': {'turbidity': 4.0, 'energy': 2.0},
    });
    expect(
      (_stageEnv(session).skybox!.source as PhysicalSkySpec).turbidity,
      4.0,
    );

    // Toggling lighting off (no sky param given) must not reset the sky.
    session.run('setSkybox', {'sky': 'physical', 'lightScene': false});
    final sky = _stageEnv(session).skybox!.source as PhysicalSkySpec;
    expect(sky.turbidity, 4.0);
    expect(sky.energy, 2.0);
    expect(_stageEnv(session).skyEnvironment, isNull);
  });

  test('setSkyParameters tunes both the skybox and sky lighting, reverts', () {
    final session = EditorSession.empty();

    session.run('setSkybox', {'sky': 'gradient', 'lightScene': true});
    final before =
        (_stageEnv(session).skybox!.source as GradientSkySpec).sunSharpness;

    session.run('setSkyParameters', {
      'properties': {
        'sunSharpness': 900.0,
        'sunColor': {'x': 4.0, 'y': 3.0, 'z': 2.0},
      },
    });
    final skybox = _stageEnv(session).skybox!.source as GradientSkySpec;
    final lighting =
        _stageEnv(session).skyEnvironment!.source as GradientSkySpec;
    expect(skybox.sunSharpness, 900.0);
    expect(skybox.sunColor.x, 4.0);
    // The lighting source mirrors the same parameters.
    expect(lighting.sunSharpness, 900.0);
    expect(lighting.sunColor.z, 2.0);

    session.undo();
    expect(
      (_stageEnv(session).skybox!.source as GradientSkySpec).sunSharpness,
      before,
    );
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

    session.run('setSkybox', {
      'sky': 'physical',
      'lightScene': true,
      'castShadows': true,
    });
    expect(_stageEnv(session).skyEnvironment!.sunLight!.castsShadow, isTrue);

    // Tuning a parameter keeps shadows on.
    session.run('setSkyParameters', {
      'properties': {'energy': 2.0},
    });
    expect(_stageEnv(session).skyEnvironment!.sunLight!.castsShadow, isTrue);

    // Turning shadows off keeps the sky lighting.
    session.run('setSkybox', {'sky': 'physical', 'castShadows': false});
    expect(_stageEnv(session).skyEnvironment, isNotNull);
    expect(_stageEnv(session).skyEnvironment!.sunLight, isNull);

    // Shadows require sky lighting; dropping it drops the binding entirely.
    session.run('setSkybox', {
      'sky': 'physical',
      'lightScene': false,
      'castShadows': true,
    });
    expect(_stageEnv(session).skyEnvironment, isNull);
  });

  test('setSkybox carries the sun direction across a type switch', () {
    final session = EditorSession.empty();

    session.run('setSkybox', {
      'sky': 'gradient',
      'sunDirection': {'x': 0.1, 'y': 0.9, 'z': 0.2},
    });
    session.run('setSkybox', {'sky': 'physical'});
    final sky = _stageEnv(session).skybox!.source as PhysicalSkySpec;
    expect(sky.sunDirection.x, closeTo(0.1, 1e-6));
    expect(sky.sunDirection.y, closeTo(0.9, 1e-6));
    expect(sky.sunDirection.z, closeTo(0.2, 1e-6));
  });

  test('setEnvironmentProperties sets and clears the reflection size', () {
    final session = EditorSession.empty();
    session.run('createEnvironmentResource', {});
    final id = session.document.resources.values
        .whereType<EnvironmentResource>()
        .single
        .id;
    EnvironmentResource env() =>
        session.document.resource(id)! as EnvironmentResource;

    session.run('setEnvironmentProperties', {
      'environmentId': id.toToken(),
      'properties': {'radianceCubeSize': 1024},
    });
    expect(env().radianceCubeSize, 1024);

    // A non-positive value clears back to the engine default (null).
    session.run('setEnvironmentProperties', {
      'environmentId': id.toToken(),
      'properties': {'radianceCubeSize': 0},
    });
    expect(env().radianceCubeSize, isNull);
  });

  test('setEnvironmentProperties edits the complete rendering look', () {
    final session = EditorSession.empty();
    session.run('createEnvironmentResource', {});
    final id = session.document.resources.values
        .whereType<EnvironmentResource>()
        .single
        .id;

    session.run('setEnvironmentProperties', {
      'environmentId': id.toToken(),
      'properties': {
        'environmentRotationY': 0.75,
        'agxWhite': 24.0,
        'bloomEnabled': true,
        'bloomIntensity': 1.4,
        'ambientOcclusionSampleCount': 32,
        'ambientOcclusionIndirectLight': 2.0,
        'screenSpaceReflectionsEnabled': true,
        'fogColor': {'x': 0.1, 'y': 0.2, 'z': 0.3},
        'godRaysStepCount': 48,
        'depthOfFieldQuality': 'high',
        'autoExposureCompensation': 1.5,
      },
    });

    final environment = session.document.resource(id)! as EnvironmentResource;
    expect(environment.environmentRotationY, 0.75);
    expect(environment.agxWhite, 24.0);
    expect(environment.effects.bloomEnabled, isTrue);
    expect(environment.effects.bloomIntensity, 1.4);
    expect(environment.effects.ambientOcclusionSampleCount, 32);
    expect(environment.effects.ambientOcclusionIndirectLight, 2.0);
    expect(environment.effects.screenSpaceReflectionsEnabled, isTrue);
    expect(environment.effects.fogColor, Vector3(0.1, 0.2, 0.3));
    expect(environment.effects.godRaysStepCount, 48);
    expect(environment.effects.depthOfFieldQuality, 'high');
    expect(environment.effects.autoExposureCompensation, 1.5);

    session.undo();
    final restored = session.document.resource(id)! as EnvironmentResource;
    expect(restored.environmentRotationY, 0.0);
    expect(restored.effects.bloomEnabled, isFalse);
    expect(restored.effects.fogColor, Vector3(0.6, 0.7, 0.8));
  });

  test('setEnvironmentProperties edits global illumination and TAA', () {
    // Both were realized (GI) or authorable (TAA) but reachable from no
    // command, so the engine could light a scene by bounce and the editor had
    // no way to turn it on.
    final session = EditorSession.empty();
    session.run('createEnvironmentResource', {});
    final id = session.document.resources.values
        .whereType<EnvironmentResource>()
        .single
        .id;

    session.run('setEnvironmentProperties', {
      'environmentId': id.toToken(),
      'properties': {
        'globalIlluminationEnabled': true,
        'globalIlluminationVolumeMode': 'fitScene',
        'globalIlluminationExtents': {'x': 30.0, 'y': 12.0, 'z': 30.0},
        'globalIlluminationIntensity': 1.5,
        'globalIlluminationProbeUpdateBudget': 256,
        'globalIlluminationInjectionResolution': 'quarter',
        'globalIlluminationBakeOnly': true,
        'temporalAntiAliasingSharpness': 0.4,
        'temporalAntiAliasingJitterSequenceLength': 16,
        'temporalAntiAliasingObjectMotion': true,
      },
    });

    final e = (session.document.resource(id)! as EnvironmentResource).effects;
    expect(e.globalIlluminationEnabled, isTrue);
    expect(e.globalIlluminationVolumeMode, 'fitScene');
    expect(e.globalIlluminationExtents, Vector3(30, 12, 30));
    expect(e.globalIlluminationIntensity, 1.5);
    expect(e.globalIlluminationProbeUpdateBudget, 256);
    expect(e.globalIlluminationInjectionResolution, 'quarter');
    expect(e.globalIlluminationBakeOnly, isTrue);
    expect(e.temporalAntiAliasingSharpness, 0.4);
    expect(e.temporalAntiAliasingJitterSequenceLength, 16);
    expect(e.temporalAntiAliasingObjectMotion, isTrue);

    session.undo();
    final back =
        (session.document.resource(id)! as EnvironmentResource).effects;
    expect(back.globalIlluminationEnabled, isFalse);
    expect(back.temporalAntiAliasingSharpness, 0.15);
  });

  test('the anti-aliasing mode accepts every mode the engine has', () {
    // The editor's dropdown offered four of the six; smaa and taa were only
    // reachable from code or a hand-edited document.
    final session = EditorSession.empty();
    for (final mode in ['none', 'msaa', 'fxaa', 'smaa', 'taa', 'auto']) {
      session.run('setStageProperties', {
        'properties': {'antiAliasingMode': mode},
      });
      expect(session.document.stage.antiAliasingMode, mode);
    }
  });

  test('setEnvironmentImage assigns and removes the image atomically', () {
    final session = EditorSession.empty();
    session.run('createEnvironmentResource', {'name': 'courtyard'});
    final id = session.document.resources.values
        .whereType<EnvironmentResource>()
        .single
        .id;
    EnvironmentResource env() =>
        session.document.resource(id)! as EnvironmentResource;

    session.run('setEnvironmentImage', {
      'environmentId': id.toToken(),
      'asset': 'environments/courtyard.exr',
      'showAsBackground': true,
    });
    expect(
      (env().environment as AssetEnvironment).asset.key,
      'environments/courtyard.exr',
    );
    expect(env().skybox?.source, isA<EnvironmentSkySpec>());

    session.run('setEnvironmentImage', {
      'environmentId': id.toToken(),
      'asset': '',
    });
    expect(env().environment, isA<EmptyEnvironment>());
    expect(env().skybox, isNull);

    session.undo();
    expect(
      (env().environment as AssetEnvironment).asset.key,
      'environments/courtyard.exr',
    );
    expect(env().skybox?.source, isA<EnvironmentSkySpec>());
  });

  test('setEnvironmentProperties represents constant lighting', () {
    final session = EditorSession.empty();
    session.run('createEnvironmentResource', {});
    final id = session.document.resources.values
        .whereType<EnvironmentResource>()
        .single
        .id;

    session.run('setEnvironmentProperties', {
      'environmentId': id.toToken(),
      'properties': {
        'environment': 'constant',
        'environmentColor': {'x': 0.2, 'y': 0.3, 'z': 0.4},
      },
    });
    final environment = session.document.resource(id)! as EnvironmentResource;
    expect(
      (environment.environment as ConstantEnvironment).color,
      Vector3(0.2, 0.3, 0.4),
    );
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

    test('edits sky sun shadow settings as one undoable change', () {
      final session = EditorSession.empty();
      session.run('createEnvironmentResource', {'name': 'day'});
      final id = only(session).id;
      session.run('setEnvironmentSkybox', {
        'environmentId': id.toToken(),
        'sky': 'physical',
        'lightScene': true,
        'castShadows': true,
      });

      session.run('setEnvironmentSunLightProperties', {
        'environmentId': id.toToken(),
        'properties': {
          'priority': 4,
          'shadowMaxDistance': 350.0,
          'shadowCascadeCount': 3,
          'shadowFilter': 'fixedPcf',
          'shadowCasterFaces': 'both',
        },
      });
      final sun = only(session).skyEnvironment!.sunLight!;
      expect(sun.priority, 4);
      expect(sun.shadowMaxDistance, 350);
      expect(sun.shadowCascadeCount, 3);
      expect(sun.shadowFilter, 'fixedPcf');
      expect(sun.shadowCasterFaces, 'both');

      session.undo();
      expect(only(session).skyEnvironment!.sunLight!.priority, 0);
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
