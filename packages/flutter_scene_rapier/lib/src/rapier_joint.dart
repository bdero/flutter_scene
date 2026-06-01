import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/rapier_rigid_body.dart';
import 'package:flutter_scene_rapier/src/rapier_world.dart';
import 'package:vector_math/vector_math.dart';

/// Shared lifecycle for the Rapier-backed joints.
///
/// A joint links the [RapierRigidBody] on its own node to the body on
/// [otherNode]. The own node must carry a mounted [RapierRigidBody] when
/// the joint mounts. When [otherNode] is null the joint anchors to the
/// world: it connects to an implicit fixed body at the world origin, so
/// the B-side anchor is interpreted in world space.
///
/// Parameter setters take effect immediately while the joint is mounted;
/// each setter rewrites the native joint in place.
mixin _RapierJointMixin on Joint {
  RapierWorld? _world;
  int? _handle;

  // Native handle of the implicit fixed body created for a world-anchored
  // joint, or null when the joint connects to a real [otherNode].
  int? _anchorBody;

  /// The native joint handle once mounted, or null when the joint has
  /// no ancestor world or is otherwise not registered.
  int? get nativeHandle => _handle;

  // Pushes this joint's current parameters to the native side. Subclasses
  // implement it by calling the matching `RapierWorld.update*Joint`.
  void _applyToNative(RapierWorld world, int handle);

  // Re-applies the joint's parameters to the native side if it is mounted.
  // Called from every parameter setter so changes take effect live.
  void _applyIfMounted() {
    final world = _world;
    final handle = _handle;
    if (world != null && handle != null) {
      _applyToNative(world, handle);
    }
  }

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
    final int bodyB;
    final other = otherNode;
    if (other == null) {
      // World-anchored: stand in a fixed body at the origin for the
      // unused side, so the B-side anchor lands in world space.
      _anchorBody = world.createJointAnchorBody();
      bodyB = _anchorBody!;
    } else {
      final handle = other.getComponent<RapierRigidBody>()?.nativeHandle;
      if (handle == null) {
        throw StateError(
          'A Rapier joint requires a mounted RapierRigidBody on its '
          'otherNode.',
        );
      }
      bodyB = handle;
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
    final anchor = _anchorBody;
    if (world != null && anchor != null) {
      world.destroyJointAnchorBody(anchor);
    }
    _world = null;
    _handle = null;
    _anchorBody = null;
  }
}

/// [FixedJoint] backed by Rapier. Welds the two bodies together at the
/// given local anchors. Pass a null [otherNode] to weld the body to the
/// world.
class RapierFixedJoint extends FixedJoint with _RapierJointMixin {
  RapierFixedJoint({
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

  /// Anchor point on this node's body, in its local space.
  Vector3 get localAnchorA => _localAnchorA;
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    _applyIfMounted();
  }

  /// Anchor point on the other body (or in world space when
  /// world-anchored), in its local space.
  Vector3 get localAnchorB => _localAnchorB;
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _applyIfMounted();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _applyIfMounted();
  }

  @override
  void onMount() {
    _insertJoint(
      (world, bodyA, bodyB) => world.createFixedJoint(
        bodyA: bodyA,
        bodyB: bodyB,
        anchorA: _localAnchorA,
        anchorB: _localAnchorB,
        collisionsEnabled: _collisionsEnabled,
      ),
    );
  }

  @override
  void _applyToNative(RapierWorld world, int handle) {
    world.updateFixedJoint(
      handle,
      anchorA: _localAnchorA,
      anchorB: _localAnchorB,
      collisionsEnabled: _collisionsEnabled,
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}

/// [SphericalJoint] backed by Rapier. A ball-and-socket: free rotation
/// about the shared anchor point, no relative translation. Pass a null
/// [otherNode] to anchor to the world.
class RapierSphericalJoint extends SphericalJoint with _RapierJointMixin {
  RapierSphericalJoint({
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
    _applyIfMounted();
  }

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _applyIfMounted();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _applyIfMounted();
  }

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
  void _applyToNative(RapierWorld world, int handle) {
    world.updateSphericalJoint(
      handle,
      anchorA: _localAnchorA,
      anchorB: _localAnchorB,
      collisionsEnabled: _collisionsEnabled,
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}

/// [RevoluteJoint] backed by Rapier. A hinge about a shared axis, with
/// optional angular limits and a velocity motor. Pass a null [otherNode]
/// to hinge against the world.
class RapierRevoluteJoint extends RevoluteJoint with _RapierJointMixin {
  RapierRevoluteJoint({
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
    _applyIfMounted();
  }

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _applyIfMounted();
  }

  @override
  Vector3 get localAxisA => _localAxisA;
  @override
  set localAxisA(Vector3 value) {
    _localAxisA = value;
    _applyIfMounted();
  }

  @override
  Vector3 get localAxisB => _localAxisB;
  @override
  set localAxisB(Vector3 value) {
    _localAxisB = value;
    _applyIfMounted();
  }

  @override
  double? get lowerLimit => _lowerLimit;
  @override
  set lowerLimit(double? value) {
    _lowerLimit = value;
    _applyIfMounted();
  }

  @override
  double? get upperLimit => _upperLimit;
  @override
  set upperLimit(double? value) {
    _upperLimit = value;
    _applyIfMounted();
  }

  @override
  double? get motorTargetVelocity => _motorTargetVelocity;
  @override
  set motorTargetVelocity(double? value) {
    _motorTargetVelocity = value;
    _applyIfMounted();
  }

  @override
  double? get motorMaxForce => _motorMaxForce;
  @override
  set motorMaxForce(double? value) {
    _motorMaxForce = value;
    _applyIfMounted();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _applyIfMounted();
  }

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
  void _applyToNative(RapierWorld world, int handle) {
    world.updateRevoluteJoint(
      handle,
      axis: _localAxisA,
      anchorA: _localAnchorA,
      anchorB: _localAnchorB,
      lowerLimit: _lowerLimit,
      upperLimit: _upperLimit,
      motorTargetVelocity: _motorTargetVelocity,
      motorMaxForce: _motorMaxForce,
      collisionsEnabled: _collisionsEnabled,
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}

/// [PrismaticJoint] backed by Rapier. A slider along a shared axis, with
/// optional linear limits and a velocity motor. Pass a null [otherNode]
/// to slide against the world.
class RapierPrismaticJoint extends PrismaticJoint with _RapierJointMixin {
  RapierPrismaticJoint({
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
    _applyIfMounted();
  }

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _applyIfMounted();
  }

  @override
  Vector3 get localAxisA => _localAxisA;
  @override
  set localAxisA(Vector3 value) {
    _localAxisA = value;
    _applyIfMounted();
  }

  @override
  Vector3 get localAxisB => _localAxisB;
  @override
  set localAxisB(Vector3 value) {
    _localAxisB = value;
    _applyIfMounted();
  }

  @override
  double? get lowerLimit => _lowerLimit;
  @override
  set lowerLimit(double? value) {
    _lowerLimit = value;
    _applyIfMounted();
  }

  @override
  double? get upperLimit => _upperLimit;
  @override
  set upperLimit(double? value) {
    _upperLimit = value;
    _applyIfMounted();
  }

  @override
  double? get motorTargetVelocity => _motorTargetVelocity;
  @override
  set motorTargetVelocity(double? value) {
    _motorTargetVelocity = value;
    _applyIfMounted();
  }

  @override
  double? get motorMaxForce => _motorMaxForce;
  @override
  set motorMaxForce(double? value) {
    _motorMaxForce = value;
    _applyIfMounted();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _applyIfMounted();
  }

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
  void _applyToNative(RapierWorld world, int handle) {
    world.updatePrismaticJoint(
      handle,
      axis: _localAxisA,
      anchorA: _localAnchorA,
      anchorB: _localAnchorB,
      lowerLimit: _lowerLimit,
      upperLimit: _upperLimit,
      motorTargetVelocity: _motorTargetVelocity,
      motorMaxForce: _motorMaxForce,
      collisionsEnabled: _collisionsEnabled,
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}

/// [GenericJoint] backed by Rapier. A fully configurable six-degree-of-
/// freedom joint: each of the six axes (defined in the joint frames set
/// by the local anchors and bases) is independently locked, free, or
/// limited, and may carry a spring-damper [JointMotor]. Pass a null
/// [otherNode] to anchor to the world.
class RapierGenericJoint extends GenericJoint with _RapierJointMixin {
  RapierGenericJoint({
    Node? otherNode,
    Vector3? localAnchorA,
    Vector3? localAnchorB,
    Quaternion? localBasisA,
    Quaternion? localBasisB,
    Map<JointAxis, JointAxisConfig>? axes,
    bool collisionsEnabled = false,
  }) : _otherNode = otherNode,
       _localAnchorA = localAnchorA ?? Vector3.zero(),
       _localAnchorB = localAnchorB ?? Vector3.zero(),
       _localBasisA = localBasisA ?? Quaternion.identity(),
       _localBasisB = localBasisB ?? Quaternion.identity(),
       _axes = _buildAxisList(axes),
       _collisionsEnabled = collisionsEnabled;

  // Fills a fixed six-entry list (indexed by JointAxis.index) from the
  // optional per-axis overrides, defaulting every axis to free.
  static List<JointAxisConfig> _buildAxisList(
    Map<JointAxis, JointAxisConfig>? axes,
  ) {
    final list = List<JointAxisConfig>.filled(6, const JointAxisConfig.free());
    if (axes != null) {
      for (final entry in axes.entries) {
        list[entry.key.index] = entry.value;
      }
    }
    return list;
  }

  final Node? _otherNode;
  Vector3 _localAnchorA;
  Vector3 _localAnchorB;
  Quaternion _localBasisA;
  Quaternion _localBasisB;
  final List<JointAxisConfig> _axes;
  bool _collisionsEnabled;

  @override
  Node? get otherNode => _otherNode;

  @override
  Vector3 get localAnchorA => _localAnchorA;
  @override
  set localAnchorA(Vector3 value) {
    _localAnchorA = value;
    _applyIfMounted();
  }

  @override
  Vector3 get localAnchorB => _localAnchorB;
  @override
  set localAnchorB(Vector3 value) {
    _localAnchorB = value;
    _applyIfMounted();
  }

  @override
  Quaternion get localBasisA => _localBasisA;
  @override
  set localBasisA(Quaternion value) {
    _localBasisA = value;
    _applyIfMounted();
  }

  @override
  Quaternion get localBasisB => _localBasisB;
  @override
  set localBasisB(Quaternion value) {
    _localBasisB = value;
    _applyIfMounted();
  }

  @override
  JointAxisConfig configForAxis(JointAxis axis) => _axes[axis.index];

  @override
  void setAxisConfig(JointAxis axis, JointAxisConfig config) {
    _axes[axis.index] = config;
    _applyIfMounted();
  }

  @override
  bool get collisionsEnabled => _collisionsEnabled;
  @override
  set collisionsEnabled(bool value) {
    _collisionsEnabled = value;
    _applyIfMounted();
  }

  @override
  void onMount() {
    _insertJoint(
      (world, bodyA, bodyB) => world.createGenericJoint(
        bodyA,
        bodyB,
        anchorA: _localAnchorA,
        basisA: _localBasisA,
        anchorB: _localAnchorB,
        basisB: _localBasisB,
        axes: _axes,
        collisionsEnabled: _collisionsEnabled,
      ),
    );
  }

  @override
  void _applyToNative(RapierWorld world, int handle) {
    world.updateGenericJoint(
      handle,
      anchorA: _localAnchorA,
      basisA: _localBasisA,
      anchorB: _localAnchorB,
      basisB: _localBasisB,
      axes: _axes,
      collisionsEnabled: _collisionsEnabled,
    );
  }

  @override
  void onUnmount() => _destroyJoint();
}
