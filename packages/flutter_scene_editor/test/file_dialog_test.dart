import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_scene_editor/src/io/scene_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('open and save pickers forward their initial directory', () async {
    final original = FileSelectorPlatform.instance;
    final selector = _RecordingFileSelector();
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = original);

    expect(
      await pickOpenPath(initialDirectory: '/project/scenes'),
      '/project/scenes/opened.fscene',
    );
    expect(selector.openInitialDirectory, '/project/scenes');

    expect(
      await pickSavePath(
        initialDirectory: '/project/scenes',
        suggestedName: 'level.fscene',
      ),
      '/project/scenes/saved.fscene',
    );
    expect(selector.saveInitialDirectory, '/project/scenes');
    expect(selector.suggestedName, 'level');
  });

  test('prefab directory changes only when a prefab is remembered', () {
    final history = FileDialogHistory();

    expect(
      history.prefabInitialDirectory('/project/scenes'),
      '/project/scenes',
    );
    expect(history.prefabInitialDirectory('/other/scene'), '/other/scene');

    history.rememberPrefab('/shared/prefabs/chair.fscene');
    expect(history.prefabInitialDirectory('/other/scene'), '/shared/prefabs');
  });

  test('environment image picker includes HDR and EXR', () async {
    final original = FileSelectorPlatform.instance;
    final selector = _RecordingFileSelector();
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = original);

    await pickEnvironmentPath(initialDirectory: '/project/environments');

    expect(selector.openExtensions, containsAll(['hdr', 'exr']));
  });
}

class _RecordingFileSelector extends FileSelectorPlatform {
  String? openInitialDirectory;
  List<String> openExtensions = const [];
  String? saveInitialDirectory;
  String? suggestedName;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openInitialDirectory = initialDirectory;
    openExtensions = [
      for (final group in acceptedTypeGroups ?? const <XTypeGroup>[])
        ...?group.extensions,
    ];
    return XFile('$initialDirectory/opened.fscene');
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    saveInitialDirectory = options.initialDirectory;
    suggestedName = options.suggestedName;
    return FileSaveLocation('$saveInitialDirectory/saved');
  }
}
