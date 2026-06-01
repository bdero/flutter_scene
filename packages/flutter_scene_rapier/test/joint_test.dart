// Concrete Rapier joints: fixed weld, revolute hinge (with limits and
// a motor), and prismatic slider.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _boot({Vector3? gravity}) {
  final root = Node();
  final world = RapierWorld(gravity: gravity ?? Vector3(0, -9.81, 0));
  root.addComponent(world);
  world.mount();
  return root;
}

(Node, RapierRigidBody) _body(
  Node root,
  Vector3 position,
  BodyType type, {
  double? mass,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  final body = RapierRigidBody(type: type, mass: mass);
  node.addComponent(body);
  // A collider gives the body mass/inertia for the dynamic cases.
  node.addComponent(RapierCollider(shape: SphereShape(radius: 0.5)));
  root.add(node);
  body.mount();
  node.getComponents<RapierCollider>().first.mount();
  return (node, body);
}

void main() {
  test('a fixed joint holds two bodies at a constant offset', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    // Anchor body is fixed; the second body would fall without the
    // joint. The joint welds them, so the second body stays put.
    final (anchorNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (hangNode, hangBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    final joint = RapierFixedJoint(
      otherNode: anchorNode,
      localAnchorA: Vector3.zero(),
      localAnchorB: Vector3(2, 0, 0),
    );
    hangNode.addComponent(joint);
    joint.mount();

    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }

    final p = hangBody.readNativeTranslation();
    // Welded to a fixed anchor: it should barely move from (2, 5, 0).
    expect(p.x, closeTo(2.0, 0.2));
    expect(p.y, closeTo(5.0, 0.2));
  });

  test('a revolute joint keeps the body at a fixed radius from the hinge', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    // Hinge at the origin (fixed body); the arm hangs 2 units along +X
    // and swings down about the Z axis under gravity.
    final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (armNode, armBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    final joint = RapierRevoluteJoint(
      otherNode: hingeNode,
      axis: Vector3(0, 0, 1),
      localAnchorA: Vector3(-2, 0, 0),
      localAnchorB: Vector3.zero(),
    );
    armNode.addComponent(joint);
    joint.mount();

    for (var i = 0; i < 180; i++) {
      world.step(1.0 / 60.0);
    }

    final p = armBody.readNativeTranslation();
    // Distance from the hinge (at 0,5,0) should remain ~2.
    final radius = (p - Vector3(0, 5, 0)).length;
    expect(radius, closeTo(2.0, 0.2));
    // It should have swung downward from its starting height.
    expect(p.y, lessThan(4.5));
  });

  test('a revolute limit confines the hinge to a narrow swing band', () {
    // A tight angular limit pins the arm to a small wedge around the
    // joint's zero angle, so its vertical travel stays small. An
    // unconstrained hinge, by contrast, swings as a full pendulum and
    // sweeps a large vertical range. Comparing the two ranges proves
    // the limit constrains the free axis without depending on where
    // Rapier places the zero-angle reference.
    double swingRange({double? lower, double? upper}) {
      final root = _boot();
      final world = root.getComponent<RapierWorld>()!;
      final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
      final (armNode, armBody) = _body(
        root,
        Vector3(2, 5, 0),
        BodyType.dynamic_,
        mass: 1,
      );
      final joint = RapierRevoluteJoint(
        otherNode: hingeNode,
        axis: Vector3(0, 0, 1),
        localAnchorA: Vector3(-2, 0, 0),
        localAnchorB: Vector3.zero(),
        lowerLimit: lower,
        upperLimit: upper,
      );
      armNode.addComponent(joint);
      joint.mount();

      var minY = double.infinity;
      var maxY = -double.infinity;
      for (var i = 0; i < 240; i++) {
        world.step(1.0 / 60.0);
        final y = armBody.readNativeTranslation().y;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      return maxY - minY;
    }

    final limited = swingRange(lower: -0.2, upper: 0.2);
    final free = swingRange();
    // The free pendulum sweeps roughly the arm length (~2+ units); the
    // limited hinge should travel a small fraction of that.
    expect(limited, lessThan(1.0));
    expect(free, greaterThan(limited * 2));
  });

  test('a revolute motor drives the arm against gravity', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (armNode, armBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    // A strong positive-velocity motor should rotate the arm up and
    // around rather than letting it hang straight down.
    final joint = RapierRevoluteJoint(
      otherNode: hingeNode,
      axis: Vector3(0, 0, 1),
      localAnchorA: Vector3(-2, 0, 0),
      localAnchorB: Vector3.zero(),
      motorTargetVelocity: 6.0,
      motorMaxForce: 1000.0,
    );
    armNode.addComponent(joint);
    joint.mount();

    var maxHeight = -double.infinity;
    for (var i = 0; i < 180; i++) {
      world.step(1.0 / 60.0);
      final y = armBody.readNativeTranslation().y;
      if (y > maxHeight) maxHeight = y;
    }

    // The motor should carry the arm above the hinge height at some
    // point in the rotation.
    expect(maxHeight, greaterThan(5.5));
  });

  test('a prismatic joint confines motion to its axis', () {
    final root = _boot(gravity: Vector3(0, -9.81, 0));
    final world = root.getComponent<RapierWorld>()!;

    // Rail anchor (fixed) up top; the slider hangs below it on a
    // vertical axis. The slider may only translate along Y, so gravity
    // drags it straight down with no lateral drift. The two bodies
    // carry no colliders, so there is nothing to interpenetrate.
    final railNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    railNode.addComponent(RapierRigidBody(type: BodyType.fixed));
    root.add(railNode);
    railNode.getComponents<RapierRigidBody>().first.mount();

    final sliderNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 4, 0)),
    );
    final sliderBody = RapierRigidBody(type: BodyType.dynamic_, mass: 1);
    sliderNode.addComponent(sliderBody);
    root.add(sliderNode);
    sliderBody.mount();

    final joint = RapierPrismaticJoint(
      otherNode: railNode,
      axis: Vector3(0, 1, 0),
      localAnchorA: Vector3.zero(),
      localAnchorB: Vector3.zero(),
    );
    sliderNode.addComponent(joint);
    joint.mount();

    final startY = sliderBody.readNativeTranslation().y;
    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }

    final p = sliderBody.readNativeTranslation();
    expect(p.y, lessThan(startY - 1.0)); // slid down the axis
    expect(p.x.abs(), lessThan(1e-3)); // no lateral drift
    expect(p.z.abs(), lessThan(1e-3));
  });

  test('a joint without a sibling body throws', () {
    final root = _boot();
    final (otherNode, _) = _body(root, Vector3.zero(), BodyType.fixed);

    final node = Node();
    final joint = RapierFixedJoint(otherNode: otherNode);
    node.addComponent(joint);
    root.add(node);
    expect(joint.mount, throwsStateError);
  });

  test('onUnmount removes the joint handle', () {
    final root = _boot();
    final (anchorNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (hangNode, _) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );
    final joint = RapierFixedJoint(otherNode: anchorNode);
    hangNode.addComponent(joint);
    joint.mount();
    expect(joint.nativeHandle, isNotNull);

    joint.unmount();
    expect(joint.nativeHandle, isNull);
  });
}
