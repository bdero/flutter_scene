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

/// A generic six-degree-of-freedom joint. Backends expose per-axis
/// locks, limits, and motors through their concrete subclass.
abstract class GenericJoint extends Joint {
  Vector3 get localAnchorA;
  set localAnchorA(Vector3 value);

  Vector3 get localAnchorB;
  set localAnchorB(Vector3 value);
}
