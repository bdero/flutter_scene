// What the inspector shows the moment a scene opens. The inspector inspects
// the selection, so opening with nothing selected meant opening on the one
// screen in the editor that answers no question anybody asked.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  if (!_gpuAvailable()) {
    test('opening selection', () {}, skip: 'Requires a GPU device.');
    return;
  }

  test('opening a scene selects its first node', () async {
    await Scene.initializeStaticResources();
    final document = SceneDocument();
    final first = document.newId();
    final second = document.newId();
    document.addNode(NodeSpec(id: first, name: 'Sun'), root: true);
    document.addNode(NodeSpec(id: second, name: 'Camera'), root: true);

    final controller = await EditorController.open(EditorSession(document));
    addTearDown(controller.dispose);
    expect(controller.selection.primary, first);
  });

  test('a scene with no nodes opens with nothing selected', () async {
    await Scene.initializeStaticResources();
    final controller = await EditorController.open(
      EditorSession(SceneDocument()),
    );
    addTearDown(controller.dispose);
    expect(controller.selection.isEmpty, isTrue);
  });

  test('a template scene opens on the node it starts with', () async {
    await Scene.initializeStaticResources();
    final controller = await EditorController.empty();
    addTearDown(controller.dispose);
    expect(controller.selection.primary, isNotNull);
  });
}
