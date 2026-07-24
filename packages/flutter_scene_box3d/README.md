# flutter_scene_box3d

A [box3d](https://github.com/erincatto/box3d) physics backend for
[flutter_scene](https://pub.dev/packages/flutter_scene). It implements the
`PhysicsSimulation` contract from `package:scene` (rigid bodies, colliders,
joints, queries, and collision events) against the box3d engine, through
the engine-agnostic [box3d](https://pub.dev/packages/box3d) Dart package.

> **Status: experimental.** The API may change between releases.

## Quick start

Wrap a `Box3dPhysicsWorld` in flutter_scene's `PhysicsWorld` component on
the scene root, then attach `RigidBody` and `Collider` components to the
nodes you want simulated (the body must be added before the collider). The
scene advances physics on a fixed timestep and interpolates transforms for
you.

```dart
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_box3d/flutter_scene_box3d.dart';
import 'package:vector_math/vector_math.dart';

await Box3dPhysicsWorld.ensureInitialized();

final scene = Scene();
final world = PhysicsWorld(Box3dPhysicsWorld(gravity: Vector3(0, -9.81, 0)));
scene.root.addComponent(world);

// A static floor.
final floor = Node(localTransform: Matrix4.translation(Vector3(0, -0.5, 0)));
floor.addComponent(RigidBody(type: BodyType.fixed));
floor.addComponent(Collider(shape: BoxShape(halfExtents: Vector3(10, 0.5, 10))));
scene.add(floor);

// A falling dynamic box.
final box = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
box.addComponent(RigidBody(type: BodyType.dynamic_));
box.addComponent(Collider(shape: BoxShape(halfExtents: Vector3.all(0.5))));
scene.add(box);

world.collisions.listen((event) {
  // CollisionBegan / CollisionEnded / TriggerEntered / TriggerExited
});
```

Each frame, advance and render the scene:

```dart
scene.update(deltaSeconds); // steps physics + interpolates
scene.render(camera, canvas, viewport: Offset.zero & size);
```

Scene queries run through `world.raycast`, `world.raycastAll`,
`world.overlapSphere`, `world.overlapBox`, and `world.shapeCast`.

## Supported shapes

Sphere, box, capsule, cylinder, convex hull, triangle mesh, height field,
and compound. A collider's `localPose` is baked into the shape geometry; a
non-identity pose on a cylinder or height field is not supported yet.

## Joints

Fixed, spherical, revolute, and prismatic joints are supported through the
flutter_scene joint components. box3d has no 6-DOF generic joint, so
`GenericJoint` throws `UnsupportedError`.

## Not yet implemented

The kinematic character controller and an explicit mass/inertia override
are not wired up yet (box3d derives mass from collider density). See the
`TODO` notes in the source.

## License

MIT (see `LICENSE`).
