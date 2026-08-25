## 0.2.1

* Widen the `scene` constraint to `^0.3.0`. No API changes.

## 0.2.0

* BREAKING: the backend now implements the `PhysicsSimulation` contract from `package:scene`; the runtime dependency moved from `flutter_scene` to `scene`.
* BREAKING: removed the `Box3dRigidBody`, `Box3dCollider`, and `Box3dJoint` types; construct only `Box3dPhysicsWorld` and attach flutter_scene's generic `RigidBody`, `Collider`, and joint components.
* BREAKING: wrap the world in flutter_scene's `PhysicsWorld` now, `PhysicsWorld(Box3dPhysicsWorld(...))`, instead of adding the concrete components directly.
* Require `box3d` `^0.1.1` for the Android native load fix.

## 0.1.0

- Initial release. Implements the physics simulation contract from
  `package:scene` against box3d: rigid bodies, colliders (sphere, box,
  capsule, cylinder, convex hull, triangle mesh, height field, compound),
  fixed/spherical/revolute/prismatic joints, scene queries, and
  contact/trigger events. The generic 6-DOF joint, character controller,
  and explicit mass override are not yet wired up.
