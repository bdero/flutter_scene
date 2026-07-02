/// box3d physics backend for flutter_scene.
///
/// Implements the abstract [PhysicsWorld], [RigidBody], and [Collider]
/// contract from `package:flutter_scene` against the box3d engine. Construct
/// a [Box3dPhysicsWorld] and attach it to your scene root, then attach
/// [Box3dRigidBody] and [Box3dCollider] components to nodes that should
/// participate in the simulation.
///
/// The scene advances physics on a fixed timestep and interpolates dynamic
/// body transforms for rendering. Rigid bodies, the full shape hierarchy,
/// axis locks, sleeping, kinematic transform sync, scene queries (raycast,
/// overlap, shape cast), and contact / trigger events all run through
/// box3d. Await [Box3dPhysicsWorld.ensureInitialized] once before creating a
/// world.
library;

export 'src/box3d_collider.dart';
export 'src/box3d_joint.dart';
export 'src/box3d_physics_world.dart' show Box3dPhysicsWorld;
export 'src/box3d_rigid_body.dart';
