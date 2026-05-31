// Stage 4 commit F tests: sphere collider cooking through the native
// FFI, sphere-on-sphere contact, and transform writeback through
// RapierWorld.interpolateTransforms.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _bootWorld({Vector3? gravity}) {
  final root = Node();
  final world = RapierWorld(gravity: gravity);
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('a dynamic sphere collides with a fixed sphere and settles', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    // Static floor (a huge sphere far below the origin acts as a
    // ground plane). Box cooking lands in the next commit.
    final floor = Node(
      localTransform: Matrix4.translation(Vector3(0, -100, 0)),
    );
    final floorBody = RapierRigidBody(type: BodyType.fixed);
    floor.addComponent(floorBody);
    floor.addComponent(RapierCollider(shape: SphereShape(radius: 100.0)));
    root.add(floor);
    floorBody.mount();
    floor.getComponents<RapierCollider>().first.mount();

    final ball = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
    final ballBody = RapierRigidBody(type: BodyType.dynamic_);
    ball.addComponent(ballBody);
    ball.addComponent(RapierCollider(shape: SphereShape(radius: 0.5)));
    root.add(ball);
    ballBody.mount();
    ball.getComponents<RapierCollider>().first.mount();

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

  test('interpolateTransforms snaps node.localTransform to the body pose', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    final ball = Node(localTransform: Matrix4.translation(Vector3(0, 10, 0)));
    final ballBody = RapierRigidBody(type: BodyType.dynamic_);
    ball.addComponent(ballBody);
    ball.addComponent(RapierCollider(shape: SphereShape(radius: 0.5)));
    root.add(ball);
    ballBody.mount();
    ball.getComponents<RapierCollider>().first.mount();

    for (var i = 0; i < 30; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(0);

    final pos = ball.localTransform.getTranslation();
    expect(pos.y, lessThan(10.0));
    expect(pos.y, closeTo(ballBody.readNativeTranslation().y, 1e-5));
  });

  test('writeback leaves a fixed body node alone', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    final start = Matrix4.translation(Vector3(1, 2, 3));
    final node = Node(localTransform: start.clone());
    final rb = RapierRigidBody(type: BodyType.fixed);
    node.addComponent(rb);
    node.addComponent(RapierCollider(shape: SphereShape(radius: 1)));
    root.add(node);
    rb.mount();
    node.getComponents<RapierCollider>().first.mount();

    for (var i = 0; i < 30; i++) {
      world.step(1.0 / 60.0);
    }
    world.interpolateTransforms(0);

    final t = node.localTransform.getTranslation();
    expect(t.x, closeTo(1, 1e-5));
    expect(t.y, closeTo(2, 1e-5));
    expect(t.z, closeTo(3, 1e-5));
  });

  test('RapierCollider without a sibling body throws', () {
    final root = _bootWorld();
    final node = Node();
    final collider = RapierCollider(shape: SphereShape(radius: 1));
    node.addComponent(collider);
    root.add(node);
    expect(collider.mount, throwsStateError);
  });

  test('non-sphere shapes throw UnimplementedError', () {
    final root = _bootWorld();
    final node = Node();
    final rb = RapierRigidBody(type: BodyType.dynamic_);
    node.addComponent(rb);
    node.addComponent(
      RapierCollider(shape: BoxShape(halfExtents: Vector3(1, 1, 1))),
    );
    root.add(node);
    rb.mount();
    final collider = node.getComponents<RapierCollider>().first;
    expect(collider.mount, throwsUnimplementedError);
  });
}
