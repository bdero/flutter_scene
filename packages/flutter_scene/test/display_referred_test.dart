// Covers the display-referred surface path: which materials opt in, how the
// opt-in keeps them out of the scene's depth and shadow passes, and that
// WidgetComponent turns it on for the material it owns.

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/display_referred_pass.dart';
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
    test('display-referred suite requires a GPU context', () {
      markTestSkipped('No Impeller GPU context');
    });
    return;
  }

  test('materials are scene-referred unless they opt in', () {
    expect(UnlitMaterial().displayReferred, isFalse);
    expect(PhysicallyBasedMaterial().displayReferred, isFalse);
    expect((UnlitMaterial()..displayReferred = true).displayReferred, isTrue);
  });

  test('a display-referred material leaves the depth prepass', () {
    final material = UnlitMaterial()..alphaMode = AlphaMode.opaque;
    expect(material.depthPrepassParticipates, isTrue);
    material.displayReferred = true;
    expect(material.depthPrepassParticipates, isFalse);
  });

  testWidgets('the scene scan finds a visible display-referred surface', (
    tester,
  ) async {
    final material = UnlitMaterial()..alphaMode = AlphaMode.opaque;
    final scene = Scene();
    scene.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material)));

    Future<void> render() async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 128,
            height: 128,
            child: SceneView(
              scene,
              camera: PerspectiveCamera(position: vm.Vector3(0, 0, 4)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    await render();
    expect(sceneHasDisplayReferred(scene.renderScene), isFalse);

    material.displayReferred = true;
    await render();
    expect(sceneHasDisplayReferred(scene.renderScene), isTrue);
  });

  testWidgets('WidgetComponent owns a display-referred material by default', (
    tester,
  ) async {
    final scene = Scene();
    final component = WidgetComponent(
      child: const ColoredBox(color: Color(0xFF204080)),
      size: const Size(64, 64),
      pixelRatio: 1,
    );
    final node = Node()..addComponent(component);
    scene.add(node);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 128,
          height: 128,
          child: SceneView(scene, camera: PerspectiveCamera()),
        ),
      ),
    );
    await _settle(tester, () => component.controller.texture != null);

    final mesh = node.getComponent<MeshComponent>();
    expect(mesh, isNotNull, reason: 'the component never built its surface');
    final material = mesh!.mesh.primitives.single.material as UnlitMaterial;
    expect(material.displayReferred, isTrue);
  });

  testWidgets('WidgetComponent can stay scene-referred', (tester) async {
    final scene = Scene();
    final component = WidgetComponent(
      child: const ColoredBox(color: Color(0xFF204080)),
      size: const Size(64, 64),
      pixelRatio: 1,
      displayReferred: false,
    );
    final node = Node()..addComponent(component);
    scene.add(node);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 128,
          height: 128,
          child: SceneView(scene, camera: PerspectiveCamera()),
        ),
      ),
    );
    await _settle(tester, () => component.controller.texture != null);

    final mesh = node.getComponent<MeshComponent>();
    expect(mesh, isNotNull, reason: 'the component never built its surface');
    final material = mesh!.mesh.primitives.single.material as UnlitMaterial;
    expect(material.displayReferred, isFalse);
  });
}
