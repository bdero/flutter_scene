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
  final world = PhysicsWorld(RapierWorld());
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('convex hull cooks a tetrahedron and stops a falling ball', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

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
    hullNode.addComponent(RigidBody(type: BodyType.fixed));
    hullNode.addComponent(Collider(shape: ConvexHullShape(points: hullPoints)));
    root.add(hullNode);
    hullNode.getComponents<RigidBody>().first.mount();
    hullNode.getComponents<Collider>().first.mount();

    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    final ballBody = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    ballNode.addComponent(Collider(shape: SphereShape(radius: 0.5)));
    root.add(ballNode);
    ballBody.mount();
    ballNode.getComponents<Collider>().first.mount();

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(ballBody.readSimulationPose().$1.y, greaterThan(-1.0));
  });

  test('trimesh cooks a single-triangle floor and stops a falling ball', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final vertices = Float32List.fromList([-10, 0, -10, 10, 0, -10, 0, 0, 10]);
    final indices = Uint32List.fromList([0, 1, 2]);

    final floorNode = Node();
    floorNode.addComponent(RigidBody(type: BodyType.fixed));
    floorNode.addComponent(
      Collider(
        shape: TriMeshShape(vertices: vertices, indices: indices),
      ),
    );
    root.add(floorNode);
    floorNode.getComponents<RigidBody>().first.mount();
    floorNode.getComponents<Collider>().first.mount();

    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    final ballBody = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    ballNode.addComponent(Collider(shape: SphereShape(radius: 0.5)));
    root.add(ballNode);
    ballBody.mount();
    ballNode.getComponents<Collider>().first.mount();

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(ballBody.readSimulationPose().$1.y, greaterThan(-1.0));
  });

  test('heightfield cooks a flat plane and stops a falling ball', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final heights = Float32List(4 * 4); // all zeros: flat plane

    final floorNode = Node();
    floorNode.addComponent(RigidBody(type: BodyType.fixed));
    floorNode.addComponent(
      Collider(
        shape: HeightFieldShape(
          width: 4,
          depth: 4,
          heights: heights,
          scale: Vector3(5, 1, 5),
        ),
      ),
    );
    root.add(floorNode);
    floorNode.getComponents<RigidBody>().first.mount();
    floorNode.getComponents<Collider>().first.mount();

    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    final ballBody = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ballBody);
    ballNode.addComponent(Collider(shape: SphereShape(radius: 0.5)));
    root.add(ballNode);
    ballBody.mount();
    ballNode.getComponents<Collider>().first.mount();

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    expect(ballBody.readSimulationPose().$1.y, greaterThan(-1.0));
  });

  test('compound shape produces one native handle per child primitive', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

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
    node.addComponent(RigidBody(type: BodyType.dynamic_, mass: 1.0));
    final collider = Collider(shape: compound);
    node.addComponent(collider);
    root.add(node);
    node.getComponents<RigidBody>().first.mount();
    collider.mount();

    expect(collider.handles, hasLength(2));
    // Each child should be a distinct native handle.
    expect(collider.handles.toSet(), hasLength(2));

    world.step(1.0 / 60.0);
  });

  test('a degenerate convex hull fails the mount', () {
    final root = _boot();

    final node = Node();
    node.addComponent(RigidBody(type: BodyType.fixed));
    // Two colinear points cannot form a hull; the backend returns no
    // handles and the component surfaces that as an error.
    final collider = Collider(
      shape: ConvexHullShape(points: Float32List.fromList([0, 0, 0, 1, 0, 0])),
    );
    node.addComponent(collider);
    root.add(node);
    node.getComponents<RigidBody>().first.mount();

    expect(collider.mount, throwsUnsupportedError);
    expect(collider.handles, isEmpty);
  });
}
