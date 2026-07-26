/// Physics for flutter_scene, an optional pluggable-backend contract.
///
/// The generic scene-graph components ([PhysicsWorld], [RigidBody],
/// [Collider], the joints, [KinematicCharacterController]) plus the
/// re-exported `scene` contract they drive. Attach a backend, `PhysicsWorld(
/// RapierWorld())` from `package:flutter_scene_rapier`, or `BasicSimulation()`
/// for pure-Dart queries and triggers. Import this only when a build needs
/// physics; the core `package:flutter_scene/scene.dart` does not carry it.
///
/// For a backend feature beyond the shared contract, downcast
/// [PhysicsWorld.simulation] and drive it by [RigidBody.handle] /
/// [Collider.handles] / [Joint.handle]; the components are subclassable for
/// typed backend companions.
library;

export 'package:scene/physics.dart'
    show
        BasicSimulation,
        BodyType,
        BoxShape,
        CapsuleShape,
        CharacterMovement,
        CombineRule,
        CompoundChild,
        CompoundShape,
        ConvexHullShape,
        CylinderShape,
        HeightFieldShape,
        JointAxis,
        JointAxisConfig,
        JointAxisMotion,
        JointMotor,
        JointMotorModel,
        PhysicsMaterial,
        PhysicsSimulation,
        PoseTarget,
        Shape,
        SimplePoseTarget,
        SphereShape,
        TriMeshShape;
export 'src/physics/character_controller.dart'
    show KinematicCharacterController;
export 'src/physics/collider.dart' show Collider;
export 'src/physics/events.dart'
    show
        CollisionBegan,
        CollisionEnded,
        CollisionEvent,
        ContactPoint,
        TriggerEntered,
        TriggerExited;
export 'src/physics/joint.dart'
    show
        FixedJoint,
        GenericJoint,
        Joint,
        PrismaticJoint,
        RevoluteJoint,
        SphericalJoint;
export 'src/physics/physics_world.dart'
    show NodePoseTarget, PhysicsWorld, findAncestorWorld;
export 'src/physics/queries.dart' show OverlapHit, RaycastHit, ShapeCastHit;
export 'src/physics/rigid_body.dart' show RigidBody;
