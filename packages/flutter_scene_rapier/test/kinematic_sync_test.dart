// Kinematic body transform sync. The user moves the owning node each
// frame; fixedUpdate pushes the new pose to Rapier via
// set_next_kinematic_position so dynamic bodies in contact are pushed
// along.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _bootZeroGravity() {
  final root = Node();
  final world = PhysicsWorld(RapierWorld(gravity: Vector3.zero()));
  root.addComponent(world);
  world.mount();
  return root;
}

void _stepWithFixedUpdate(Node root, PhysicsWorld world, double dt) {
  root.sceneFixedPass(dt);
  world.step(dt);
}

void main() {
  test('moving a kinematic body node updates the native body', () async {
    final root = _bootZeroGravity();
    final world = root.getComponent<PhysicsWorld>()!;

    final node = Node(localTransform: Matrix4.translation(Vector3.zero()));
    final body = RigidBody(type: BodyType.kinematic);
    node.addComponent(body);
    root.add(node);
    body.mount();
    // Let onLoad resolve so fixedUpdate fires through sceneFixedPass.
    await Future<void>.delayed(Duration.zero);

    expect(body.readSimulationPose().$1.y, closeTo(0.0, 1e-5));

    node.localTransform = Matrix4.translation(Vector3(0, 3, 0));
    _stepWithFixedUpdate(root, world, 1.0 / 60.0);

    expect(body.readSimulationPose().$1.y, closeTo(3.0, 1e-3));
  });

  test('kinematic body pushes a dynamic ball it contacts', () async {
    final root = _bootZeroGravity();
    final world = root.getComponent<PhysicsWorld>()!;

    // Kinematic paddle below the dynamic ball.
    final paddleNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 0, 0)),
    );
    final paddle = RigidBody(type: BodyType.kinematic);
    paddleNode.addComponent(paddle);
    paddleNode.addComponent(
      Collider(shape: BoxShape(halfExtents: Vector3(2, 0.25, 2))),
    );
    root.add(paddleNode);
    paddle.mount();
    paddleNode.getComponents<Collider>().first.mount();

    // Dynamic ball resting just above the paddle.
    final ballNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 1.0, 0)),
    );
    final ball = RigidBody(type: BodyType.dynamic_, mass: 1.0);
    ballNode.addComponent(ball);
    ballNode.addComponent(Collider(shape: SphereShape(radius: 0.5)));
    root.add(ballNode);
    ball.mount();
    ballNode.getComponents<Collider>().first.mount();
    await Future<void>.delayed(Duration.zero);

    // Move the paddle upward over a series of steps. The dynamic ball
    // should ride it up.
    for (var i = 0; i < 30; i++) {
      paddleNode.localTransform = Matrix4.translation(
        Vector3(0, (i + 1) * 0.1, 0),
      );
      _stepWithFixedUpdate(root, world, 1.0 / 60.0);
    }

    expect(ball.readSimulationPose().$1.y, greaterThan(2.5));
  });
}
