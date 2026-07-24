// Sphere collider cooking through the native FFI, sphere-on-sphere
// contact, and transform writeback through
// RapierWorld.interpolateTransforms.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _bootWorld({Vector3? gravity}) {
  final root = Node();
  final world = PhysicsWorld(RapierWorld(gravity: gravity));
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('a dynamic sphere collides with a fixed sphere and settles', () {
    final root = _bootWorld();
    final world = root.getComponent<PhysicsWorld>()!;

    // Static floor (a huge sphere far below the origin acts as a
    // ground plane). Box cooking lands in the next commit.
    final floor = Node(
      localTransform: Matrix4.translation(Vector3(0, -100, 0)),
    );
    final floorBody = RigidBody(type: BodyType.fixed);
    floor.addComponent(floorBody);
    floor.addComponent(Collider(shape: SphereShape(radius: 100.0)));
    root.add(floor);
    floorBody.mount();
    floor.getComponents<Collider>().first.mount();

    final ball = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
    final ballBody = RigidBody(type: BodyType.dynamic_);
    ball.addComponent(ballBody);
    ball.addComponent(Collider(shape: SphereShape(radius: 0.5)));
    root.add(ball);
    ballBody.mount();
    ball.getComponents<Collider>().first.mount();

    for (var i = 0; i < 240; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(0);

    // Ball at radius 0.5 sits on the floor sphere centered at y=-100
    // with radius 100, so the contact rests near y ≈ 0.5.
    final pos = ball.localTransform.getTranslation();
    expect(pos.y, greaterThan(0.0));
    expect(pos.y, lessThan(1.0));
  });

  test('interpolateTransforms writes the body pose back to the node', () {
    final root = _bootWorld();
    final world = root.getComponent<PhysicsWorld>()!;

    final ball = Node(localTransform: Matrix4.translation(Vector3(0, 10, 0)));
    final ballBody = RigidBody(type: BodyType.dynamic_);
    ball.addComponent(ballBody);
    ball.addComponent(Collider(shape: SphereShape(radius: 0.5)));
    root.add(ball);
    ballBody.mount();
    ball.getComponents<Collider>().first.mount();

    for (var i = 0; i < 30; i++) {
      world.step(1.0 / 60.0);
    }
    // alpha=1 snaps to the current step's pose, which should match
    // what the native side reports back.
    world.interpolateTransforms(1.0);

    final pos = ball.localTransform.getTranslation();
    expect(pos.y, lessThan(10.0));
    expect(pos.y, closeTo(ballBody.readSimulationPose().$1.y, 1e-5));
  });

  test('writeback leaves a fixed body node alone', () {
    final root = _bootWorld();
    final world = root.getComponent<PhysicsWorld>()!;

    final start = Matrix4.translation(Vector3(1, 2, 3));
    final node = Node(localTransform: start.clone());
    final rb = RigidBody(type: BodyType.fixed);
    node.addComponent(rb);
    node.addComponent(Collider(shape: SphereShape(radius: 1)));
    root.add(node);
    rb.mount();
    node.getComponents<Collider>().first.mount();

    for (var i = 0; i < 30; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(0);

    final t = node.localTransform.getTranslation();
    expect(t.x, closeTo(1, 1e-5));
    expect(t.y, closeTo(2, 1e-5));
    expect(t.z, closeTo(3, 1e-5));
  });

  test('Collider without a sibling body becomes static geometry', () {
    final root = _bootWorld(gravity: Vector3.zero());
    final world = root.getComponent<PhysicsWorld>()!;
    final node = Node(localTransform: Matrix4.translation(Vector3(0, 0, 5)));
    final collider = Collider(shape: SphereShape(radius: 1));
    node.addComponent(collider);
    root.add(node);
    collider.mount();
    expect(collider.handles, isNotEmpty);

    // The implicit fixed body holds the collider in the world; a ray
    // from the origin hits it and resolves back to the node.
    world.step(1.0 / 60.0);
    final hit = world.raycast(
      Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1)),
    );
    expect(hit, isNotNull);
    expect(identical(hit!.node, node), isTrue);
  });
}
