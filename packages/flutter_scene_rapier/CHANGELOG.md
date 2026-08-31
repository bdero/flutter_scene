## 0.5.2

* Triangle mesh colliders are cooked with merged duplicate vertices and fixed internal edges, so a character crossing imported terrain stops catching on the seams between triangles.
* Requires rebuilt binaries and wasm; the 0.5.0 prebuilts carry the old shape construction.

## 0.5.1

* Widen the `scene` constraint to `^0.3.0`. No native changes; a release reuses the 0.5.0 binaries and wasm.

## 0.5.0

* BREAKING: `RapierWorld.snapshot` wraps the native payload in an envelope carrying the body set it captured, so snapshots taken by 0.4.0 no longer restore.
* `RapierWorld.restore` reconciles its body registry against the restored world. A body created after the snapshot stops being driven, and one destroyed after it is removed rather than left simulating with no pose target.
* No native changes; reuses the 0.4.0 prebuilt binaries and wasm.

## 0.4.0

* Requires the scene 0.1.1 physics contract.
* `RapierWorld.snapshot`/`restore`, full world serialization for rollback prediction and lag-compensation rewind, on native and web.
* `RapierWorld.setBodyPose`, immediate body teleport for rollback correction.
* Ships new native binaries and wasm (new `fsr_world_snapshot`/`fsr_world_restore`/`fsr_body_set_pose` exports).

## 0.3.0

* Requires flutter_scene 0.20.0.
* BREAKING: implements the `scene` package's `PhysicsSimulation` contract and no longer depends on Flutter, so the simulation runs headless. Drive it with the generic `PhysicsWorld(RapierWorld())`, `RigidBody`, and `Collider` from flutter_scene; the backend-specific `Rapier*` component classes are removed.
* No native changes; reuses the 0.1.0 prebuilt binaries and wasm.

## 0.2.2

* Requires flutter_scene 0.19.0.
* No native changes; this release reuses the 0.1.0 prebuilt binaries and wasm.

## 0.2.1

* Requires flutter_scene 0.18.0.
* No native changes; this release reuses the 0.1.0 prebuilt binaries and wasm.

## 0.2.0

* Requires flutter_scene 0.17.0.
* No native changes; this release reuses the 0.1.0 prebuilt binaries and wasm.

## 0.1.0

First public release. A Rapier 3D physics backend for flutter_scene,
implementing the abstract physics contract added in flutter_scene 0.16.0.

* Rigid bodies (`RapierRigidBody`): fixed, kinematic, and dynamic, with
  mass, damping, axis locks, velocities, impulses/forces, and runtime body
  type changes.
* Colliders (`RapierCollider`) for box, sphere, capsule, cylinder, convex
  hull, triangle mesh, height field, and compound shapes, with friction,
  restitution, collision groups, and sensor (trigger) support.
* Joints: fixed, spherical, revolute, prismatic, and a fully configurable
  6-DOF generic joint, with limits and motors.
* A kinematic character controller
  (`RapierKinematicCharacterController.move`) with move-and-slide, slope
  handling, autostep, snap-to-ground, and optional pushing of dynamic
  bodies.
* Scene queries: raycast, shape cast, and sphere/box overlap, plus a
  collision/trigger event stream.
* Fixed-timestep stepping with transform interpolation, driven
  automatically by the scene.
* Precompiled native libraries downloaded per release (no Rust toolchain
  needed) with a source-build fallback, and a WebAssembly backend for the
  web.
