// Frustum / cull tests. Exercises Camera.getFrustum and
// Node.isVisibleTo without touching a real GPU context. Uses a stub
// Geometry / Material so MeshPrimitive can be constructed in pure
// Dart, same pattern as bounds_test.dart.

import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  _StubGeometry(Aabb3 aabb) {
    setLocalBounds(
      aabb,
      Sphere.centerRadius(
        (aabb.min + aabb.max) * 0.5,
        ((aabb.max - aabb.min) * 0.5).length,
      ),
    );
  }

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition,
  ) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubGeometryNoBounds extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition,
  ) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

Node _unitCubeNodeAt(Vector3 position) {
  return Node(
    localTransform: Matrix4.translation(position),
    mesh: Mesh.primitives(
      primitives: [
        MeshPrimitive(
          _StubGeometry(Aabb3.minMax(Vector3.all(-1.0), Vector3.all(1.0))),
          _StubMaterial(),
        ),
      ],
    ),
  );
}

const ui.Size _viewport = ui.Size(800, 600);

PerspectiveCamera _cameraLookingAtOrigin() {
  // Eye at -10z, looking at origin, default 45deg FOV. The default
  // PerspectiveCamera() is at -5z which sits very close to a unit
  // cube at the origin; pull back to put cubes safely inside a
  // canonical frustum.
  return PerspectiveCamera(
    position: Vector3(0, 0, -10),
    target: Vector3.zero(),
  );
}

void main() {
  group('Camera.getFrustum', () {
    test('contains the camera target and excludes a far-off-axis point', () {
      final camera = _cameraLookingAtOrigin();
      final frustum = camera.getFrustum(_viewport);
      expect(
        frustum.containsVector3(Vector3.zero()),
        isTrue,
        reason: 'origin is on the line of sight, inside the near/far range',
      );
      expect(
        frustum.containsVector3(Vector3(0, 0, -50)),
        isFalse,
        reason: 'point behind the camera should be outside',
      );
      expect(
        frustum.containsVector3(Vector3(1000, 0, 0)),
        isFalse,
        reason: 'point far off the side should be outside',
      );
    });
  });

  group('Node.isVisibleTo', () {
    test('cube on the line of sight is visible', () {
      final node = _unitCubeNodeAt(Vector3.zero());
      expect(node.isVisibleTo(_cameraLookingAtOrigin(), _viewport), isTrue);
    });

    test('cube far off-screen is culled', () {
      final node = _unitCubeNodeAt(Vector3(1000, 0, 0));
      expect(node.isVisibleTo(_cameraLookingAtOrigin(), _viewport), isFalse);
    });

    test('frustumCulled = false bypasses the cull test', () {
      final node = _unitCubeNodeAt(Vector3(1000, 0, 0));
      node.frustumCulled = false;
      expect(node.isVisibleTo(_cameraLookingAtOrigin(), _viewport), isTrue);
    });

    test(
      'skinned node uses geometry bounds when present (pose-union path)',
      () {
        // Skinned but with bounds (importer populated localBounds from
        // skinnedPoseUnionAabb). Treated like any other bounded
        // subtree.
        final node = _unitCubeNodeAt(Vector3(1000, 0, 0));
        node.skin = Skin();
        expect(node.isVisibleTo(_cameraLookingAtOrigin(), _viewport), isFalse);
      },
    );

    test('skinned node without bounds is treated as always visible', () {
      // No pose-union baked (e.g. no animations in the source).
      // Runtime conservatively skips cull.
      final node = Node(
        localTransform: Matrix4.translation(Vector3(1000, 0, 0)),
        mesh: Mesh.primitives(
          primitives: [MeshPrimitive(_StubGeometryNoBounds(), _StubMaterial())],
        ),
      );
      node.skin = Skin();
      expect(node.isVisibleTo(_cameraLookingAtOrigin(), _viewport), isTrue);
    });

    test('parent transform is honoured when computing world AABB', () {
      // Cube at the origin is visible. Wrap it in a parent that
      // translates far off to the side, and visibility flips.
      final cube = _unitCubeNodeAt(Vector3.zero());
      final group = Node(
        localTransform: Matrix4.translation(Vector3(1000, 0, 0)),
      );
      group.add(cube);
      expect(cube.isVisibleTo(_cameraLookingAtOrigin(), _viewport), isFalse);
    });

    test('negative-determinant world transform still culls correctly', () {
      // Mirror the cube along Z (the same flip the scene-root uses).
      // It should still be visible in front of the camera.
      final cube = _unitCubeNodeAt(Vector3.zero());
      final flip = Node(
        localTransform: Matrix4.identity()..setEntry(2, 2, -1.0),
      );
      flip.add(cube);
      expect(cube.isVisibleTo(_cameraLookingAtOrigin(), _viewport), isTrue);
    });
  });
}
