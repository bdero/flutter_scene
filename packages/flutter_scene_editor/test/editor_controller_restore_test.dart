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
  // Scene.initializeStaticResources reaches rootBundle, which needs a binding.
  // Without this the whole file fails before it reaches an assertion.
  TestWidgetsFlutterBinding.ensureInitialized();

  if (!_gpuAvailable()) {
    test('restored-node reflection', () {}, skip: 'Requires a GPU device.');
    return;
  }

  SceneDocument buildDocument({bool animateChild = false}) {
    final document = SceneDocument();
    final parentId = document.newId();
    final childId = document.newId();
    document.addNode(
      NodeSpec(
        id: childId,
        name: 'Child',
        components: [
          ComponentSpec(
            'directionalLight',
            properties: {'intensity': const DoubleValue(2)},
          ),
        ],
      ),
    );
    document.addNode(
      NodeSpec(id: parentId, name: 'Parent', children: [childId]),
      root: true,
    );
    final retainedId = document.newId();
    document.addNode(NodeSpec(id: retainedId, name: 'Retained'), root: true);
    if (animateChild) {
      final animationId = document.newId();
      // Payload references are absent; animation realization treats missing
      // payloads as empty, and the restore guard only reads channel targets.
      document.animations[animationId] = AnimationSpec(
        animationId,
        name: 'spin',
        channels: [
          AnimationChannelSpec(
            target: childId,
            property: AnimationProperty.rotation,
            timeline: document.newId(),
            keyframes: document.newId(),
          ),
        ],
      );
    }
    return document;
  }

  LocalId byName(SceneDocument document, String name) => document.nodes.entries
      .firstWhere((entry) => entry.value.name == name)
      .key;

  test('undoing a delete restores live nodes without a full rebuild', () async {
    await Scene.initializeStaticResources();
    final document = buildDocument();
    final parentId = byName(document, 'Parent');
    final childId = byName(document, 'Child');
    final retainedId = byName(document, 'Retained');
    final controller = await EditorController.open(EditorSession(document));
    addTearDown(controller.dispose);
    final retainedBefore = controller.liveNode(retainedId);
    expect(retainedBefore, isNotNull);

    await controller.run('deleteNode', {'nodeId': parentId.toToken()});
    expect(controller.liveNode(parentId), isNull);
    expect(controller.liveNode(childId), isNull);

    await controller.undo();
    // The unrelated node kept its live object, so the whole scene was not
    // re-realized.
    expect(identical(controller.liveNode(retainedId), retainedBefore), isTrue);
    final parent = controller.liveNode(parentId);
    final child = controller.liveNode(childId);
    expect(parent, isNotNull);
    expect(child, isNotNull);
    expect(child!.parent, same(parent));
    expect(child.getComponents<DirectionalLightComponent>(), isNotEmpty);
  });

  test('an undone delete restores the node shadow casting mode', () async {
    await Scene.initializeStaticResources();
    final document = buildDocument();
    final parentId = byName(document, 'Parent');
    document.node(parentId)!.shadowCastingMode = 'shadowsOnly';
    final controller = await EditorController.open(EditorSession(document));
    addTearDown(controller.dispose);
    expect(
      controller.liveNode(parentId)!.shadowCastingMode,
      ShadowCastingMode.shadowsOnly,
    );

    await controller.run('deleteNode', {'nodeId': parentId.toToken()});
    await controller.undo();

    // The restore path rebuilds the node by hand, so a field it forgets comes
    // back as the default and silently disagrees with the document.
    expect(
      controller.liveNode(parentId)!.shadowCastingMode,
      ShadowCastingMode.shadowsOnly,
    );
  });

  test(
    'a restored node driven by an animation takes the full rebuild',
    () async {
      await Scene.initializeStaticResources();
      final document = buildDocument(animateChild: true);
      final parentId = byName(document, 'Parent');
      final animatedChildId = byName(document, 'Child');
      final retainedId = byName(document, 'Retained');
      final controller = await EditorController.open(EditorSession(document));
      addTearDown(controller.dispose);
      final retainedBefore = controller.liveNode(retainedId);

      await controller.run('deleteNode', {'nodeId': parentId.toToken()});
      await controller.undo();
      // The full realize replaced every live node, including the unrelated one,
      // so the animation could rebind its restored target.
      expect(
        identical(controller.liveNode(retainedId), retainedBefore),
        isFalse,
      );
      expect(controller.liveNode(animatedChildId), isNotNull);
    },
  );
}
