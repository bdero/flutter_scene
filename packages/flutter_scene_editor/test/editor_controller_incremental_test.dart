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
    test(
      'incremental editor reflection',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test(
    'component edits and primitive assembly preserve the live graph',
    () async {
      await Scene.initializeStaticResources();
      final document = SceneDocument();
      final lightId = document.newId();
      document.addNode(
        NodeSpec(
          id: lightId,
          name: 'Light',
          components: [
            ComponentSpec(
              'directionalLight',
              properties: {'intensity': const DoubleValue(1)},
            ),
          ],
        ),
        root: true,
      );
      final retainedId = document.newId();
      document.addNode(NodeSpec(id: retainedId, name: 'Retained'), root: true);
      final controller = await EditorController.open(EditorSession(document));
      addTearDown(controller.dispose);
      final retained = controller.liveNode(retainedId);

      await controller.run('setComponentProperties', {
        'nodeId': lightId.toToken(),
        'componentType': 'directionalLight',
        'properties': {'intensity': 2.0},
      });

      expect(controller.liveNode(retainedId), same(retained));
      expect(
        controller
            .liveNode(lightId)!
            .getComponent<DirectionalLightComponent>()!
            .light
            .intensity,
        2,
      );

      final geometryBefore = Set.of(document.resources.keys);
      await controller.run('createCuboidGeometry');
      final geometryId = document.resources.keys.firstWhere(
        (id) => !geometryBefore.contains(id),
      );
      final materialBefore = Set.of(document.resources.keys);
      await controller.run('createMaterial', {'type': 'physicallyBased'});
      final materialId = document.resources.keys.firstWhere(
        (id) => !materialBefore.contains(id),
      );
      final nodesBefore = Set.of(document.nodes.keys);
      await controller.run('createNode', {'name': 'Cube'});
      final cubeId = document.nodes.keys.firstWhere(
        (id) => !nodesBefore.contains(id),
      );
      await controller.run('addComponent', {
        'nodeId': cubeId.toToken(),
        'componentType': 'mesh',
        'properties': {
          'geometry': {'\$resource': geometryId.toToken()},
          'material': {'\$resource': materialId.toToken()},
        },
      });

      expect(controller.liveNode(retainedId), same(retained));
      expect(controller.liveNode(cubeId)?.mesh, isNotNull);

      await controller.undo();
      await controller.undo();
      expect(controller.liveNode(cubeId), isNull);
      expect(controller.liveNode(retainedId), same(retained));
      await controller.undo();
      await controller.undo();
    },
  );
}
