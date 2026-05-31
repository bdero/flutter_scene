/// Rapier 3D physics backend for flutter_scene.
///
/// Implements the abstract [PhysicsWorld], [RigidBody], and [Collider]
/// contract from `package:flutter_scene` against the Rapier 3D physics
/// engine. Construct a [RapierWorld] and attach it to your scene root;
/// then attach [RapierRigidBody] and [RapierCollider] components to
/// nodes that should participate in the simulation.
///
/// Body lifecycle, force / impulse application, the full Shape
/// hierarchy, axis locks, sleeping, kinematic transform sync, and
/// interpolated transform writeback all run through the native shim.
///
/// TODO(scene-queries): the abstract scene-query surface
/// ([PhysicsWorld.raycast], [PhysicsWorld.overlapSphere], and the rest)
/// still throws [UnimplementedError]; wire it through Rapier's
/// QueryPipeline.
/// TODO(events): emit [CollisionBegan] / [CollisionEnded] /
/// [TriggerEntered] / [TriggerExited] on the [PhysicsWorld.collisions]
/// stream via Rapier's narrow-phase events.
/// TODO(joints): expose concrete subclasses of [FixedJoint],
/// [SphericalJoint], [RevoluteJoint], [PrismaticJoint], and
/// [GenericJoint] backed by Rapier's impulse-joint set.
library;

export 'src/rapier_collider.dart';
export 'src/rapier_rigid_body.dart';
export 'src/rapier_world.dart';
