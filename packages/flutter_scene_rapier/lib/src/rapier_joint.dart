import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/rapier_rigid_body.dart';
import 'package:flutter_scene_rapier/src/rapier_world.dart';
import 'package:vector_math/vector_math.dart';

/// Shared lifecycle for the Rapier-backed joints.
///
/// A joint links the [RapierRigidBody] on its own node to the body on
/// [otherNode]. Both nodes must carry a mounted [RapierRigidBody] when
/// the joint mounts.
///
/// TODO(world-anchor): [otherNode] cannot be null yet. Anchoring a
/// joint to the world (the abstract contract's null case) needs an
/// implicit fixed body on the unused side; wire that up.
mixin _RapierJointMixin on Joint {
  RapierWorld? _world;
  int? _handle;

  /// The native joint handle once mounted, or null when the joint has
  /// no ancestor world or is otherwise not registered.
  int? get nativeHandle => _handle;

  // Inserts the joint into the native world. Subclasses supply the
  // builder call via [insert]; this handles world / body resolution
  // and bookkeeping shared by every joint type.
  int _insertJoint(
    int Function(RapierWorld world, int bodyA, int bodyB) insert,
  ) {
    final world = findAncestorRapierWorld(node);
    if (world == null) {
      throw StateError(
        'A Rapier joint must be mounted under a node carrying a '
        'RapierWorld.',
      );
    }
    final bodyA = node.getComponent<RapierRigidBody>()?.nativeHandle;
    if (bodyA == null) {
      throw StateError(
        'A Rapier joint requires a mounted RapierRigidBody on its own '
        'node.',
      );
    }
    final other = otherNode;
    if (other == null) {
      throw UnsupportedError(
        'Rapier joints require a non-null otherNode; world-anchored '
        'joints are not supported yet.',
      );
    }
    final bodyB = other.getComponent<RapierRigidBody>()?.nativeHandle;
    if (bodyB == null) {
      throw StateError(
        'A Rapier joint requires a mounted RapierRigidBody on its '
        'otherNode.',
      );
    }
    _world = world;
    _handle = insert(world, bodyA, bodyB);
    return _handle!;
  }

  void _destroyJoint() {
    final world = _world;
    final handle = _handle;
    if (world != null && handle != null) {
      world.destroyJoint(handle);
    }
    _world = null;
    _handle = null;
  }
}

/// [FixedJoint] backed by Rapier. Welds the two bodies together at the
/// given local anchors.
class RapierFixedJoint extends FixedJoint with _RapierJointMixin {
  RapierFixedJoint({
    required Node otherNode,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    bool collisionsEnabled = false,
  }) : _otherNode = otherNode,
       localAnchorA = localAnchorA ?? Vector3.zero(),
       localAnchorB = localAnchorB ?? Vector3.zero(),
       _collisionsEnabled = collisionsEnabled;

  final Node _otherNode;
  Vector3 localAnchorA;
  Vector3 localAnchorB;
  bool _collisionsEnabled;

  @override
  Node? get otherNode => _otherNode;

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) => _collisionsEnabled = value;

  @override
  void onMount() {
    _insertJoint(
      (world, bodyA, bodyB) => world.createFixedJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        anchorA: localAnchorA,
        anchorB: localAnchorB,
        collisionsEnabled: _collisionsEnabled,
      ),
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}

/// [SphericalJoint] backed by Rapier. A ball-and-socket: free rotation
/// about the shared anchor point, no relative translation.
class RapierSphericalJoint extends SphericalJoint with _RapierJointMixin {
  RapierSphericalJoint({
    required Node otherNode,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    bool collisionsEnabled = false,
  }) : _otherNode = otherNode,
       _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _collisionsEnabled = collisionsEnabled;

  final Node _otherNode;
  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  bool _collisionsEnabled;

  @override
  Node? get otherNode => _otherNode;

  @override
  Vector3 get localAnchorA => _localAnchorA;
  @override
  set localAnchorA(Vector3 value) => _localAnchorA = value;

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) => _localAnchorB = value;

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) => _collisionsEnabled = value;

  @override
  void onMount() {
    _insertJoint(
      (world, bodyA, bodyB) => world.createSphericalJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        anchorA: _localAnchorA,
        anchorB: _localAnchorB,
        collisionsEnabled: _collisionsEnabled,
      ),
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}

/// [RevoluteJoint] backed by Rapier. A hinge about a shared axis, with
/// optional angular limits and a velocity motor.
///
/// Joint parameters (anchors, axis, limits, motor) are read once at
/// mount time. Changing them after mount has no effect until the joint
/// is re-mounted.
///
/// TODO(live-joint-params): forward post-mount parameter changes to
/// the native joint rather than only reading them at mount.
class RapierRevoluteJoint extends RevoluteJoint with _RapierJointMixin {
  RapierRevoluteJoint({
    required Node otherNode,
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

  final Node _otherNode;
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
  set localAnchorA(Vector3 value) => _localAnchorA = value;

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) => _localAnchorB = value;

  @override
  Vector3 get localAxisA => _localAxisA;
  @override
  set localAxisA(Vector3 value) => _localAxisA = value;

  @override
  Vector3 get localAxisB => _localAxisB;
  @override
  set localAxisB(Vector3 value) => _localAxisB = value;

  @override
  double? get lowerLimit => _lowerLimit;
  @override
  set lowerLimit(double? value) => _lowerLimit = value;

  @override
  double? get upperLimit => _upperLimit;
  @override
  set upperLimit(double? value) => _upperLimit = value;

  @override
  double? get motorTargetVelocity => _motorTargetVelocity;
  @override
  set motorTargetVelocity(double? value) => _motorTargetVelocity = value;

  @override
  double? get motorMaxForce => _motorMaxForce;
  @override
  set motorMaxForce(double? value) => _motorMaxForce = value;

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) => _collisionsEnabled = value;

  @override
  void onMount() {
    _insertJoint(
      (world, bodyA, bodyB) => world.createRevoluteJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        axis: _localAxisA,
        anchorA: _localAnchorA,
        anchorB: _localAnchorB,
        lowerLimit: _lowerLimit,
        upperLimit: _upperLimit,
        motorTargetVelocity: _motorTargetVelocity,
        motorMaxForce: _motorMaxForce,
        collisionsEnabled: _collisionsEnabled,
      ),
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}

/// [PrismaticJoint] backed by Rapier. A slider along a shared axis,
/// with optional linear limits and a velocity motor.
///
/// As with [RapierRevoluteJoint], parameters are read once at mount
/// time.
class RapierPrismaticJoint extends PrismaticJoint with _RapierJointMixin {
  RapierPrismaticJoint({
    required Node otherNode,
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

  final Node _otherNode;
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
  set localAnchorA(Vector3 value) => _localAnchorA = value;

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) => _localAnchorB = value;

  @override
  Vector3 get localAxisA => _localAxisA;
  @override
  set localAxisA(Vector3 value) => _localAxisA = value;

  @override
  Vector3 get localAxisB => _localAxisB;
  @override
  set localAxisB(Vector3 value) => _localAxisB = value;

  @override
  double? get lowerLimit => _lowerLimit;
  @override
  set lowerLimit(double? value) => _lowerLimit = value;

  @override
  double? get upperLimit => _upperLimit;
  @override
  set upperLimit(double? value) => _upperLimit = value;

  @override
  double? get motorTargetVelocity => _motorTargetVelocity;
  @override
  set motorTargetVelocity(double? value) => _motorTargetVelocity = value;

  @override
  double? get motorMaxForce => _motorMaxForce;
  @override
  set motorMaxForce(double? value) => _motorMaxForce = value;

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) => _collisionsEnabled = value;

  @override
  void onMount() {
    _insertJoint(
      (world, bodyA, bodyB) => world.createPrismaticJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        axis: _localAxisA,
        anchorA: _localAnchorA,
        anchorB: _localAnchorB,
        lowerLimit: _lowerLimit,
        upperLimit: _upperLimit,
        motorTargetVelocity: _motorTargetVelocity,
        motorMaxForce: _motorMaxForce,
        collisionsEnabled: _collisionsEnabled,
      ),
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}
