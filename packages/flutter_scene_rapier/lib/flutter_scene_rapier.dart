/// Rapier 3D physics backend for the `scene` physics contract.
///
/// Implements [PhysicsSimulation] from `package:scene` against the
/// Rapier 3D physics engine. Construct a [RapierWorld] and hand it to
/// whatever drives the contract, in flutter_scene that is
/// `PhysicsWorld(RapierWorld())` attached to the scene root, with the
/// generic `RigidBody`, `Collider`, joint, and character-controller
/// components on descendant nodes.
///
/// Body lifecycle, force / impulse application, the full Shape
/// hierarchy, axis locks, sleeping, kinematic target poses,
/// interpolated pose writeback, scene queries (raycast, overlap, shape
/// cast), collision / trigger events, the fixed, spherical, revolute,
/// prismatic, and generic (6DOF) joints, and a kinematic character
/// controller all run through the native shim.
library;

export 'src/rapier_world.dart' show RapierWorld;
