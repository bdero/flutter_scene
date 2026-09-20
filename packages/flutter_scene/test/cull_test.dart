// Frustum / cull tests. Exercises Camera.getFrustum and
// Node.isVisibleTo without touching a real GPU context. Uses a stub
// Geometry / Material so MeshPrimitive can be constructed in pure
// Dart, same pattern as bounds_test.dart.

import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_scene.dart';
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
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubGeometryNoBounds extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
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

/// Mounts [node] under a fresh root, runs a pre-pass so its render item
/// picks up a world AABB, and brings the BVH up to date, so
/// [RenderScene.cull] on the result reflects [node]'s current position.
RenderScene _sceneWith(Node node) {
  final renderScene = RenderScene();
  final root = Node()..debugMountInto(renderScene);
  root.add(node);
  root.scenePrePass(0);
  renderScene.rebuildIfDirty();
  return renderScene;
}

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

  group('RenderScene.cull rejection count', () {
    // The BVH rejects a whole subtree at an interior node without ever
    // touching the leaf items inside it, so a naive "count what the
    // encoder saw" approach sees nothing for a rejected item. These check
    // the count `cull` returns instead, the fix for that hole.
    test('a node far off-screen counts as culled', () {
      final scene = _sceneWith(_unitCubeNodeAt(Vector3(1000, 0, 0)));
      final frustum = _cameraLookingAtOrigin().getFrustum(_viewport);

      final rejected = scene.cull(frustum, (_) {});

      expect(rejected, 1);
    });

    test('an on-screen node does not count as culled', () {
      final scene = _sceneWith(_unitCubeNodeAt(Vector3.zero()));
      final frustum = _cameraLookingAtOrigin().getFrustum(_viewport);

      final rejected = scene.cull(frustum, (_) {});

      expect(rejected, 0);
    });

    test('frustumCulled = false never counts, even far off-screen', () {
      final node = _unitCubeNodeAt(Vector3(1000, 0, 0))..frustumCulled = false;
      final scene = _sceneWith(node);
      final frustum = _cameraLookingAtOrigin().getFrustum(_viewport);

      final rejected = scene.cull(frustum, (_) {});

      expect(rejected, 0);
    });
  });
}
