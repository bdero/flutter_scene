// Stage 4 commit N: interpolateTransforms blends between the previous
// and current physics steps using the alpha residual.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

(RapierWorld, RapierRigidBody, Node) _boot({Vector3? velocity}) {
  final root = Node();
  final world = RapierWorld(gravity: Vector3.zero());
  root.addComponent(world);
  world.mount();

  final ballNode = Node();
  final ball = RapierRigidBody(
    type: BodyType.dynamic_,
    mass: 1.0,
    linearVelocity: velocity ?? Vector3(1, 0, 0),
  );
  ballNode.addComponent(ball);
  root.add(ballNode);
  ball.mount();
  return (world, ball, ballNode);
}

void main() {
  test('alpha 0 yields the previous-step pose', () {
    final (world, ball, node) = _boot();
    // Two steps so prev != curr.
    world.step(1.0 / 60.0);
    world.step(1.0 / 60.0);
    world.interpolateTransforms(0);
    // After two 1/60s steps at v=1, body is at x ≈ 2/60. Previous
    // step's curr was at 1/60.
    expect(node.localTransform.getTranslation().x, closeTo(1.0 / 60.0, 1e-4));
  });

  test('alpha 1 yields the current-step pose', () {
    final (world, ball, node) = _boot();
    world.step(1.0 / 60.0);
    world.step(1.0 / 60.0);
    world.interpolateTransforms(1.0);
    expect(node.localTransform.getTranslation().x, closeTo(2.0 / 60.0, 1e-4));
  });

  test('alpha 0.5 yields the midpoint translation', () {
    final (world, ball, node) = _boot();
    world.step(1.0 / 60.0);
    world.step(1.0 / 60.0);
    world.interpolateTransforms(0.5);
    expect(node.localTransform.getTranslation().x, closeTo(1.5 / 60.0, 1e-4));
  });

  test('rotation slerps along the shortest arc', () {
    final (world, ball, node) = _boot(velocity: Vector3.zero());
    // Need a collider for inertia so angular velocity actually
    // changes the rotation.
    final colliderNode = ball.node;
    colliderNode.addComponent(RapierCollider(shape: SphereShape(radius: 1)));
    colliderNode.getComponents<RapierCollider>().first.mount();
    ball.angularVelocity = Vector3(0, 1.0, 0);

    world.step(1.0 / 60.0);
    world.step(1.0 / 60.0);
    world.interpolateTransforms(0.5);

    // After two 1/60s steps at omega=1 rad/s, total rotation ≈ 2/60
    // rad about Y. Midpoint should be about 1.5/60 rad.
    final rot = Quaternion.fromRotation(node.localTransform.getRotation());
    // Extract Y-axis rotation: 2 * atan2(y, w). For small angles, y ≈
    // angle/2.
    final angleY = 2.0 * (rot.y / rot.w).abs();
    expect(angleY, closeTo(1.5 / 60.0, 5e-3));
  });
}
