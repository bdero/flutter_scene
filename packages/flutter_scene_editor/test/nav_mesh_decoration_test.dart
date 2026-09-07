// Editor-only scene decorations: nodes drawn in the scene but absent from the
// document, which is how a baked nav mesh gets on screen. The load-bearing
// property is that a re-realize -- which rebuilds the scene from the document
// -- puts them back rather than dropping them.

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

/// A document with one empty root, enough to realize.
SceneDocument levelDocument() {
  final document = SceneDocument();
  document.addNode(NodeSpec(id: document.newId(), name: 'Level'), root: true);
  return document;
}

void main() {
  if (!_gpuAvailable()) {
    test('scene decorations', () {}, skip: 'Requires a GPU device.');
    return;
  }

  Future<EditorController> open() async {
    await Scene.initializeStaticResources();
    final controller = await EditorController.open(
      EditorSession(levelDocument()),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('a decoration is drawn but is not part of the document', () async {
    final controller = await open();
    final overlay = Node(name: 'Nav mesh');
    controller.setSceneDecoration('navMesh', overlay);

    expect(controller.sceneDecoration('navMesh'), same(overlay));
    expect(controller.scene.root.children, contains(overlay));
    expect(
      controller.document.nodes.values.map((n) => n.name),
      isNot(contains('Nav mesh')),
    );
  });

  test('setting the same key again replaces what was there', () async {
    final controller = await open();
    final first = Node(name: 'first');
    final second = Node(name: 'second');
    controller.setSceneDecoration('navMesh', first);
    controller.setSceneDecoration('navMesh', second);

    expect(controller.scene.root.children, isNot(contains(first)));
    expect(controller.scene.root.children, contains(second));
  });

  test('null removes it', () async {
    final controller = await open();
    final overlay = Node(name: 'Nav mesh');
    controller.setSceneDecoration('navMesh', overlay);
    controller.setSceneDecoration('navMesh', null);

    expect(controller.sceneDecoration('navMesh'), isNull);
    expect(controller.scene.root.children, isNot(contains(overlay)));
  });

  test('two keys coexist', () async {
    final controller = await open();
    final nav = Node(name: 'nav');
    final physics = Node(name: 'physics');
    controller
      ..setSceneDecoration('navMesh', nav)
      ..setSceneDecoration('physics', physics);

    expect(controller.scene.root.children, contains(nav));
    expect(controller.scene.root.children, contains(physics));
  });

  test('a re-realize puts the decoration back', () async {
    final controller = await open();
    final overlay = Node(name: 'Nav mesh');
    controller.setSceneDecoration('navMesh', overlay);

    // Any structural edit rebuilds the scene from the document, which clears
    // it before adding the realized root.
    await controller.recompose();

    expect(
      controller.scene.root.children,
      contains(overlay),
      reason: 'a decoration has to survive the scene being rebuilt under it',
    );
    expect(controller.sceneDecoration('navMesh'), same(overlay));
  });
}
