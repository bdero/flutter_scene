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
/// shape cast), and collision / trigger events all run through the
/// native shim.
///
/// TODO(joints): expose concrete subclasses of [FixedJoint],
/// [SphericalJoint], [RevoluteJoint], [PrismaticJoint], and
/// [GenericJoint] backed by Rapier's impulse-joint set.
library;

export 'src/rapier_collider.dart';
export 'src/rapier_rigid_body.dart';
export 'src/rapier_world.dart';
