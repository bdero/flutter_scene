// A save rebuilds the editor state from the live camera and selection, so it
// has to carry forward the keys the loaded state arrived with.
import 'package:flutter_scene_editor/src/io/scene_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

EditorCameraSpec _camera({
  double azimuth = 0,
  Map<String, Object?> unknown = const {},
}) => EditorCameraSpec(
  azimuth: azimuth,
  elevation: 0,
  radius: 1,
  target: Vector3.zero(),
  unknown: unknown,
);

void main() {
  test('a save keeps the editor state a newer engine wrote', () {
    final loaded = EditorStateSpec(
      camera: _camera(unknown: const {'dev.example.lens': 35}),
      unknown: const {'dev.example.layout': 'wide'},
    );
    final fresh = EditorStateSpec(camera: _camera(azimuth: 2));

    final merged = keepEditorStateUnknown(fresh, loaded);

    expect(merged.camera!.azimuth, 2, reason: 'the live pose still wins');
    expect(merged.camera!.unknown['dev.example.lens'], 35);
    expect(merged.unknown['dev.example.layout'], 'wide');
  });

  test('nothing to carry leaves the fresh state alone', () {
    final fresh = EditorStateSpec(camera: _camera(azimuth: 1));
    expect(keepEditorStateUnknown(fresh, null), same(fresh));

    final merged = keepEditorStateUnknown(fresh, EditorStateSpec());
    expect(merged.camera!.unknown, isEmpty);
    expect(merged.unknown, isEmpty);
  });

  test('a document written without a camera keeps its own keys', () {
    final merged = keepEditorStateUnknown(
      EditorStateSpec(),
      EditorStateSpec(unknown: const {'dev.example.layout': 'wide'}),
    );
    expect(merged.camera, isNull);
    expect(merged.unknown['dev.example.layout'], 'wide');
  });
}
