import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// A constraint linking the owning node's rigid body to another body.
///
/// Each joint subclass exposes a different combination of allowed
/// degrees of freedom plus optional limits and motors.
///
/// Concrete joint classes live in backend packages. Hold a reference at
/// the appropriate abstract subclass so user code stays portable.
abstract class Joint extends Component {
  /// The other node this joint connects to. When `null`, the joint
  /// anchors to the world (the other side behaves as a fixed body).
  Node? get otherNode;

  /// When `false`, the two bodies connected by this joint do not
  /// collide with each other (typical for ragdoll joints).
  bool get collisionsEnabled;
  set collisionsEnabled(bool value);
}

/// Welds two bodies together with zero degrees of freedom.
abstract class FixedJoint extends Joint {}

/// A ball-and-socket joint: three rotational degrees of freedom, zero
/// translational.
abstract class SphericalJoint extends Joint {
  Vector3 get localAnchorA;
  set localAnchorA(Vector3 value);

  Vector3 get localAnchorB;
  set localAnchorB(Vector3 value);
}

/// A hinge: one rotational degree of freedom around a shared axis.
abstract class RevoluteJoint extends Joint {
  Vector3 get localAnchorA;
  set localAnchorA(Vector3 value);

  Vector3 get localAnchorB;
  set localAnchorB(Vector3 value);

  Vector3 get localAxisA;
  set localAxisA(Vector3 value);

  Vector3 get localAxisB;
  set localAxisB(Vector3 value);

  /// Lower rotation limit in radians, or null for unlimited.
  double? get lowerLimit;
  set lowerLimit(double? value);

  double? get upperLimit;
  set upperLimit(double? value);

  /// Target angular velocity for the joint's motor, in radians per
  /// second. Null disables the motor.
  double? get motorTargetVelocity;
  set motorTargetVelocity(double? value);

  /// Maximum torque the motor may apply. Null disables the motor.
  double? get motorMaxForce;
  set motorMaxForce(double? value);
}

/// A slider: one translational degree of freedom along a shared axis.
abstract class PrismaticJoint extends Joint {
  Vector3 get localAnchorA;
  set localAnchorA(Vector3 value);

  Vector3 get localAnchorB;
  set localAnchorB(Vector3 value);

  Vector3 get localAxisA;
  set localAxisA(Vector3 value);

  Vector3 get localAxisB;
  set localAxisB(Vector3 value);

  double? get lowerLimit;
  set lowerLimit(double? value);

  double? get upperLimit;
  set upperLimit(double? value);

  double? get motorTargetVelocity;
  set motorTargetVelocity(double? value);

  double? get motorMaxForce;
  set motorMaxForce(double? value);
}

/// One of the six degrees of freedom a [GenericJoint] constrains. The
/// linear axes are translations along, and the angular axes rotations
/// about, the joint frame's local X / Y / Z (oriented by the joint's
/// local bases on each body).
enum JointAxis { linearX, linearY, linearZ, angularX, angularY, angularZ }

/// How a [JointMotor] turns its drive parameters into a force.
enum JointMotorModel {
  /// Treat [JointMotor.stiffness] and [JointMotor.damping] as target
  /// accelerations, so the response is independent of the connected
  /// bodies' masses. The usual choice.
  acceleration,

  /// Treat the drive parameters as raw forces.
  force,
}

/// A spring-damper drive on a single [GenericJoint] axis.
///
/// The motor pulls the axis toward [targetPosition] with spring constant
/// [stiffness] and toward [targetVelocity] with [damping], applying at
/// most [maxForce] (a force on a linear axis, a torque on an angular
/// one). Leave [stiffness] at 0 for a pure velocity drive; set it for a
/// positional spring (a soft constraint).
class JointMotor {
  /// Rest position the spring pulls toward: meters on a linear axis,
  /// radians on an angular one.
  final double targetPosition;

  /// Velocity the damper drives toward: meters per second or radians per
  /// second.
  final double targetVelocity;

  /// Spring constant pulling the axis toward [targetPosition].
  final double stiffness;

  /// Damping constant pulling the axis toward [targetVelocity].
  final double damping;

  /// Maximum force (linear axis) or torque (angular axis) the motor may
  /// apply. [double.infinity] leaves it unlimited.
  final double maxForce;

  /// How the drive parameters are interpreted.
  final JointMotorModel model;

  const JointMotor({
    this.targetPosition = 0,
    this.targetVelocity = 0,
    this.stiffness = 0,
    this.damping = 0,
    this.maxForce = double.infinity,
    this.model = JointMotorModel.acceleration,
  });
}

/// Whether a [GenericJoint] axis is locked, free, or limited.
enum JointAxisMotion { locked, free, limited }

/// The configuration of one of a [GenericJoint]'s six axes.
///
/// [motion] sets whether the axis is rigidly locked, free, or confined to
/// a band. [lowerLimit] / [upperLimit] apply only when [motion] is
/// [JointAxisMotion.limited]. An optional [motor] drives the axis.
class JointAxisConfig {
  final JointAxisMotion motion;
  final double lowerLimit;
  final double upperLimit;
  final JointMotor? motor;

  /// The axis is rigidly fixed (no relative motion along it).
  const JointAxisConfig.locked()
    : motion = JointAxisMotion.locked,
      lowerLimit = 0,
      upperLimit = 0,
      motor = null;

  /// The axis moves freely, optionally driven by [motor].
  const JointAxisConfig.free({this.motor})
    : motion = JointAxisMotion.free,
      lowerLimit = 0,
      upperLimit = 0;

  /// The axis is confined to [lower] .. [upper] (meters on a linear axis,
  /// radians on an angular one), optionally driven by [motor].
  const JointAxisConfig.limited(double lower, double upper, {this.motor})
    : motion = JointAxisMotion.limited,
      lowerLimit = lower,
      upperLimit = upper;
}

/// A fully configurable six-degree-of-freedom joint.
///
/// The joint defines a local reference frame on each body ([localAnchorA]
/// / [localBasisA] and [localAnchorB] / [localBasisB]); the six axes are
/// expressed in that frame. Each axis is independently locked, free, or
/// limited and may carry a spring-damper [JointMotor]. This is the most
/// general joint: the fixed, spherical, revolute, and prismatic joints
/// are all special cases. Pass a null [otherNode] to anchor to the world.
abstract class GenericJoint extends Joint {
  Vector3 get localAnchorA;
  set localAnchorA(Vector3 value);

  Vector3 get localAnchorB;
  set localAnchorB(Vector3 value);

  /// Orientation of the joint's reference frame on this node's body.
  Quaternion get localBasisA;
  set localBasisA(Quaternion value);

  /// Orientation of the joint's reference frame on the other body.
  Quaternion get localBasisB;
  set localBasisB(Quaternion value);

  /// The current configuration of [axis].
  JointAxisConfig configForAxis(JointAxis axis);

  /// Replaces the configuration of [axis]. Takes effect immediately while
  /// the joint is mounted.
  void setAxisConfig(JointAxis axis, JointAxisConfig config);
}
