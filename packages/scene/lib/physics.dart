/// The engine-agnostic physics contract.
///
/// The backend-driver interface ([PhysicsSimulation]), collision shapes,
/// materials, joint descriptions, pose seam, queries, and the pure-Dart
/// [BasicSimulation]. Physics engines (rapier, box3d, future backends)
/// implement this; renderers and servers drive it. Pure Dart, optional,
/// import it only when a build needs physics.
library;

export 'src/physics/basic_simulation.dart' show BasicSimulation;
export 'src/physics/joint_desc.dart'
    show
        FixedJointDesc,
        GenericJointDesc,
        JointAxis,
        JointAxisConfig,
        JointAxisMotion,
        JointDesc,
        JointMotor,
        JointMotorModel,
        PrismaticJointDesc,
        RevoluteJointDesc,
        SphericalJointDesc;
export 'src/physics/material.dart' show CombineRule, PhysicsMaterial;
export 'src/physics/pose_target.dart' show PoseTarget, SimplePoseTarget;
export 'src/physics/shape.dart'
    show
        BoxShape,
        CapsuleShape,
        CompoundChild,
        CompoundShape,
        ConvexHullShape,
        CylinderShape,
        HeightFieldShape,
        Shape,
        SphereShape,
        TriMeshShape;
export 'src/physics/shape_queries.dart'
    show
        aabbRaycast,
        RayShapeHit,
        rayHitsShape,
        shapesOverlap,
        shapeWorldAabb,
        sphereOverlapsAabb,
        sphereOverlapsSphere;
export 'src/physics/sim_types.dart'
    show
        BodyType,
        CharacterMovement,
        ContactPoint,
        SimCollisionBegan,
        SimCollisionEnded,
        SimCollisionEvent,
        SimOverlapHit,
        SimRaycastHit,
        SimShapeCastHit,
        SimTriggerEntered,
        SimTriggerExited;
export 'src/physics/simulation.dart' show PhysicsSimulation;
