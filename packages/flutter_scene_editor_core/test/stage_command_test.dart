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
}
