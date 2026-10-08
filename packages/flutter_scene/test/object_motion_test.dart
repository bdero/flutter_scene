// Object motion feeds temporal anti-aliasing and motion blur. GPU-gated:
// mounting a mesh uploads its geometry.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

void main() {
  if (!gpuAvailable()) {
    test('object motion requires a GPU context', () {
      markTestSkipped('No Impeller GPU context');
    });
    return;
  }

  test('a node that stops moving reports no motion', () {
    final scene = Scene();
    final node = Node(
      mesh: Mesh(CuboidGeometry(Vector3.all(1)), UnlitMaterial()),
    );
    scene.add(node);
    final component = node.getComponent<MeshComponent>()!;
    // ignore: invalid_use_of_protected_member
    final item = component.renderItems.single;
    component.refreshRenderItems();

    node.position = Vector3(2, 0, 0);
    component.refreshRenderItems();
    expect(item.isMoving, isTrue);
    expect(item.previousWorldTransform.getTranslation().x, 0);

    component.refreshRenderItems();
    expect(item.isMoving, isFalse);
    expect(item.previousWorldTransform.getTranslation().x, 2);
  });
}
