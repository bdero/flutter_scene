import 'package:vector_math/vector_math.dart';

/// One of the six relative degrees of freedom a generic joint constrains.
enum JointAxis { linearX, linearY, linearZ, angularX, angularY, angularZ }

/// How a joint motor's strength is interpreted.
enum JointMotorModel { acceleration, force }

/// Drives a joint axis toward a target position and/or velocity.
class JointMotor {
  const JointMotor({
    this.targetPosition = 0,
    this.targetVelocity = 0,
    this.stiffness = 0,
    this.damping = 0,
    this.maxForce = double.infinity,
    this.model = JointMotorModel.acceleration,
  });

  final double targetPosition;
  final double targetVelocity;
  final double stiffness;
  final double damping;
  final double maxForce;
  final JointMotorModel model;
}

enum JointAxisMotion { locked, free, limited }

/// Motion allowance for one axis of a generic joint.
class JointAxisConfig {
  const JointAxisConfig.locked() : this._(JointAxisMotion.locked, 0, 0, null);

  const JointAxisConfig.free({JointMotor? motor})
    : this._(JointAxisMotion.free, 0, 0, motor);

  const JointAxisConfig.limited(double lower, double upper, {JointMotor? motor})
    : this._(JointAxisMotion.limited, lower, upper, motor);

  const JointAxisConfig._(
    this.motion,
    this.lowerLimit,
    this.upperLimit,
    this.motor,
  );

  final JointAxisMotion motion;
  final double lowerLimit;
  final double upperLimit;
  final JointMotor? motor;
}

/// Full description of a joint between two bodies.
///
/// [PhysicsSimulation.createJoint] consumes one; the same description is
/// passed to `updateJoint` on reconfiguration, so backends without
/// in-place updates can recreate internally.
sealed class JointDesc {
  const JointDesc({
    required this.bodyA,
    required this.bodyB,
    this.collisionsEnabled = false,
  });

  final int bodyA;
  final int bodyB;

  /// Whether the joined bodies still collide with each other.
  final bool collisionsEnabled;
}

class FixedJointDesc extends JointDesc {
  FixedJointDesc({
    required super.bodyA,
    required super.bodyB,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    super.collisionsEnabled,
  }) : localAnchorA = localAnchorA ?? Vector3.zero(),
       localAnchorB = localAnchorB ?? Vector3.zero();

  final Vector3 localAnchorA;
  final Vector3 localAnchorB;
}

class SphericalJointDesc extends JointDesc {
  SphericalJointDesc({
    required super.bodyA,
    required super.bodyB,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    super.collisionsEnabled,
  }) : localAnchorA = localAnchorA ?? Vector3.zero(),
       localAnchorB = localAnchorB ?? Vector3.zero();

  final Vector3 localAnchorA;
  final Vector3 localAnchorB;
}

class RevoluteJointDesc extends JointDesc {
  RevoluteJointDesc({
    required super.bodyA,
    required super.bodyB,
    required this.localAxisA,
    required this.localAxisB,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    this.lowerLimit,
    this.upperLimit,
    this.motorTargetVelocity,
    this.motorMaxForce,
    super.collisionsEnabled,
  }) : localAnchorA = localAnchorA ?? Vector3.zero(),
       localAnchorB = localAnchorB ?? Vector3.zero();

  final Vector3 localAnchorA;
  final Vector3 localAnchorB;
  final Vector3 localAxisA;
  final Vector3 localAxisB;
  final double? lowerLimit;
  final double? upperLimit;
  final double? motorTargetVelocity;
  final double? motorMaxForce;
}

class PrismaticJointDesc extends JointDesc {
  PrismaticJointDesc({
    required super.bodyA,
    required super.bodyB,
    required this.localAxisA,
    required this.localAxisB,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    this.lowerLimit,
    this.upperLimit,
    this.motorTargetVelocity,
    this.motorMaxForce,
    super.collisionsEnabled,
  }) : localAnchorA = localAnchorA ?? Vector3.zero(),
       localAnchorB = localAnchorB ?? Vector3.zero();

  final Vector3 localAnchorA;
  final Vector3 localAnchorB;
  final Vector3 localAxisA;
  final Vector3 localAxisB;
  final double? lowerLimit;
  final double? upperLimit;
  final double? motorTargetVelocity;
  final double? motorMaxForce;
}

class GenericJointDesc extends JointDesc {
  GenericJointDesc({
    required super.bodyA,
    required super.bodyB,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    Quaternion? localBasisA,
    Quaternion? localBasisB,
    List<JointAxisConfig>? axes,
    super.collisionsEnabled,
  }) : localAnchorA = localAnchorA ?? Vector3.zero(),
       localAnchorB = localAnchorB ?? Vector3.zero(),
       localBasisA = localBasisA ?? Quaternion.identity(),
       localBasisB = localBasisB ?? Quaternion.identity(),
       axes =
           axes ??
           List.filled(JointAxis.values.length, const JointAxisConfig.free());

  final Vector3 localAnchorA;
  final Vector3 localAnchorB;
  final Quaternion localBasisA;
  final Quaternion localBasisB;

  /// One config per [JointAxis], indexed by `JointAxis.index`.
  final List<JointAxisConfig> axes;
}
