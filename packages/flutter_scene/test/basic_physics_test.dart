// Stage 2 tests for the pure-Dart basic backend: intersection math,
// query routing, body-type guard, and trigger event diffing.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/physics/basic/basic_queries.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('rayHitsShape', () {
    test('sphere hit returns distance and outward normal', () {
      // Sphere of radius 1 at (0, 0, 5). Ray from origin along +Z.
      final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));
      final hit = rayHitsShape(
        ray,
        SphereShape(radius: 1),
        Matrix4.translation(Vector3(0, 0, 5)),
        double.infinity,
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(4.0, 1e-6));
      expect(hit.worldPoint.z, closeTo(4.0, 1e-6));
      expect(hit.worldNormal.z, closeTo(-1.0, 1e-6));
    });

    test('sphere miss returns null', () {
      final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));
      final hit = rayHitsShape(
        ray,
        SphereShape(radius: 1),
        Matrix4.translation(Vector3(5, 0, 5)),
        double.infinity,
      );
      expect(hit, isNull);
    });

    test('box hit returns the near face normal', () {
      // Unit cube at the origin. Ray from (0, 0, 5) heading toward -Z.
      final ray = Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1));
      final hit = rayHitsShape(
        ray,
        BoxShape(halfExtents: Vector3(1, 1, 1)),
        Matrix4.identity(),
        double.infinity,
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(4.0, 1e-6));
      expect(hit.worldNormal.x, closeTo(0.0, 1e-6));
      expect(hit.worldNormal.y, closeTo(0.0, 1e-6));
      expect(hit.worldNormal.z, closeTo(1.0, 1e-6));
    });

    test('rotated box: the ray sees the box-local face it intersects', () {
      // Box rotated 90 degrees around Y. A ray along +X now sees what
      // was originally the +Z face.
      final pose = Matrix4.compose(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(0, 1, 0), 3.141592653589793 / 2),
        Vector3(1, 1, 1),
      );
      final ray = Ray.originDirection(Vector3(-5, 0, 0), Vector3(1, 0, 0));
      final hit = rayHitsShape(
        ray,
        BoxShape(halfExtents: Vector3(1, 1, 1)),
        pose,
        double.infinity,
      );
      expect(hit, isNotNull);
      // Box-local +Z axis maps to world +X under a +90 deg Y rotation.
      expect(hit!.worldNormal.x, closeTo(-1.0, 1e-6));
    });

    test('capsule cylindrical side hit', () {
      // Y-aligned capsule at the origin, radius 1, halfHeight 2. Ray
      // from (5, 0, 0) toward -X hits the side at distance 4.
      final ray = Ray.originDirection(Vector3(5, 0, 0), Vector3(-1, 0, 0));
      final hit = rayHitsShape(
        ray,
        CapsuleShape(radius: 1, halfHeight: 2),
        Matrix4.identity(),
        double.infinity,
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(4.0, 1e-6));
      expect(hit.worldNormal.x, closeTo(1.0, 1e-6));
    });

    test('capsule hemispherical cap hit', () {
      // Same capsule. Ray from (0, 10, 0) toward -Y hits the top cap.
      // Cap center is at (0, 2, 0), radius 1. Hit at y = 3, t = 7.
      final ray = Ray.originDirection(Vector3(0, 10, 0), Vector3(0, -1, 0));
      final hit = rayHitsShape(
        ray,
        CapsuleShape(radius: 1, halfHeight: 2),
        Matrix4.identity(),
        double.infinity,
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(7.0, 1e-6));
      expect(hit.worldNormal.y, closeTo(1.0, 1e-6));
    });

    test('maxDistance culls a far hit', () {
      final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));
      final hit = rayHitsShape(
        ray,
        SphereShape(radius: 1),
        Matrix4.translation(Vector3(0, 0, 100)),
        50.0,
      );
      expect(hit, isNull);
    });
  });

  group('BasicPhysicsWorld', () {
    test('raycast on an empty world returns null', () {
      final world = BasicPhysicsWorld();
      Node().addComponent(world);
      world.mount();

      final hit = world.raycast(
        Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1)),
      );
      expect(hit, isNull);
    });

    test(
      'raycast returns the closest collider; raycastAll sorts by distance',
      () {
        final root = _bootWorld();
        final world = root.getComponent<BasicPhysicsWorld>()!;

        _attachStaticCollider(root, SphereShape(radius: 1), Vector3(0, 0, 5));
        _attachStaticCollider(root, SphereShape(radius: 1), Vector3(0, 0, 10));

        final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));
        final closest = world.raycast(ray)!;
        expect(closest.distance, closeTo(4.0, 1e-6));

        final all = world.raycastAll(ray);
        expect(all, hasLength(2));
        expect(all[0].distance, closeTo(4.0, 1e-6));
        expect(all[1].distance, closeTo(9.0, 1e-6));
      },
    );

    test('triggers excluded by default; opt-in via includeTriggers', () {
      final root = _bootWorld();
      final world = root.getComponent<BasicPhysicsWorld>()!;

      _attachStaticCollider(
        root,
        SphereShape(radius: 1),
        Vector3(0, 0, 5),
        isTrigger: true,
      );

      final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));
      expect(world.raycast(ray), isNull);
      expect(world.raycast(ray, includeTriggers: true), isNotNull);
    });

    test('overlapSphere finds colliders whose AABBs overlap', () {
      final root = _bootWorld();
      final world = root.getComponent<BasicPhysicsWorld>()!;

      _attachStaticCollider(root, SphereShape(radius: 1), Vector3(0, 0, 0));
      _attachStaticCollider(root, SphereShape(radius: 1), Vector3(10, 0, 0));

      final hits = world.overlapSphere(Vector3.zero(), 2.0);
      expect(hits, hasLength(1));
    });

    test('constructing a dynamic body throws', () {
      expect(
        () => BasicKinematicBody(type: BodyType.dynamic_),
        throwsStateError,
      );
    });

    test(
      'AABB overlap that is not actual overlap does not fire trigger',
      () async {
        final root = _bootWorld();
        final world = root.getComponent<BasicPhysicsWorld>()!;

        // Sphere trigger of radius 1 at origin. A second sphere whose
        // AABB overlaps the trigger's AABB at the corners, but whose
        // actual sphere does not. Center at (1.3, 1.3, 0): the AABBs
        // (sphere shape produces an AABB enclosing the ball) overlap,
        // but distance is sqrt(1.3^2 + 1.3^2) = 1.838 > sum of radii
        // (1 + 0.5 = 1.5).
        _attachStaticCollider(
          root,
          SphereShape(radius: 1),
          Vector3.zero(),
          isTrigger: true,
        );
        _attachStaticCollider(
          root,
          SphereShape(radius: 0.5),
          Vector3(1.3, 1.3, 0),
        );

        final events = <CollisionEvent>[];
        final sub = world.collisions.listen(events.add);

        world.step(1.0 / 60.0);
        await Future<void>.delayed(Duration.zero);
        expect(
          events,
          isEmpty,
          reason: 'exact sphere-sphere overlap should reject the corner case',
        );

        await sub.cancel();
      },
    );

    test('trigger entry and exit events fire on the right step', () async {
      final root = _bootWorld();
      final world = root.getComponent<BasicPhysicsWorld>()!;

      // A trigger sphere at the origin and a kinematic body that the
      // test moves into and out of it.
      _attachStaticCollider(
        root,
        SphereShape(radius: 1),
        Vector3.zero(),
        isTrigger: true,
      );

      final mover = Node(localTransform: Matrix4.translation(Vector3(5, 0, 0)));
      final moverBody = BasicKinematicBody();
      mover.addComponent(moverBody);
      final moverCollider = BasicCollider(shape: SphereShape(radius: 0.5));
      mover.addComponent(moverCollider);
      root.add(mover);
      moverBody.mount();
      moverCollider.mount();

      final events = <CollisionEvent>[];
      final sub = world.collisions.listen(events.add);

      // Far from the trigger: no events.
      world.step(1.0 / 60.0);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);

      // Move into the trigger: entered fires once.
      mover.localTransform = Matrix4.translation(Vector3.zero());
      world.step(1.0 / 60.0);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single, isA<TriggerEntered>());

      // Same position: no new events.
      world.step(1.0 / 60.0);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));

      // Move out: exited fires once.
      mover.localTransform = Matrix4.translation(Vector3(5, 0, 0));
      world.step(1.0 / 60.0);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));
      expect(events.last, isA<TriggerExited>());

      await sub.cancel();
    });
  });
}

// Builds a root node with a mounted BasicPhysicsWorld. Children added
// later must have their components mounted manually because the root is
// not attached to a live RenderScene (constructing Scene requires a GPU
// context which unit tests do not have).
Node _bootWorld() {
  final root = Node();
  final world = BasicPhysicsWorld();
  root.addComponent(world);
  world.mount();
  return root;
}

void _attachStaticCollider(
  Node root,
  Shape shape,
  Vector3 worldPosition, {
  bool isTrigger = false,
}) {
  final node = Node(localTransform: Matrix4.translation(worldPosition));
  final collider = BasicCollider(shape: shape, isTrigger: isTrigger);
  node.addComponent(collider);
  root.add(node);
  collider.mount();
}
