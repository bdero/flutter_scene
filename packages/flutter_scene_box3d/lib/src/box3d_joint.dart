import 'package:box3d/box3d.dart' as b3;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'box3d_physics_world.dart';
import 'box3d_rigid_body.dart';

/// Shared lifecycle for the box3d-backed joints.
///
/// A joint links the [Box3dRigidBody] on its own node to the body on
/// [otherNode]; a null [otherNode] anchors to the world through an implicit
/// static body at the origin, so the B-side anchor is in world space.
///
/// box3d exposes joint creation and destruction but no in-place
/// reconfiguration, so parameter setters recreate the joint while the two
/// resolved bodies (and any world-anchor body) stay put.
mixin _Box3dJointMixin on Joint {
  Box3dPhysicsWorld? _world;
  b3.Box3dJoint? _joint;
  b3.Box3dBody? _bodyA;
  b3.Box3dBody? _bodyB;
  b3.Box3dBody? _anchorBody;

  /// The box3d joint once mounted, or null.
  b3.Box3dJoint? get nativeJoint => _joint;

  // Builds the joint on the two resolved bodies. Implemented per subclass.
  b3.Box3dJoint _create(
    b3.Box3dWorld world,
    b3.Box3dBody bodyA,
    b3.Box3dBody bodyB,
  );

  /// The current world transform of a resolved body, for frame math.
  static Matrix4 worldOf(b3.Box3dBody body) =>
      Matrix4.compose(body.position, body.rotation, Vector3(1, 1, 1));

  @override
  void onMount() {
    final world = findAncestorBox3dWorld(node);
    if (world == null) {
      throw StateError('A box3d joint must be mounted under a Box3dWorld.');
    }
    final bodyA = node.getComponent<Box3dRigidBody>()?.nativeBody;
    if (bodyA == null) {
      throw StateError(
        'A box3d joint requires a mounted Box3dRigidBody on its own node.',
      );
    }
    final b3.Box3dBody bodyB;
    final other = otherNode;
    if (other == null) {
      _anchorBody = world.nativeWorld.createBody(
        type: b3.Box3dBodyType.static_,
      );
      bodyB = _anchorBody!;
    } else {
      final handle = other.getComponent<Box3dRigidBody>()?.nativeBody;
      if (handle == null) {
        throw StateError(
          'A box3d joint requires a mounted Box3dRigidBody on its otherNode.',
        );
      }
      bodyB = handle;
    }
    _world = world;
    _bodyA = bodyA;
    _bodyB = bodyB;
    _joint = _create(world.nativeWorld, bodyA, bodyB);
  }

  // Recreates the joint (setters call this so parameter changes take effect).
  void _recreate() {
    final world = _world;
    final bodyA = _bodyA;
    final bodyB = _bodyB;
    if (world == null || bodyA == null || bodyB == null) return;
    _joint?.destroy();
    _joint = _create(world.nativeWorld, bodyA, bodyB);
  }

  @override
  void onUnmount() {
    _joint?.destroy();
    _anchorBody?.destroy();
    _world = null;
    _joint = null;
    _bodyA = null;
    _bodyB = null;
    _anchorBody = null;
  }
}

/// [FixedJoint] backed by box3d. Welds the two bodies, holding their
/// relative pose at the moment the joint mounts. Pass a null [otherNode] to
/// weld the body to the world.
class Box3dFixedJoint extends FixedJoint with _Box3dJointMixin {
  Box3dFixedJoint({Node? otherNode, bool collisionsEnabled = false})
    : _otherNode = otherNode,
      _collisionsEnabled = collisionsEnabled;

  final Node? _otherNode;
  bool _collisionsEnabled;

  @override
  Node? get otherNode => _otherNode;

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _recreate();
  }

  @override
  b3.Box3dJoint _create(
    b3.Box3dWorld world,
    b3.Box3dBody bodyA,
    b3.Box3dBody bodyB,
  ) {
    // Choose frames so the weld holds the current relative pose:
    // worldA * frameA == worldB * frameB with frameA at A's origin.
    final worldA = _Box3dJointMixin.worldOf(bodyA);
    final worldB = _Box3dJointMixin.worldOf(bodyB);
    final relative = Matrix4.inverted(worldB)..multiply(worldA);
    return world.createWeldJoint(
      bodyA,
      bodyB,
      frameB: b3.Box3dFrame(
        position: relative.getTranslation(),
        rotation: Quaternion.fromRotation(relative.getRotation()),
      ),
      collideConnected: _collisionsEnabled,
    );
  }
}

/// [SphericalJoint] backed by box3d: a ball-and-socket about the shared
/// anchor. Pass a null [otherNode] to anchor to the world.
class Box3dSphericalJoint extends SphericalJoint with _Box3dJointMixin {
  Box3dSphericalJoint({
    Node? otherNode,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    bool collisionsEnabled = false,
  }) : _otherNode = otherNode,
       _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _collisionsEnabled = collisionsEnabled;

  final Node? _otherNode;
  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  bool _collisionsEnabled;

  @override
  Node? get otherNode => _otherNode;

  @override
  Vector3 get localAnchorA => _localAnchorA;
  @override
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    _recreate();
  }

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _recreate();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _recreate();
  }

  @override
  b3.Box3dJoint _create(
    b3.Box3dWorld world,
    b3.Box3dBody bodyA,
    b3.Box3dBody bodyB,
  ) => world.createSphericalJoint(
    bodyA,
    bodyB,
    frameA: b3.Box3dFrame(position: _localAnchorA),
    frameB: b3.Box3dFrame(position: _localAnchorB),
    collideConnected: _collisionsEnabled,
  );
}

/// [RevoluteJoint] backed by box3d: a hinge about a shared axis, with
/// optional angular limits and a velocity motor. Pass a null [otherNode] to
/// hinge against the world.
class Box3dRevoluteJoint extends RevoluteJoint with _Box3dJointMixin {
  Box3dRevoluteJoint({
    Node? otherNode,
    required Vector3 axis,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled = false,
  }) : _otherNode = otherNode,
       _localAxisA = axis.normalized(),
       _localAxisB = axis.normalized(),
       _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _lowerLimit = lowerLimit,
       _upperLimit = upperLimit,
       _motorTargetVelocity = motorTargetVelocity,
       _motorMaxForce = motorMaxForce,
       _collisionsEnabled = collisionsEnabled;

  final Node? _otherNode;
  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  Vector3 _localAxisA;
  Vector3 _localAxisB;
  double? _lowerLimit;
  double? _upperLimit;
  double? _motorTargetVelocity;
  double? _motorMaxForce;
  bool _collisionsEnabled;

  @override
  Node? get otherNode => _otherNode;

  @override
  Vector3 get localAnchorA => _localAnchorA;
  @override
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    _recreate();
  }

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _recreate();
  }

  @override
  Vector3 get localAxisA => _localAxisA;
  @override
  set localAxisA(Vector3 value) {
    _localAxisA = value.normalized();
    _recreate();
  }

  @override
  Vector3 get localAxisB => _localAxisB;
  @override
  set localAxisB(Vector3 value) {
    _localAxisB = value.normalized();
    _recreate();
  }

  @override
  double? get lowerLimit => _lowerLimit;
  @override
  set lowerLimit(double? value) {
    _lowerLimit = value;
    _recreate();
  }

  @override
  double? get upperLimit => _upperLimit;
  @override
  set upperLimit(double? value) {
    _upperLimit = value;
    _recreate();
  }

  @override
  double? get motorTargetVelocity => _motorTargetVelocity;
  @override
  set motorTargetVelocity(double? value) {
    _motorTargetVelocity = value;
    _recreate();
  }

  @override
  double? get motorMaxForce => _motorMaxForce;
  @override
  set motorMaxForce(double? value) {
    _motorMaxForce = value;
    _recreate();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _recreate();
  }

  @override
  b3.Box3dJoint _create(
    b3.Box3dWorld world,
    b3.Box3dBody bodyA,
    b3.Box3dBody bodyB,
  ) => world.createRevoluteJoint(
    bodyA,
    bodyB,
    frameA: b3.Box3dFrame.pointAxis(_localAnchorA, _localAxisA),
    frameB: b3.Box3dFrame.pointAxis(_localAnchorB, _localAxisB),
    lowerLimit: _lowerLimit,
    upperLimit: _upperLimit,
    motorSpeed: _motorTargetVelocity,
    maxMotorTorque: _motorMaxForce,
    collideConnected: _collisionsEnabled,
  );
}

/// [PrismaticJoint] backed by box3d: a slider along a shared axis, with
/// optional linear limits and a velocity motor. Pass a null [otherNode] to
/// slide against the world.
class Box3dPrismaticJoint extends PrismaticJoint with _Box3dJointMixin {
  Box3dPrismaticJoint({
    Node? otherNode,
    required Vector3 axis,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled = false,
  }) : _otherNode = otherNode,
       _localAxisA = axis.normalized(),
       _localAxisB = axis.normalized(),
       _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _lowerLimit = lowerLimit,
       _upperLimit = upperLimit,
       _motorTargetVelocity = motorTargetVelocity,
       _motorMaxForce = motorMaxForce,
       _collisionsEnabled = collisionsEnabled;

  final Node? _otherNode;
  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  Vector3 _localAxisA;
  Vector3 _localAxisB;
  double? _lowerLimit;
  double? _upperLimit;
  double? _motorTargetVelocity;
  double? _motorMaxForce;
  bool _collisionsEnabled;

  @override
  Node? get otherNode => _otherNode;

  @override
  Vector3 get localAnchorA => _localAnchorA;
  @override
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    _recreate();
  }

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _recreate();
  }

  @override
  Vector3 get localAxisA => _localAxisA;
  @override
  set localAxisA(Vector3 value) {
    _localAxisA = value.normalized();
    _recreate();
  }

  @override
  Vector3 get localAxisB => _localAxisB;
  @override
  set localAxisB(Vector3 value) {
    _localAxisB = value.normalized();
    _recreate();
  }

  @override
  double? get lowerLimit => _lowerLimit;
  @override
  set lowerLimit(double? value) {
    _lowerLimit = value;
    _recreate();
  }

  @override
  double? get upperLimit => _upperLimit;
  @override
  set upperLimit(double? value) {
    _upperLimit = value;
    _recreate();
  }

  @override
  double? get motorTargetVelocity => _motorTargetVelocity;
  @override
  set motorTargetVelocity(double? value) {
    _motorTargetVelocity = value;
    _recreate();
  }

  @override
  double? get motorMaxForce => _motorMaxForce;
  @override
  set motorMaxForce(double? value) {
    _motorMaxForce = value;
    _recreate();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _recreate();
  }

  @override
  b3.Box3dJoint _create(
    b3.Box3dWorld world,
    b3.Box3dBody bodyA,
    b3.Box3dBody bodyB,
  ) => world.createPrismaticJoint(
    bodyA,
    bodyB,
    // A prismatic joint's slide axis is the frame's local X.
    frameA: b3.Box3dFrame.pointAxisX(_localAnchorA, _localAxisA),
    frameB: b3.Box3dFrame.pointAxisX(_localAnchorB, _localAxisB),
    // box3d measures this joint's translation opposite to the contract's
    // convention (positive along +axis) when the own node is body A, so
    // negate and swap the limits and negate the motor velocity.
    lowerLimit: _upperLimit == null ? null : -_upperLimit!,
    upperLimit: _lowerLimit == null ? null : -_lowerLimit!,
    motorSpeed: _motorTargetVelocity == null ? null : -_motorTargetVelocity!,
    maxMotorForce: _motorMaxForce,
    collideConnected: _collisionsEnabled,
  );
}

// TODO(box3d-generic-joint): box3d has no 6-DOF generic joint, so
// GenericJoint from the flutter_scene contract is not implemented by this
// backend. Use the fixed, spherical, revolute, or prismatic joints instead.
