import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/physics_world.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:scene/scene.dart' as sim;
import 'package:vector_math/vector_math.dart';

/// A constraint between this node's [RigidBody] and [otherNode]'s (or the
/// world, when [otherNode] is null).
///
/// Add after both bodies. Property setters reconfigure the live joint.
/// {@category Physics}
abstract class Joint extends Component {
  Joint({this.otherNode, bool collisionsEnabled = false})
    : _collisionsEnabled = collisionsEnabled;

  /// The body on the other side, or null to anchor against the world.
  final Node? otherNode;

  PhysicsWorld? _world;
  int? _handle;
  int? _anchorHandle;
  int _bodyA = 0;
  int _bodyB = 0;
  bool _collisionsEnabled;

  /// Whether the joined bodies still collide with each other.
  bool get collisionsEnabled => _collisionsEnabled;
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    push();
  }

  /// Builds the description for the current property values.
  sim.JointDesc buildDesc(int bodyA, int bodyB, bool collisionsEnabled);

  /// Reconfigures the live joint after a property change.
  void push() {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) return;
    world.simulation.updateJoint(
      handle,
      buildDesc(_bodyA, _bodyB, _collisionsEnabled),
    );
  }

  int _resolveBody(Node bodyNode, String side) {
    final body = bodyNode.getComponent<RigidBody>();
    final handle = body?.handle;
    if (handle == null) {
      throw StateError(
        'Joint requires a mounted RigidBody on its $side node; add the '
        'bodies before the joint',
      );
    }
    return handle;
  }

  @override
  void onMount() {
    final world = findAncestorWorld(node);
    if (world == null) {
      throw StateError(
        'Joint mounted with no PhysicsWorld on an ancestor node',
      );
    }
    if (!world.simulation.supportsJoints) {
      throw UnsupportedError('${world.backendName} has no joints');
    }
    _world = world;
    _bodyA = _resolveBody(node, 'own');
    final other = otherNode;
    if (other != null) {
      _bodyB = _resolveBody(other, 'other');
    } else {
      _bodyB = _anchorHandle = world.simulation.createAnchorBody();
    }
    _handle = world.simulation.createJoint(
      buildDesc(_bodyA, _bodyB, _collisionsEnabled),
    );
  }

  @override
  void onUnmount() {
    final world = _world;
    if (world != null) {
      final handle = _handle;
      if (handle != null) world.simulation.destroyJoint(handle);
      final anchor = _anchorHandle;
      if (anchor != null) world.simulation.destroyAnchorBody(anchor);
    }
    _handle = null;
    _anchorHandle = null;
    _world = null;
  }
}

/// Welds the two bodies' current relative pose.
/// {@category Physics}
class FixedJoint extends Joint {
  FixedJoint({
    super.otherNode,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    super.collisionsEnabled,
  }) : _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero();

  Vector3 _localAnchorA;
  Vector3 _localAnchorB;

  Vector3 get localAnchorA => _localAnchorA;
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    push();
  }

  Vector3 get localAnchorB => _localAnchorB;
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    push();
  }

  @override
  sim.JointDesc buildDesc(int bodyA, int bodyB, bool collisionsEnabled) =>
      sim.FixedJointDesc(
        bodyA: bodyA,
        bodyB: bodyB,
        localAnchorA: _localAnchorA,
        localAnchorB: _localAnchorB,
        collisionsEnabled: collisionsEnabled,
      );
}

/// A ball-and-socket constraint.
/// {@category Physics}
class SphericalJoint extends Joint {
  SphericalJoint({
    super.otherNode,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    super.collisionsEnabled,
  }) : _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero();

  Vector3 _localAnchorA;
  Vector3 _localAnchorB;

  Vector3 get localAnchorA => _localAnchorA;
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    push();
  }

  Vector3 get localAnchorB => _localAnchorB;
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    push();
  }

  @override
  sim.JointDesc buildDesc(int bodyA, int bodyB, bool collisionsEnabled) =>
      sim.SphericalJointDesc(
        bodyA: bodyA,
        bodyB: bodyB,
        localAnchorA: _localAnchorA,
        localAnchorB: _localAnchorB,
        collisionsEnabled: collisionsEnabled,
      );
}

/// A hinge about [localAxisA]/[localAxisB], optionally limited and
/// motorized.
/// {@category Physics}
class RevoluteJoint extends Joint {
  RevoluteJoint({
    super.otherNode,
    required Vector3 axis,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    super.collisionsEnabled,
  }) : _localAxisA = axis,
       _localAxisB = axis.clone(),
       _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _lowerLimit = lowerLimit,
       _upperLimit = upperLimit,
       _motorTargetVelocity = motorTargetVelocity,
       _motorMaxForce = motorMaxForce;

  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  Vector3 _localAxisA;
  Vector3 _localAxisB;
  double? _lowerLimit;
  double? _upperLimit;
  double? _motorTargetVelocity;
  double? _motorMaxForce;

  Vector3 get localAnchorA => _localAnchorA;
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    push();
  }

  Vector3 get localAnchorB => _localAnchorB;
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    push();
  }

  Vector3 get localAxisA => _localAxisA;
  set localAxisA(Vector3 value) {
    _localAxisA = value.normalized();
    push();
  }

  Vector3 get localAxisB => _localAxisB;
  set localAxisB(Vector3 value) {
    _localAxisB = value.normalized();
    push();
  }

  double? get lowerLimit => _lowerLimit;
  set lowerLimit(double? value) {
    _lowerLimit = value;
    push();
  }

  double? get upperLimit => _upperLimit;
  set upperLimit(double? value) {
    _upperLimit = value;
    push();
  }

  double? get motorTargetVelocity => _motorTargetVelocity;
  set motorTargetVelocity(double? value) {
    _motorTargetVelocity = value;
    push();
  }

  double? get motorMaxForce => _motorMaxForce;
  set motorMaxForce(double? value) {
    _motorMaxForce = value;
    push();
  }

  @override
  sim.JointDesc buildDesc(int bodyA, int bodyB, bool collisionsEnabled) =>
      sim.RevoluteJointDesc(
        bodyA: bodyA,
        bodyB: bodyB,
        localAnchorA: _localAnchorA,
        localAnchorB: _localAnchorB,
        localAxisA: _localAxisA,
        localAxisB: _localAxisB,
        lowerLimit: _lowerLimit,
        upperLimit: _upperLimit,
        motorTargetVelocity: _motorTargetVelocity,
        motorMaxForce: _motorMaxForce,
        collisionsEnabled: collisionsEnabled,
      );
}

/// A slider along [localAxisA]/[localAxisB], optionally limited and
/// motorized.
/// {@category Physics}
class PrismaticJoint extends Joint {
  PrismaticJoint({
    super.otherNode,
    required Vector3 axis,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    super.collisionsEnabled,
  }) : _localAxisA = axis,
       _localAxisB = axis.clone(),
       _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _lowerLimit = lowerLimit,
       _upperLimit = upperLimit,
       _motorTargetVelocity = motorTargetVelocity,
       _motorMaxForce = motorMaxForce;

  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  Vector3 _localAxisA;
  Vector3 _localAxisB;
  double? _lowerLimit;
  double? _upperLimit;
  double? _motorTargetVelocity;
  double? _motorMaxForce;

  Vector3 get localAnchorA => _localAnchorA;
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    push();
  }

  Vector3 get localAnchorB => _localAnchorB;
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    push();
  }

  Vector3 get localAxisA => _localAxisA;
  set localAxisA(Vector3 value) {
    _localAxisA = value.normalized();
    push();
  }

  Vector3 get localAxisB => _localAxisB;
  set localAxisB(Vector3 value) {
    _localAxisB = value.normalized();
    push();
  }

  double? get lowerLimit => _lowerLimit;
  set lowerLimit(double? value) {
    _lowerLimit = value;
    push();
  }

  double? get upperLimit => _upperLimit;
  set upperLimit(double? value) {
    _upperLimit = value;
    push();
  }

  double? get motorTargetVelocity => _motorTargetVelocity;
  set motorTargetVelocity(double? value) {
    _motorTargetVelocity = value;
    push();
  }

  double? get motorMaxForce => _motorMaxForce;
  set motorMaxForce(double? value) {
    _motorMaxForce = value;
    push();
  }

  @override
  sim.JointDesc buildDesc(int bodyA, int bodyB, bool collisionsEnabled) =>
      sim.PrismaticJointDesc(
        bodyA: bodyA,
        bodyB: bodyB,
        localAnchorA: _localAnchorA,
        localAnchorB: _localAnchorB,
        localAxisA: _localAxisA,
        localAxisB: _localAxisB,
        lowerLimit: _lowerLimit,
        upperLimit: _upperLimit,
        motorTargetVelocity: _motorTargetVelocity,
        motorMaxForce: _motorMaxForce,
        collisionsEnabled: collisionsEnabled,
      );
}

/// A six-degree-of-freedom constraint with per-axis motion configs.
/// {@category Physics}
class GenericJoint extends Joint {
  GenericJoint({
    super.otherNode,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    Quaternion? localBasisA,
    Quaternion? localBasisB,
    Map<sim.JointAxis, sim.JointAxisConfig>? axes,
    super.collisionsEnabled,
  }) : _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _localBasisA = localBasisA ?? Quaternion.identity(),
       _localBasisB = localBasisB ?? Quaternion.identity(),
       _axes = [
         for (final axis in sim.JointAxis.values)
           axes?[axis] ?? const sim.JointAxisConfig.free(),
       ];

  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  Quaternion _localBasisA;
  Quaternion _localBasisB;
  final List<sim.JointAxisConfig> _axes;

  Vector3 get localAnchorA => _localAnchorA;
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    push();
  }

  Vector3 get localAnchorB => _localAnchorB;
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    push();
  }

  Quaternion get localBasisA => _localBasisA;
  set localBasisA(Quaternion value) {
    _localBasisA = value;
    push();
  }

  Quaternion get localBasisB => _localBasisB;
  set localBasisB(Quaternion value) {
    _localBasisB = value;
    push();
  }

  sim.JointAxisConfig configForAxis(sim.JointAxis axis) => _axes[axis.index];

  void setAxisConfig(sim.JointAxis axis, sim.JointAxisConfig config) {
    _axes[axis.index] = config;
    push();
  }

  @override
  sim.JointDesc buildDesc(int bodyA, int bodyB, bool collisionsEnabled) =>
      sim.GenericJointDesc(
        bodyA: bodyA,
        bodyB: bodyB,
        localAnchorA: _localAnchorA,
        localAnchorB: _localAnchorB,
        localBasisA: _localBasisA,
        localBasisB: _localBasisB,
        axes: List.of(_axes),
        collisionsEnabled: collisionsEnabled,
      );
}
