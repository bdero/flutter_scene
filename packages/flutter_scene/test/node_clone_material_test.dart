// Regression test: cloning a node (as the model cache does on every
// loadModel) must give each clone its own MeshPrimitive slots, so
// reassigning one instance's material does not leak onto sibling clones
// or the template. The geometry stays shared (it is the heavy GPU
// resource). Uses stub geometry / material so no GPU context is required
// (same pattern as mesh_removal_test).

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
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
    gpu.HostBuffer transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition,
  ) => throw UnsupportedError('Stub geometry is not renderable');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('Stub material is not renderable');
}

void main() {
  test('clones get independent materials but share geometry', () {
    final geometry = _StubGeometry();
    final original = _StubMaterial();
    final template = Node(mesh: Mesh(geometry, original));

    final a = template.clone();
    final b = template.clone();

    // Reassign one clone's material.
    final replacement = _StubMaterial();
    a.mesh!.primitives.single.material = replacement;

    // The other clone and the template keep the original material.
    expect(a.mesh!.primitives.single.material, same(replacement));
    expect(b.mesh!.primitives.single.material, same(original));
    expect(template.mesh!.primitives.single.material, same(original));

    // Geometry (the GPU-heavy resource) stays shared across clones.
    expect(a.mesh!.primitives.single.geometry, same(geometry));
    expect(b.mesh!.primitives.single.geometry, same(geometry));

    // Each clone has its own Mesh and primitive objects.
    expect(a.mesh, isNot(same(b.mesh)));
    expect(a.mesh, isNot(same(template.mesh)));
    expect(a.mesh!.primitives.single, isNot(same(b.mesh!.primitives.single)));
  });
}
