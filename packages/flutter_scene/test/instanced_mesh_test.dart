// InstancedMesh API tests. Uses stub Geometry and Material so the tests
// run without a Flutter GPU context.

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Geometry that skips shader-library access. Optionally carries a
/// local-space AABB so aggregate-bounds logic can be exercised.
class _StubGeometry extends Geometry {
  _StubGeometry({Aabb3? aabb}) {
    if (aabb != null) {
      setLocalBounds(
        aabb,
        Sphere.centerRadius(
          (aabb.min + aabb.max) * 0.5,
          ((aabb.max - aabb.min) * 0.5).length,
        ),
      );
    }
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

InstancedMesh _instancedMesh({Aabb3? aabb}) => InstancedMesh(
  geometry: _StubGeometry(aabb: aabb),
  material: _StubMaterial(),
);

void main() {
  group('InstancedMesh instances', () {
    test('a new instanced mesh has no instances', () {
      expect(_instancedMesh().instanceCount, 0);
    });

    test('addInstance appends and returns the new index', () {
      final mesh = _instancedMesh();
      expect(mesh.addInstance(Matrix4.identity()), 0);
      expect(mesh.addInstance(Matrix4.identity()), 1);
      expect(mesh.instanceCount, 2);
    });

    test('addInstance copies the transform', () {
      final mesh = _instancedMesh();
      final transform = Matrix4.identity();
      mesh.addInstance(transform);
      transform.setTranslationRaw(9, 9, 9);

      expect(mesh.instances[0], Matrix4.identity());
    });

    test('stores white by default and copies explicit colors', () {
      final mesh = _instancedMesh();
      mesh.addInstance(Matrix4.identity());
      final color = Vector4(0.2, 0.4, 0.6, 0.8);
      mesh.addInstance(Matrix4.identity(), color: color);
      color.setZero();

      expect(mesh.colors[0], Vector4(1, 1, 1, 1));
      expect(mesh.colors[1], Vector4(0.2, 0.4, 0.6, 0.8));
    });

    test('updates an instance color', () {
      final mesh = _instancedMesh()..addInstance(Matrix4.identity());
      mesh.setInstanceColor(0, Vector4(0.1, 0.2, 0.3, 1));
      expect(mesh.colors[0], Vector4(0.1, 0.2, 0.3, 1));
    });

    test('setInstanceTransform replaces an instance transform', () {
      final mesh = _instancedMesh();
      mesh.addInstance(Matrix4.identity());
      final moved = Matrix4.translation(Vector3(5, 0, 0));
      mesh.setInstanceTransform(0, moved);

      expect(mesh.instances[0], moved);
    });

    test('removeInstanceAt removes and shifts later instances', () {
      final mesh = _instancedMesh();
      final a = Matrix4.translation(Vector3(1, 0, 0));
      final b = Matrix4.translation(Vector3(2, 0, 0));
      final c = Matrix4.translation(Vector3(3, 0, 0));
      mesh.addInstance(a);
      mesh.addInstance(b);
      mesh.addInstance(c);

      mesh.removeInstanceAt(0);
      expect(mesh.instanceCount, 2);
      expect(mesh.instances[0], b);
      expect(mesh.colors, hasLength(2));
      expect(mesh.instances[1], c);
    });

    test('clearInstances removes every instance', () {
      final mesh = _instancedMesh();
      mesh.addInstance(Matrix4.identity());
      mesh.addInstance(Matrix4.identity());
      mesh.clearInstances();

      expect(mesh.instanceCount, 0);
      expect(mesh.colors, isEmpty);
    });
  });

  group('InstancedMesh aggregate bounds', () {
    test('bounds are null without a geometry bound', () {
      final mesh = _instancedMesh();
      mesh.addInstance(Matrix4.identity());
      expect(mesh.aggregateBounds, isNull);
    });

    test('bounds are null when there are no instances', () {
      final mesh = _instancedMesh(
        aabb: Aabb3.minMax(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5)),
      );
      expect(mesh.aggregateBounds, isNull);
    });

    test('bounds hull every instance and update after a change', () {
      final mesh = _instancedMesh(
        aabb: Aabb3.minMax(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5)),
      );
      mesh.addInstance(Matrix4.translation(Vector3(10, 0, 0)));
      mesh.addInstance(Matrix4.translation(Vector3(-10, 0, 0)));

      final bounds = mesh.aggregateBounds!;
      expect(bounds.min.x, closeTo(-10.5, 1e-6));
      expect(bounds.max.x, closeTo(10.5, 1e-6));

      mesh.clearInstances();
      expect(mesh.aggregateBounds, isNull);
    });
  });
}
