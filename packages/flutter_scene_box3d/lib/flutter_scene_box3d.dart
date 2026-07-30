/// box3d physics backend for flutter_scene.
///
/// Implements the `PhysicsSimulation` contract from `package:scene` against
/// the box3d engine. Await [Box3dPhysicsWorld.ensureInitialized] once during
/// startup, then hand a [Box3dPhysicsWorld] to the engine's physics world
/// (`PhysicsWorld(Box3dPhysicsWorld())` in flutter_scene) and attach the
/// generic `RigidBody`, `Collider`, and joint components to nodes that
/// should participate in the simulation.
///
/// Rigid bodies, the full shape hierarchy, axis locks, sleeping, kinematic
/// pose targets, joints, queries (raycast, overlap, shape cast), and
/// contact/trigger events all run through box3d.
library;

export 'src/box3d_physics_world.dart' show Box3dPhysicsWorld;
