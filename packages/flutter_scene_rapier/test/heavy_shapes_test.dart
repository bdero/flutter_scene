// Cooking the heavy shapes (convex hull, trimesh, height field) and
// compound shapes (each child becomes its own Rapier collider on the
// same body).
//
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _boot() {
  final root = Node();
  final world = RapierWorld();
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('convex hull cooks a tetrahedron and stops a falling ball', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    // Tetrahedron with 4 points, large enough to act as a wedge floor.
    final hullPoints = Float32List.fromList([
      -5,
      0,
      -5,
      5,
      0,
      -5,
      0,
      0,
      5,
      0,
      1,
      0,
    ]);

    final hullNode = Node(
      localTransform: Matrix4.translation(Vector3(0, -0.5, 0)),
    );
    hullNode.addComponent(RapierRigidBody(type: BodyType.fixed));
    hullNode.addComponent(
      RapierCollider(shape: ConvexHullShape(points: hullPoints)),
    );
    root.add(hullNode);
    hullNode.getComponents<RapierRigidBody>().first.mount();
    hullNode.getComponents<RapierCollider>().first.mount();

    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    final ballBody = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    ballNode.addComponent(RapierCollider(shape: SphereShape(radius: 0.5)));
    root.add(ballNode);
    ballBody.mount();
    ballNode.getComponents<RapierCollider>().first.mount();

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(ballBody.readNativeTranslation().y, greaterThan(-1.0));
  });

  test('trimesh cooks a single-triangle floor and stops a falling ball', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final vertices = Float32List.fromList([-10, 0, -10, 10, 0, -10, 0, 0, 10]);
    final indices = Uint32List.fromList([0, 1, 2]);

    final floorNode = Node();
    floorNode.addComponent(RapierRigidBody(type: BodyType.fixed));
    floorNode.addComponent(
      RapierCollider(
        shape: TriMeshShape(vertices: vertices, indices: indices),
      ),
    );
    root.add(floorNode);
    floorNode.getComponents<RapierRigidBody>().first.mount();
    floorNode.getComponents<RapierCollider>().first.mount();

    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    final ballBody = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    ballNode.addComponent(RapierCollider(shape: SphereShape(radius: 0.5)));
    root.add(ballNode);
    ballBody.mount();
    ballNode.getComponents<RapierCollider>().first.mount();

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(ballBody.readNativeTranslation().y, greaterThan(-1.0));
  });

  test('heightfield cooks a flat plane and stops a falling ball', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final heights = Float32List(4 * 4); // all zeros: flat plane

    final floorNode = Node();
    floorNode.addComponent(RapierRigidBody(type: BodyType.fixed));
    floorNode.addComponent(
      RapierCollider(
        shape: HeightFieldShape(
          width: 4,
          depth: 4,
          heights: heights,
          scale: Vector3(5, 1, 5),
        ),
      ),
    );
    root.add(floorNode);
    floorNode.getComponents<RapierRigidBody>().first.mount();
    floorNode.getComponents<RapierCollider>().first.mount();

    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    final ballBody = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    ballNode.addComponent(RapierCollider(shape: SphereShape(radius: 0.5)));
    root.add(ballNode);
    ballBody.mount();
    ballNode.getComponents<RapierCollider>().first.mount();

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(ballBody.readNativeTranslation().y, greaterThan(-1.0));
  });

  test('compound shape produces one native handle per child primitive', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    // An "L" made of two boxes.
    final compound = CompoundShape(
      children: [
        CompoundChild(
          shape: BoxShape(halfExtents: Vector3(1, 0.5, 0.5)),
          localPose: Matrix4.translation(Vector3(0, 0, 0)),
        ),
        CompoundChild(
          shape: BoxShape(halfExtents: Vector3(0.5, 1, 0.5)),
          localPose: Matrix4.translation(Vector3(1, 1, 0)),
        ),
      ],
    );

    final node = Node();
    node.addComponent(RapierRigidBody(type: BodyType.dynamic_, mass: 1.0));
    final collider = RapierCollider(shape: compound);
    node.addComponent(collider);
    root.add(node);
    node.getComponents<RapierRigidBody>().first.mount();
    collider.mount();

    expect(collider.nativeHandles, hasLength(2));
    // Each child should be a distinct native handle.
    expect(collider.nativeHandles.toSet(), hasLength(2));

    world.step(1.0 / 60.0);
  });

  test('a degenerate convex hull leaves nativeHandle null', () {
    final root = _boot();

    final node = Node();
    node.addComponent(RapierRigidBody(type: BodyType.fixed));
    // Two colinear points cannot form a hull.
    final collider = RapierCollider(
      shape: ConvexHullShape(points: Float32List.fromList([0, 0, 0, 1, 0, 0])),
    );
    node.addComponent(collider);
    root.add(node);
    node.getComponents<RapierRigidBody>().first.mount();
    collider.mount();

    expect(collider.nativeHandle, isNull);
  });
}
