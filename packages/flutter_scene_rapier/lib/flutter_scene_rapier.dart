/// Rapier 3D physics backend for flutter_scene.
///
/// Implements the abstract [PhysicsWorld], [RigidBody], and [Collider]
/// contract from `package:flutter_scene` against the Rapier 3D physics
/// engine. Construct a [RapierWorld] and attach it to your scene root;
/// then attach [RapierRigidBody] and [RapierCollider] components to
/// nodes that should participate in the simulation.
///
/// This is the Stage 3 scaffold: the classes exist and satisfy the
/// abstract API, but the simulation step, scene queries, and event
/// streams are not yet wired through to the native engine. Stages 4
/// and 5 land that work.
library;

export 'src/rapier_collider.dart';
export 'src/rapier_rigid_body.dart';
export 'src/rapier_world.dart';
