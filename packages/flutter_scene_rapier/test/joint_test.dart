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
  final world = PhysicsWorld(
    RapierWorld(gravity: gravity ?? Vector3(0, -9.81, 0)),
  );
  root.addComponent(world);
  world.mount();
  return root;
}

(Node, RigidBody) _body(
  Node root,
  Vector3 position,
  BodyType type, {
  double? mass,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  final body = RigidBody(type: type, mass: mass);
  node.addComponent(body);
  // A collider gives the body mass/inertia for the dynamic cases.
  node.addComponent(Collider(shape: SphereShape(radius: 0.5)));
  root.add(node);
  body.mount();
  node.getComponents<Collider>().first.mount();
  return (node, body);
}

void main() {
  test('a fixed joint holds two bodies at a constant offset', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    // Anchor body is fixed; the second body would fall without the
    // joint. The joint welds them, so the second body stays put.
    final (anchorNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (hangNode, hangBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    final joint = FixedJoint(
      otherNode: anchorNode,
      localAnchorA: Vector3.zero(),
      localAnchorB: Vector3(2, 0, 0),
    );
    hangNode.addComponent(joint);
    joint.mount();

    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }

    final p = hangBody.readSimulationPose().$1;
    // Welded to a fixed anchor: it should barely move from (2, 5, 0).
    expect(p.x, closeTo(2.0, 0.2));
    expect(p.y, closeTo(5.0, 0.2));
  });

  test('a revolute joint keeps the body at a fixed radius from the hinge', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    // Hinge at the origin (fixed body); the arm hangs 2 units along +X
    // and swings down about the Z axis under gravity.
    final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (armNode, armBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    final joint = RevoluteJoint(
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

    final p = armBody.readSimulationPose().$1;
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
      final world = root.getComponent<PhysicsWorld>()!;
      final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
      final (armNode, armBody) = _body(
        root,
        Vector3(2, 5, 0),
        BodyType.dynamic_,
        mass: 1,
      );
      final joint = RevoluteJoint(
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
        final y = armBody.readSimulationPose().$1.y;
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
    final world = root.getComponent<PhysicsWorld>()!;

    final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (armNode, armBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    // A strong positive-velocity motor should rotate the arm up and
    // around rather than letting it hang straight down.
    final joint = RevoluteJoint(
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
      final y = armBody.readSimulationPose().$1.y;
      if (y > maxHeight) maxHeight = y;
    }

    // The motor should carry the arm above the hinge height at some
    // point in the rotation.
    expect(maxHeight, greaterThan(5.5));
  });

  test('a prismatic joint confines motion to its axis', () {
    final root = _boot(gravity: Vector3(0, -9.81, 0));
    final world = root.getComponent<PhysicsWorld>()!;

    // Rail anchor (fixed) up top; the slider hangs below it on a
    // vertical axis. The slider may only translate along Y, so gravity
    // drags it straight down with no lateral drift. The two bodies
    // carry no colliders, so there is nothing to interpenetrate.
    final railNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
    );
    railNode.addComponent(RigidBody(type: BodyType.fixed));
    root.add(railNode);
    railNode.getComponents<RigidBody>().first.mount();

    final sliderNode = Node(
      localTransform: Matrix4.translation(Vector3(0, 4, 0)),
    );
    final sliderBody = RigidBody(type: BodyType.dynamic_, mass: 1);
    sliderNode.addComponent(sliderBody);
    root.add(sliderNode);
    sliderBody.mount();

    final joint = PrismaticJoint(
      otherNode: railNode,
      axis: Vector3(0, 1, 0),
      localAnchorA: Vector3.zero(),
      localAnchorB: Vector3.zero(),
    );
    sliderNode.addComponent(joint);
    joint.mount();

    final startY = sliderBody.readSimulationPose().$1.y;
    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }

    final p = sliderBody.readSimulationPose().$1;
    expect(p.y, lessThan(startY - 1.0)); // slid down the axis
    expect(p.x.abs(), lessThan(1e-3)); // no lateral drift
    expect(p.z.abs(), lessThan(1e-3));
  });

  test('a world-anchored fixed joint pins a body in place', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    // A dynamic body that would fall under gravity, welded to the world
    // (null otherNode) at its starting position. The B-side anchor is in
    // world space because the implicit anchor sits at the origin.
    final (node, body) = _body(
      root,
      Vector3(3, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );
    final joint = FixedJoint(
      localAnchorA: Vector3.zero(),
      localAnchorB: Vector3(3, 5, 0),
    );
    node.addComponent(joint);
    joint.mount();

    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }

    final p = body.readSimulationPose().$1;
    // Held against gravity by the world anchor: it stays near (3, 5, 0).
    expect(p.x, closeTo(3.0, 0.2));
    expect(p.y, closeTo(5.0, 0.2));
  });

  test('setting a revolute motor after mount takes effect live', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (armNode, armBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    // No motor at first: the arm just hangs and swings down.
    final joint = RevoluteJoint(
      otherNode: hingeNode,
      axis: Vector3(0, 0, 1),
      localAnchorA: Vector3(-2, 0, 0),
      localAnchorB: Vector3.zero(),
    );
    armNode.addComponent(joint);
    joint.mount();
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(armBody.readSimulationPose().$1.y, lessThan(5.0));

    // Turn the motor on after mount; the change must reach the native
    // joint and drive the arm above the hinge.
    joint.motorTargetVelocity = 6.0;
    joint.motorMaxForce = 1000.0;

    var maxHeight = -double.infinity;
    for (var i = 0; i < 180; i++) {
      world.step(1.0 / 60.0);
      final y = armBody.readSimulationPose().$1.y;
      if (y > maxHeight) maxHeight = y;
    }
    expect(maxHeight, greaterThan(5.5));
  });

  test('a generic joint spring motor holds the arm against gravity', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (armNode, armBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    // A hinge about Z (all axes locked except angular-Z) with a stiff
    // positional spring toward its zero (horizontal) angle. The spring
    // should hold the arm near horizontal rather than letting gravity
    // swing it down.
    final joint = GenericJoint(
      otherNode: hingeNode,
      localAnchorA: Vector3(-2, 0, 0),
      localAnchorB: Vector3.zero(),
      axes: {
        JointAxis.linearX: const JointAxisConfig.locked(),
        JointAxis.linearY: const JointAxisConfig.locked(),
        JointAxis.linearZ: const JointAxisConfig.locked(),
        JointAxis.angularX: const JointAxisConfig.locked(),
        JointAxis.angularY: const JointAxisConfig.locked(),
        JointAxis.angularZ: const JointAxisConfig.free(
          motor: JointMotor(
            targetPosition: 0,
            stiffness: 2000,
            damping: 100,
            maxForce: 100000,
          ),
        ),
      },
    );
    armNode.addComponent(joint);
    joint.mount();

    for (var i = 0; i < 180; i++) {
      world.step(1.0 / 60.0);
    }

    final p = armBody.readSimulationPose().$1;
    // Held near its horizontal start by the spring, still at radius ~2.
    expect(p.y, greaterThan(4.6));
    expect((p - Vector3(0, 5, 0)).length, closeTo(2.0, 0.2));
  });

  test('setAxisConfig frees a locked axis live', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;

    final (hingeNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (armNode, armBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );

    // Every axis locked: the arm is welded horizontal and stays put.
    final joint = GenericJoint(
      otherNode: hingeNode,
      localAnchorA: Vector3(-2, 0, 0),
      localAnchorB: Vector3.zero(),
      axes: {
        for (final axis in JointAxis.values)
          axis: const JointAxisConfig.locked(),
      },
    );
    armNode.addComponent(joint);
    joint.mount();
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(armBody.readSimulationPose().$1.y, closeTo(5.0, 0.2));

    // Free the hinge axis after mount: the arm should now swing down.
    joint.setAxisConfig(JointAxis.angularZ, const JointAxisConfig.free());
    for (var i = 0; i < 150; i++) {
      world.step(1.0 / 60.0);
    }
    expect(armBody.readSimulationPose().$1.y, lessThan(4.3));
  });

  test('a joint without a sibling body throws', () {
    final root = _boot();
    final (otherNode, _) = _body(root, Vector3.zero(), BodyType.fixed);

    final node = Node();
    final joint = FixedJoint(otherNode: otherNode);
    node.addComponent(joint);
    root.add(node);
    expect(joint.mount, throwsStateError);
  });

  test('onUnmount releases the constraint', () {
    final root = _boot();
    final world = root.getComponent<PhysicsWorld>()!;
    final (anchorNode, _) = _body(root, Vector3(0, 5, 0), BodyType.fixed);
    final (hangNode, hangBody) = _body(
      root,
      Vector3(2, 5, 0),
      BodyType.dynamic_,
      mass: 1,
    );
    final joint = FixedJoint(
      otherNode: anchorNode,
      localAnchorB: Vector3(2, 0, 0),
    );
    hangNode.addComponent(joint);
    joint.mount();

    // Welded to the fixed anchor, the body holds its height.
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(hangBody.readSimulationPose().$1.y, closeTo(5.0, 0.2));

    // Unmounting destroys the native joint, so gravity takes over.
    joint.unmount();
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(hangBody.readSimulationPose().$1.y, lessThan(4.0));
  });
}
