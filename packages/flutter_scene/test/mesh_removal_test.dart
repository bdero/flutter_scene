// Regression test: removing a mesh-bearing node must drop its
// RenderItems from the flat render list. A bug in
// MeshComponent._unregisterRenderItems guarded the removal on
// isMounted, but Component.unmount clears the mounted flag before
// calling onUnmount, so the guard always failed during teardown and
// the mesh stayed visible forever. Uses stub geometry / material so no
// GPU context is required (same pattern as cull_test / bounds_test).

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  _StubGeometry() {
    setLocalBounds(
      Aabb3.minMax(Vector3.all(-1), Vector3.all(1)),
      Sphere.centerRadius(Vector3.zero(), 1.732),
    );
  }

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

class _InputMaterial extends _StubMaterial {
  @override
  Set<RenderInput> get sceneInputs => const {RenderInput.depth};
}

Node _meshNode() => Node(
  mesh: Mesh.primitives(
    primitives: [MeshPrimitive(_StubGeometry(), _StubMaterial())],
  ),
);

void main() {
  test('material-only mesh replacement retains the render item', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final geometry = _StubGeometry();
    final firstMaterial = _StubMaterial();
    final secondMaterial = _StubMaterial();
    final child = Node(mesh: Mesh(geometry, firstMaterial));
    root.add(child);
    renderScene.rebuildIfDirty();

    final item = renderScene.items.single;
    final revision = renderScene.structureRevision;
    child.mesh = Mesh(geometry, secondMaterial);

    expect(identical(renderScene.items.single, item), isTrue);
    expect(identical(item.material, secondMaterial), isTrue);
    expect(renderScene.structureRevision, revision);
  });

  test('geometry replacement re-registers the render item', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final child = Node(mesh: Mesh(_StubGeometry(), _StubMaterial()));
    root.add(child);

    final item = renderScene.items.single;
    final revision = renderScene.structureRevision;
    child.mesh = Mesh(_StubGeometry(), _StubMaterial());

    expect(identical(renderScene.items.single, item), isFalse);
    expect(renderScene.structureRevision, greaterThan(revision));
  });

  test('material replacement invalidates changed scene inputs only', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final geometry = _StubGeometry();
    final child = Node(mesh: Mesh(geometry, _StubMaterial()));
    root.add(child);

    final beforeInputChange = materialSceneInputsRevision;
    child.mesh = Mesh(geometry, _InputMaterial());
    expect(materialSceneInputsRevision, greaterThan(beforeInputChange));

    final beforeEquivalentChange = materialSceneInputsRevision;
    child.mesh = Mesh(geometry, _InputMaterial());
    expect(materialSceneInputsRevision, beforeEquivalentChange);
  });

  test('removing a mounted mesh node drops its render items', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);

    final child = _meshNode();
    final beforeAdd = renderScene.structureRevision;
    root.add(child);
    expect(
      renderScene.items.length,
      1,
      reason: 'mounting the mesh registers one render item',
    );
    expect(renderScene.structureRevision, greaterThan(beforeAdd));

    final beforeRemove = renderScene.structureRevision;
    root.remove(child);
    expect(
      renderScene.items,
      isEmpty,
      reason: 'removing the node must unregister its render item',
    );
    expect(renderScene.structureRevision, greaterThan(beforeRemove));
  });

  test('removing one of several mesh nodes leaves the others', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);

    final a = _meshNode();
    final b = _meshNode();
    root.add(a);
    root.add(b);
    expect(renderScene.items.length, 2);

    root.remove(a);
    expect(renderScene.items.length, 1);
  });
}
