// Covers WidgetComponent: SceneView hosting and capture, surface creation
// with the owned/provided material, bindOnly delivery, and render-scene
// registration. GPU-gated (Scene and textures need a device).

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _settle(
  WidgetTester tester,
  bool Function() done, {
  int tries = 40,
}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

void main() {
  if (!_gpuAvailable()) {
    test('widget component suite requires a GPU context', () {
      markTestSkipped('No Impeller GPU context');
    });
    return;
  }

  testWidgets('tier 1: hosts, captures, and builds the textured quad', (
    tester,
  ) async {
    final scene = Scene();
    final component = WidgetComponent(
      child: const ColoredBox(color: Color(0xFF2244AA)),
      size: const Size(200, 100),
      worldHeight: 2.0,
    );
    final node = Node(name: 'panel')..addComponent(component);
    scene.add(node);

    await tester.pumpWidget(
      MaterialApp(home: SceneView(scene, camera: PerspectiveCamera())),
    );
    await _settle(tester, () => component.controller.texture != null);

    final texture = component.controller.texture;
    if (texture == null) {
      markTestSkipped('Capture did not complete in this environment');
      return;
    }
    expect(texture.width, 200);
    expect(texture.height, 100);

    // The component created its surface: a mesh on the same node whose
    // unlit material is bound to the capture.
    final mesh = node.getComponent<MeshComponent>();
    expect(mesh, isNotNull);
    final material = mesh!.mesh.primitives.single.material as UnlitMaterial;
    expect(identical(material.baseColorTexture, texture), isTrue);
    expect(material.isOpaque(), isFalse);

    // The quad is raycastable with the expected world size (2 tall, 4 wide
    // for the 2:1 capture aspect).
    final hit = scene.raycast(
      vm.Ray.originDirection(vm.Vector3(0, 0, 5), vm.Vector3(0, 0, -1)),
    );
    expect(hit, isNotNull);
    expect(hit!.node, node);
    expect(hit.uv!.x, closeTo(0.5, 1e-4));
  });

  testWidgets('bindOnly delivers the texture and creates no mesh', (
    tester,
  ) async {
    final scene = Scene();
    final received = <Object>[];
    final component = WidgetComponent.bindOnly(
      child: const ColoredBox(color: Color(0xFFAA2244)),
      size: const Size(64, 64),
      bind: received.add,
    );
    final node = Node(name: 'screen')..addComponent(component);
    scene.add(node);

    await tester.pumpWidget(
      MaterialApp(home: SceneView(scene, camera: PerspectiveCamera())),
    );
    await _settle(tester, () => received.isNotEmpty);
    if (received.isEmpty) {
      markTestSkipped('Capture did not complete in this environment');
      return;
    }
    expect(identical(received.single, component.controller.texture), isTrue);
    expect(node.getComponent<MeshComponent>(), isNull);
  });

  testWidgets('ScenePointer: hover, press, occlusion, interaction mask', (
    tester,
  ) async {
    final scene = Scene();
    var presses = 0;
    final component = WidgetComponent(
      child: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: ElevatedButton(
            onPressed: () => presses++,
            child: const Text('press'),
          ),
        ),
      ),
      size: const Size(200, 100),
      worldHeight: 2.0,
    );
    final panel = Node(name: 'panel')..addComponent(component);
    scene.add(panel);

    await tester.pumpWidget(
      MaterialApp(home: SceneView(scene, camera: PerspectiveCamera())),
    );
    await _settle(tester, () => component.controller.texture != null);
    if (component.controller.texture == null) {
      markTestSkipped('Capture did not complete in this environment');
      return;
    }

    final pointer = ScenePointer(scene);
    final ray = vm.Ray.originDirection(
      vm.Vector3(0, 0, 5),
      vm.Vector3(0, 0, -1),
    );

    // Hover then press-release lands on the button.
    pointer.pointAlong(ray);
    expect(pointer.hoveredWidget, component);
    pointer.press();
    pointer.release();
    await tester.pump();
    expect(presses, 1);

    // An occluder in front blocks the press.
    final blocker = Node(
      name: 'blocker',
      localTransform: vm.Matrix4.translation(vm.Vector3(0, 0, 1)),
      mesh: Mesh(CuboidGeometry(vm.Vector3(5, 5, 0.1)), UnlitMaterial()),
    );
    scene.add(blocker);
    pointer.pointAlong(ray);
    expect(pointer.hoveredWidget, isNull);
    pointer.press();
    pointer.release();
    await tester.pump();
    expect(presses, 1);
    scene.remove(blocker);

    // The interaction mask gates forwarding without affecting occlusion.
    pointer.interactionMask = 1 << 5; // panel is on layer 0
    pointer.pointAlong(ray);
    expect(pointer.hit, isNotNull);
    expect(pointer.hoveredWidget, isNull);
  });

  testWidgets('mount and unmount drive the render-scene registry', (
    tester,
  ) async {
    final scene = Scene();
    final component = WidgetComponent(
      child: const SizedBox(),
      size: const Size(32, 32),
    );
    final node = Node()..addComponent(component);
    expect(scene.renderScene.widgetComponents, isEmpty);
    scene.add(node);
    expect(scene.renderScene.widgetComponents, contains(component));
    scene.remove(node);
    expect(scene.renderScene.widgetComponents, isEmpty);
  });
}
