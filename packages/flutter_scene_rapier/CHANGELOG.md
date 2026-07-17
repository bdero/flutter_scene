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
