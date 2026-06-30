// Covers CameraComponent: a camera whose view is derived from the owning
// node's world transform should match an equivalent free PerspectiveCamera.

import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('CameraComponent', () {
    test('derives a view matching an equivalent PerspectiveCamera', () {
      final reference = PerspectiveCamera(
        position: Vector3(3.0, 4.0, 5.0),
        target: Vector3(-1.0, 0.5, 2.0),
        up: Vector3(0.0, 1.0, 0.0),
        fovRadiansY: 0.9,
        fovNear: 0.2,
        fovFar: 500.0,
      );

      // Place a camera node where the reference camera sits: the node's
      // world transform is the inverse of the reference view matrix.
      final world = Matrix4.identity()..copyInverse(reference.getViewMatrix());
      final node = Node(localTransform: world);
      final component = CameraComponent(projection: reference.projection);
      node.addComponent(component);
      final camera = component.toCamera();

      const size = Size(800.0, 600.0);
      final expected = reference.getViewTransform(size);
      final actual = camera.getViewTransform(size);
      for (var i = 0; i < 16; i++) {
        expect(
          actual.storage[i],
          closeTo(expected.storage[i], 1e-5),
          reason: 'view-projection element $i',
        );
      }

      expect(camera.position.x, closeTo(reference.position.x, 1e-5));
      expect(camera.position.y, closeTo(reference.position.y, 1e-5));
      expect(camera.position.z, closeTo(reference.position.z, 1e-5));

      final refForward = reference.forward;
      expect(camera.forward.x, closeTo(refForward.x, 1e-5));
      expect(camera.forward.y, closeTo(refForward.y, 1e-5));
      expect(camera.forward.z, closeTo(refForward.z, 1e-5));
    });

    test('captures the node transform at the time toCamera is called', () {
      final node = Node();
      final component = CameraComponent();
      node.addComponent(component);

      node.localTransform = Matrix4.translation(Vector3(1.0, 2.0, 3.0));
      final camera = component.toCamera();
      expect(camera.position.x, closeTo(1.0, 1e-6));
      expect(camera.position.y, closeTo(2.0, 1e-6));
      expect(camera.position.z, closeTo(3.0, 1e-6));
    });
  });

  group('primary camera', () {
    test('no cameras mounted resolves to null', () {
      expect(RenderScene().primaryCamera, isNull);
    });

    test('the first mounted camera auto-promotes to primary', () {
      final rs = RenderScene();
      final root = Node();
      final cam = CameraComponent();
      root.add(Node()..addComponent(cam));
      root.debugMountInto(rs);

      expect(rs.cameras, hasLength(1));
      expect(rs.primaryCamera, same(cam.toCamera()));
      expect(cam.active, isTrue);
    });

    test('later cameras do not steal the primary', () {
      final rs = RenderScene();
      final root = Node();
      final a = CameraComponent();
      final b = CameraComponent();
      root.add(Node()..addComponent(a));
      root.add(Node()..addComponent(b));
      root.debugMountInto(rs);

      expect(rs.primaryCamera, same(a.toCamera()));
      expect(a.active, isTrue);
      expect(b.active, isFalse);
    });

    test('makeActive overrides auto-promotion', () {
      final rs = RenderScene();
      final root = Node();
      final a = CameraComponent();
      final b = CameraComponent();
      root.add(Node()..addComponent(a));
      root.add(Node()..addComponent(b));
      root.debugMountInto(rs);

      b.makeActive();
      expect(rs.primaryCamera, same(b.toCamera()));
      expect(a.active, isFalse);
      expect(b.active, isTrue);
    });

    test('clearing the override reverts to the first mounted camera', () {
      final rs = RenderScene();
      final root = Node();
      final a = CameraComponent();
      final b = CameraComponent();
      root.add(Node()..addComponent(a));
      root.add(Node()..addComponent(b));
      root.debugMountInto(rs);

      b.makeActive();
      rs.cameraOverride = null;
      expect(rs.primaryCamera, same(a.toCamera()));
      expect(a.active, isTrue);
    });

    test('unmounting the active camera promotes the next', () {
      final rs = RenderScene();
      final root = Node();
      final a = CameraComponent();
      final b = CameraComponent();
      final aNode = Node()..addComponent(a);
      root.add(aNode);
      root.add(Node()..addComponent(b));
      root.debugMountInto(rs);
      expect(rs.primaryCamera, same(a.toCamera()));

      root.remove(aNode);
      expect(rs.cameras, hasLength(1));
      expect(rs.primaryCamera, same(b.toCamera()));
    });

    test('an explicit override persists when its component unmounts', () {
      final rs = RenderScene();
      final root = Node();
      final a = CameraComponent();
      final b = CameraComponent();
      root.add(Node()..addComponent(a));
      final bNode = Node()..addComponent(b);
      root.add(bNode);
      root.debugMountInto(rs);

      final bCamera = b.toCamera();
      b.makeActive();
      root.remove(bNode);

      // The override is independent of the mounted-camera registry.
      expect(rs.cameras, hasLength(1));
      expect(rs.primaryCamera, same(bCamera));
    });

    test('makeActive before mount is deferred and applied on mount', () {
      final rs = RenderScene();
      final root = Node();
      final a = CameraComponent();
      final b = CameraComponent();
      root.add(Node()..addComponent(a));
      root.add(Node()..addComponent(b));

      // Nothing is mounted yet, so this defers until onMount.
      b.makeActive();
      root.debugMountInto(rs);

      expect(rs.primaryCamera, same(b.toCamera()));
      expect(b.active, isTrue);
    });

    test('changing the projection updates the cached camera in place', () {
      final rs = RenderScene();
      final node = Node()..addComponent(CameraComponent());
      node.debugMountInto(rs);
      final component = node.getComponents<CameraComponent>().first;

      final camera = component.toCamera();
      final newProjection = PerspectiveProjection(fovRadiansY: 1.0);
      component.projection = newProjection;

      expect(camera.projection, same(newProjection));
      expect(component.toCamera(), same(camera));
    });
  });

  group('SceneView.resolveCamera precedence', () {
    final explicit = PerspectiveCamera();
    final built = PerspectiveCamera();
    final primary = PerspectiveCamera();

    test('an explicit camera wins over everything', () {
      expect(
        SceneView.resolveCamera(
          Duration.zero,
          camera: explicit,
          cameraBuilder: (_) => built,
          sceneCamera: primary,
        ),
        same(explicit),
      );
    });

    test('cameraBuilder is used when there is no explicit camera', () {
      expect(
        SceneView.resolveCamera(
          Duration.zero,
          cameraBuilder: (_) => built,
          sceneCamera: primary,
        ),
        same(built),
      );
    });

    test('the scene primary is used when no argument is given', () {
      expect(
        SceneView.resolveCamera(Duration.zero, sceneCamera: primary),
        same(primary),
      );
    });

    test('a shared default is used when nothing resolves a camera', () {
      final a = SceneView.resolveCamera(Duration.zero);
      final b = SceneView.resolveCamera(Duration.zero);
      expect(a, isA<PerspectiveCamera>());
      expect(a, same(b));
    });
  });
}
