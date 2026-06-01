/// Rapier 3D physics backend for flutter_scene.
///
/// Implements the abstract [PhysicsWorld], [RigidBody], and [Collider]
/// contract from `package:flutter_scene` against the Rapier 3D physics
/// engine. Construct a [RapierWorld] and attach it to your scene root;
/// then attach [RapierRigidBody] and [RapierCollider] components to
/// nodes that should participate in the simulation.
///
/// Body lifecycle, force / impulse application, the full Shape
/// hierarchy, axis locks, sleeping, kinematic transform sync,
/// interpolated transform writeback, scene queries (raycast, overlap,
/// shape cast), collision / trigger events, the fixed, spherical,
/// revolute, prismatic, and generic (6DOF) joints, and a kinematic
/// character controller all run through the native shim.
library;

export 'src/rapier_character_controller.dart';
export 'src/rapier_collider.dart';
export 'src/rapier_joint.dart';
export 'src/rapier_rigid_body.dart';
export 'src/rapier_world.dart';
