// Covers the scene-structure hot-reload patch: applying a diff to a live node
// graph in place. Uses component-less nodes and a directional light (both
// realize without the GPU), so the structural patching is exercised GPU-free.

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/reload/reload.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test(
    'patches added, removed, reparented, and transform-changed nodes',
    () async {
      const r = LocalId(1, 1);
      const a = LocalId(1, 2);
      const b = LocalId(1, 3);
      const c = LocalId(1, 4);
      const d = LocalId(1, 5);

      final oldDoc = SceneDocument();
      oldDoc.addNode(NodeSpec(id: r, name: 'r', children: [a, b]), root: true);
      oldDoc.addNode(NodeSpec(id: a, name: 'a'));
      oldDoc.addNode(NodeSpec(id: b, name: 'b', children: [c]));
      oldDoc.addNode(NodeSpec(id: c, name: 'c'));

      final liveRoot = realizeScene(oldDoc);
      final liveR = liveRoot.children.single;
      final liveC = liveR.getChildByName('c')!; // under b

      // Remove a; add d under r; move c from b to r; move b up.
      final newDoc = SceneDocument();
      newDoc.addNode(
        NodeSpec(id: r, name: 'r', children: [b, d, c]),
        root: true,
      );
      newDoc.addNode(
        NodeSpec(
          id: b,
          name: 'b',
          transform: TrsTransform(translation: Vector3(0, 5, 0)),
        ),
      );
      newDoc.addNode(NodeSpec(id: c, name: 'c'));
      newDoc.addNode(NodeSpec(id: d, name: 'd'));

      await reloadScene(liveRoot, oldDoc, newDoc);

      expect(liveRoot.getChildByName('a'), isNull); // removed
      expect(liveR.children.map((n) => n.name).toSet(), {'b', 'd', 'c'});

      final liveB = liveR.children.firstWhere((n) => n.name == 'b');
      expect(liveB.children, isEmpty); // c moved out
      expect(liveB.localTransform.getTranslation(), Vector3(0, 5, 0));

      // c kept its identity, now parented under r.
      expect(liveR.children.firstWhere((n) => n.name == 'c'), same(liveC));
      expect(liveC.parent, same(liveR));
    },
  );

  test('rebuilds a changed component, keeping node identity', () async {
    const sunId = LocalId(2, 1);
    ComponentSpec light(double intensity) => ComponentSpec(
      'directionalLight',
      properties: {'intensity': DoubleValue(intensity)},
    );

    final oldDoc = SceneDocument();
    oldDoc.addNode(
      NodeSpec(id: sunId, name: 'sun', components: [light(3.0)]),
      root: true,
    );
    final liveRoot = realizeScene(oldDoc);
    final sun = liveRoot.children.single;
    expect(sun.getComponent<DirectionalLightComponent>()!.light.intensity, 3.0);

    final newDoc = SceneDocument();
    newDoc.addNode(
      NodeSpec(id: sunId, name: 'sun', components: [light(7.0)]),
      root: true,
    );
    await reloadScene(liveRoot, oldDoc, newDoc);

    expect(liveRoot.children.single, same(sun)); // identity preserved
    expect(sun.getComponent<DirectionalLightComponent>()!.light.intensity, 7.0);
  });
}
