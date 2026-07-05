// Regression test: removing a mesh-bearing node must drop its
// RenderItems from the flat render list. A bug in
// MeshComponent._unregisterRenderItems guarded the removal on
// isMounted, but Component.unmount clears the mounted flag before
// calling onUnmount, so the guard always failed during teardown and
// the mesh stayed visible forever. Uses stub geometry / material so no
// GPU context is required (same pattern as cull_test / bounds_test).

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
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

Node _meshNode() => Node(
  mesh: Mesh.primitives(
    primitives: [MeshPrimitive(_StubGeometry(), _StubMaterial())],
  ),
);

void main() {
  test('removing a mounted mesh node drops its render items', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);

    final child = _meshNode();
    root.add(child);
    expect(
      renderScene.items.length,
      1,
      reason: 'mounting the mesh registers one render item',
    );

    root.remove(child);
    expect(
      renderScene.items,
      isEmpty,
      reason: 'removing the node must unregister its render item',
    );
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
