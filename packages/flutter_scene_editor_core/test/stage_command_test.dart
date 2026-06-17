import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

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
}
