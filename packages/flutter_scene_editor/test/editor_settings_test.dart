import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const layoutA = '{"type":"tabs","panels":["viewport"]}';
  const layoutB = '{"type":"tabs","panels":["inspector"]}';

  test('settings round trip layouts and recent scenes', () {
    final settings = EditorSettings(dockLayout: layoutA);
    settings.saveNamedLayout('Modeling', layoutB);
    settings.rememberScene('/tmp/a.fscene');

    final decoded = EditorSettings.fromJsonString(settings.toJsonString());

    expect(decoded.dockLayout, layoutA);
    expect(decoded.namedLayouts, {'Modeling': layoutB});
    expect(decoded.recentScenes, ['/tmp/a.fscene']);
  });

  test('recent scenes deduplicate and retain the newest ten', () {
    final settings = EditorSettings();
    for (var index = 0; index < 12; index++) {
      settings.rememberScene('/tmp/$index.fscene');
    }
    settings.rememberScene('/tmp/5.fscene');

    expect(settings.recentScenes, hasLength(10));
    expect(settings.recentScenes.first, '/tmp/5.fscene');
    expect(settings.recentScenes.toSet(), hasLength(10));
    expect(settings.recentScenes, isNot(contains('/tmp/0.fscene')));
  });

  test('named layout matching ignores case when overwriting', () {
    final settings = EditorSettings();
    settings.saveNamedLayout('Animation', layoutA);
    settings.saveNamedLayout('animation', layoutB);

    expect(settings.namedLayouts, {'animation': layoutB});
    settings.deleteNamedLayout('animation');
    expect(settings.namedLayouts, isEmpty);
  });

  test('store migrates the legacy dock layout', () {
    final directory = Directory.systemTemp.createTempSync('editor_settings_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final legacy = File('${directory.path}/dock_layout.json')
      ..writeAsStringSync(layoutA);
    final store = EditorSettingsStore(
      file: File('${directory.path}/settings.json'),
      legacyDockLayoutFile: legacy,
    );

    final settings = store.load();

    expect(settings.dockLayout, layoutA);
    store.save(settings);
    expect(store.load().dockLayout, layoutA);
  });

  test('store atomically replaces existing settings', () {
    final directory = Directory.systemTemp.createTempSync('editor_settings_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = EditorSettingsStore(
      file: File('${directory.path}/settings.json'),
    );
    store.save(EditorSettings(dockLayout: layoutA));
    store.save(EditorSettings(dockLayout: layoutB));

    expect(store.load().dockLayout, layoutB);
    expect(File('${directory.path}/settings.json.tmp').existsSync(), isFalse);
  });

  test('clear and restore recent scenes preserves order', () {
    final settings = EditorSettings(
      recentScenes: ['/tmp/new.fscene', '/tmp/old.fscene'],
    );
    final removed = List.of(settings.recentScenes);
    settings.recentScenes.clear();
    settings.restoreRecentScenes(removed);

    expect(settings.recentScenes, removed);
  });

  test('editor command defaults, round trips, and omits the default', () {
    final settings = EditorSettings();
    expect(settings.editorCommand, EditorSettings.defaultEditorCommand);
    expect(settings.toJsonString(), isNot(contains('editorCommand')));

    settings.editorCommand = r'subl ${SOURCE_FILE}';
    final reloaded = EditorSettings.fromJsonString(settings.toJsonString());
    expect(reloaded.editorCommand, r'subl ${SOURCE_FILE}');
  });

  test('gizmo visibility round trips and omits the defaults', () {
    final settings = EditorSettings();
    expect(settings.gizmosEnabled, isTrue);
    expect(settings.toJsonString(), isNot(contains('gizmos')));

    settings.gizmosEnabled = false;
    settings.hiddenGizmoTypes.add('collider');
    final reloaded = EditorSettings.fromJsonString(settings.toJsonString());
    expect(reloaded.gizmosEnabled, isFalse);
    expect(reloaded.hiddenGizmoTypes, {'collider'});
  });

  test('GI probe visibility round trips and stays off by default', () {
    final settings = EditorSettings();
    expect(settings.giProbesVisible, isFalse);
    expect(settings.toJsonString(), isNot(contains('giProbes')));

    settings.giProbesVisible = true;
    final reloaded = EditorSettings.fromJsonString(settings.toJsonString());
    expect(reloaded.giProbesVisible, isTrue);
  });

  test('restart-on-scene-save round trips per project and forgets', () {
    final settings = EditorSettings(
      restartOnSceneSave: {'/p/a.fproject': true},
      selectedDevices: {'/p/a.fproject': 'macos'},
    );
    final reloaded = EditorSettings.fromJsonString(settings.toJsonString());
    expect(reloaded.restartOnSceneSave['/p/a.fproject'], isTrue);
    expect(reloaded.selectedDevices['/p/a.fproject'], 'macos');

    reloaded.forgetProject('/p/a.fproject');
    expect(reloaded.restartOnSceneSave, isEmpty);
  });
}
