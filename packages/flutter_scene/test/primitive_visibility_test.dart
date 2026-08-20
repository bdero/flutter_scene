// Covers per-primitive visibility and shadow casting: MeshPrimitive.visible
// gates the color passes independently of MeshPrimitive.castsShadow gating
// the shadow pass, both AND with the node-level equivalents (Node.visible
// hierarchy, Node.castsShadows). GPU-free: asserts the RenderItem fields the
// color/shadow encoders gate on (RenderItem.visible/primitiveVisible/
// castsShadows), same harness as node_shadow_casting_test.dart.

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) => throw UnsupportedError('Stub geometry is not renderable');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('Stub material is not renderable');
}

RenderItem _itemFor(RenderScene renderScene, MeshPrimitive primitive) =>
    renderScene.items.firstWhere(
      (item) => identical(item.geometry, primitive.geometry),
    );

void main() {
  test('MeshPrimitive.visible defaults to true', () {
    expect(MeshPrimitive(_StubGeometry(), _StubMaterial()).visible, isTrue);
  });

  test('MeshPrimitive.castsShadow defaults to true', () {
    expect(MeshPrimitive(_StubGeometry(), _StubMaterial()).castsShadow, isTrue);
  });

  test('a hidden primitive is excluded from the color passes while its '
      'sibling still draws', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final hidden = MeshPrimitive(_StubGeometry(), _StubMaterial())
      ..visible = false;
    final shown = MeshPrimitive(_StubGeometry(), _StubMaterial());
    root.add(Node(mesh: Mesh.primitives(primitives: [hidden, shown])));

    root.scenePrePass(0);

    expect(renderScene.items, hasLength(2));
    final hiddenItem = _itemFor(renderScene, hidden);
    final shownItem = _itemFor(renderScene, shown);
    expect(hiddenItem.primitiveVisible, isFalse);
    expect(shownItem.primitiveVisible, isTrue);
    // Both remain node-hierarchy visible; only the primitive flag differs.
    expect(hiddenItem.visible, isTrue);
    expect(shownItem.visible, isTrue);
  });

  test('castsShadow false removes a primitive from shadow casting while it '
      'still draws in color', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final primitive = MeshPrimitive(_StubGeometry(), _StubMaterial())
      ..castsShadow = false;
    root.add(Node(mesh: Mesh.primitives(primitives: [primitive])));

    root.scenePrePass(0);

    final item = renderScene.items.single;
    expect(item.castsShadows, isFalse);
    expect(item.primitiveVisible, isTrue);
    expect(item.visible, isTrue);
  });

  test('visible false with castsShadow true still casts a shadow', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final primitive = MeshPrimitive(_StubGeometry(), _StubMaterial())
      ..visible = false;
    root.add(Node(mesh: Mesh.primitives(primitives: [primitive])));

    root.scenePrePass(0);

    final item = renderScene.items.single;
    expect(item.primitiveVisible, isFalse);
    expect(item.castsShadows, isTrue);
  });

  test('Node.castsShadows still ANDs with the primitive flag', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final primitive = MeshPrimitive(_StubGeometry(), _StubMaterial());
    final node = Node(mesh: Mesh.primitives(primitives: [primitive]))
      ..castsShadows = false;
    root.add(node);

    root.scenePrePass(0);

    expect(renderScene.items.single.castsShadows, isFalse);
  });

  test('static shadow revision changes when castsShadow flips', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final primitive = MeshPrimitive(_StubGeometry(), _StubMaterial());
    final caster = Node(mesh: Mesh.primitives(primitives: [primitive]))
      ..shadowStatic = true;
    root.add(caster);

    root.scenePrePass(0);
    final initial = renderScene.staticShadowRevision;
    root.scenePrePass(0);
    expect(renderScene.staticShadowRevision, initial);

    primitive.castsShadow = false;
    root.scenePrePass(0);
    expect(renderScene.staticShadowRevision, greaterThan(initial));
  });

  test('static shadow revision is untouched when only primitive visibility '
      'flips', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final primitive = MeshPrimitive(_StubGeometry(), _StubMaterial());
    final caster = Node(mesh: Mesh.primitives(primitives: [primitive]))
      ..shadowStatic = true;
    root.add(caster);

    root.scenePrePass(0);
    final initial = renderScene.staticShadowRevision;

    primitive.visible = false;
    root.scenePrePass(0);
    expect(renderScene.staticShadowRevision, initial);
  });
}
