import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/physics/physics_world.dart';
import 'package:flutter/foundation.dart';
import 'package:scene/scene.dart' as sim;
import 'package:vector_math/vector_math.dart';

/// A simulated rigid body attached to a [Node].
///
/// One rigid body per node; [Collider]s on the same node define its
/// collision volume. Registers with the nearest ancestor [PhysicsWorld]
/// on mount. Transform sync direction depends on [type] (see
/// [sim.BodyType]); mutating a dynamic body's node transform is treated
/// as a teleport.
/// {@category Physics}
class RigidBody extends Component {
  RigidBody({
    sim.BodyType type = sim.BodyType.dynamic_,
    double? mass,
    Matrix3? inertiaTensor,
    Vector3? linearVelocity,
    Vector3? angularVelocity,
    double linearDamping = 0,
    double angularDamping = 0,
    bool useGravity = true,
    bool ccdEnabled = false,
    Vector3? linearAxisLocks,
    Vector3? angularAxisLocks,
  }) : _type = type,
       _mass = mass,
       _inertiaTensor = inertiaTensor,
       _linearVelocity = linearVelocity ?? Vector3.zero(),
       _angularVelocity = angularVelocity ?? Vector3.zero(),
       _linearDamping = linearDamping,
       _angularDamping = angularDamping,
       _useGravity = useGravity,
       _ccdEnabled = ccdEnabled,
       _linearAxisLocks = linearAxisLocks ?? Vector3(1, 1, 1),
       _angularAxisLocks = angularAxisLocks ?? Vector3(1, 1, 1);

  PhysicsWorld? _world;
  int? _handle;

  sim.BodyType _type;
  double? _mass;
  Matrix3? _inertiaTensor;
  Vector3 _linearVelocity;
  Vector3 _angularVelocity;
  double _linearDamping;
  double _angularDamping;
  bool _useGravity;
  bool _ccdEnabled;
  Vector3 _linearAxisLocks;
  Vector3 _angularAxisLocks;

  /// The owning world while mounted.
  PhysicsWorld? get world => _world;

  /// The body's simulation handle while mounted.
  @internal
  int? get handle => _handle;

  sim.PhysicsSimulation? get _sim => _world?.simulation;

  sim.BodyType get type => _type;

  /// Changes the simulation mode in place (an elevator switching between
  /// kinematic and fixed, a prop becoming dynamic on release).
  set type(sim.BodyType value) {
    _type = value;
    final handle = _handle;
    if (handle != null) _sim!.setBodyKind(handle, value);
  }

  /// Mass in kilograms. When null the backend derives mass from the
  /// owning colliders' shapes and material densities.
  double? get mass => _mass;
  set mass(double? value) {
    _mass = value;
    final handle = _handle;
    if (handle != null && value != null) {
      _sim!.setBodyAdditionalMass(handle, value);
    }
  }

  /// Local-space inertia tensor. When null, derived from the owning
  /// colliders.
  // TODO(inertia-tensor): forward to the simulation once backends grow a
  // setter; currently stored only.
  // ignore: unnecessary_getters_setters
  Matrix3? get inertiaTensor => _inertiaTensor;
  set inertiaTensor(Matrix3? value) => _inertiaTensor = value;

  Vector3 get linearVelocity {
    final handle = _handle;
    return handle == null
        ? _linearVelocity
        : _sim!.readBodyLinearVelocity(handle);
  }

  set linearVelocity(Vector3 value) {
    _linearVelocity = value;
    final handle = _handle;
    if (handle != null) _sim!.setBodyLinearVelocity(handle, value);
  }

  Vector3 get angularVelocity {
    final handle = _handle;
    return handle == null
        ? _angularVelocity
        : _sim!.readBodyAngularVelocity(handle);
  }

  set angularVelocity(Vector3 value) {
    _angularVelocity = value;
    final handle = _handle;
    if (handle != null) _sim!.setBodyAngularVelocity(handle, value);
  }

  /// Per-step linear velocity damping in `[0, 1]`. `0` is no damping.
  double get linearDamping => _linearDamping;
  set linearDamping(double value) {
    _linearDamping = value;
    final handle = _handle;
    if (handle != null) _sim!.setBodyLinearDamping(handle, value);
  }

  /// Per-step angular velocity damping in `[0, 1]`. `0` is no damping.
  double get angularDamping => _angularDamping;
  set angularDamping(double value) {
    _angularDamping = value;
    final handle = _handle;
    if (handle != null) _sim!.setBodyAngularDamping(handle, value);
  }

  bool get useGravity => _useGravity;
  set useGravity(bool value) {
    _useGravity = value;
    final handle = _handle;
    if (handle != null) _sim!.setBodyGravityScale(handle, value ? 1 : 0);
  }

  /// Continuous collision detection, prevents fast bodies from tunneling
  /// through thin colliders.
  bool get ccdEnabled => _ccdEnabled;
  set ccdEnabled(bool value) {
    _ccdEnabled = value;
    final handle = _handle;
    if (handle != null) _sim!.setBodyCcdEnabled(handle, value);
  }

  /// Per-axis linear motion factors in `[0, 1]`, `1` free, `0` locked.
  Vector3 get linearAxisLocks => _linearAxisLocks;
  set linearAxisLocks(Vector3 value) {
    _linearAxisLocks = value;
    _pushAxisLocks();
  }

  /// Per-axis angular motion factors. See [linearAxisLocks].
  Vector3 get angularAxisLocks => _angularAxisLocks;
  set angularAxisLocks(Vector3 value) {
    _angularAxisLocks = value;
    _pushAxisLocks();
  }

  void _pushAxisLocks() {
    final handle = _handle;
    if (handle != null) {
      _sim!.setBodyAxisLocks(handle, _linearAxisLocks, _angularAxisLocks);
    }
  }

  /// Applies a continuous [force] (world space) for the current step;
  /// [atWorldPoint] makes it produce torque about the center of mass.
  void applyForce(Vector3 force, {Vector3? atWorldPoint}) {
    final handle = _handle;
    if (handle != null) {
      _sim!.applyForce(handle, force, atWorldPoint: atWorldPoint);
    }
  }

  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint}) {
    final handle = _handle;
    if (handle != null) {
      _sim!.applyImpulse(handle, impulse, atWorldPoint: atWorldPoint);
    }
  }

  void applyTorque(Vector3 torque) {
    final handle = _handle;
    if (handle != null) _sim!.applyTorque(handle, torque);
  }

  void applyAngularImpulse(Vector3 impulse) {
    final handle = _handle;
    if (handle != null) _sim!.applyAngularImpulse(handle, impulse);
  }

  bool get isSleeping {
    final handle = _handle;
    return handle != null && _sim!.isBodySleeping(handle);
  }

  void wakeUp() {
    final handle = _handle;
    if (handle != null) _sim!.wakeBody(handle);
  }

  void putToSleep() {
    final handle = _handle;
    if (handle != null) _sim!.sleepBody(handle);
  }

  /// The body's pose fresh from the simulation, unlike the node transform
  /// this is exact mid-step state (useful inside [fixedUpdate], where the
  /// interpolated node transform lags).
  (Vector3, Quaternion) readSimulationPose() {
    final handle = _handle;
    if (handle == null) {
      return (
        node.globalTransform.getTranslation(),
        Quaternion.fromRotation(node.globalTransform.getRotation()),
      );
    }
    return _sim!.readBodyPose(handle);
  }

  @override
  void onMount() {
    final world = findAncestorWorld(node);
    if (world == null) {
      throw StateError(
        'RigidBody mounted with no PhysicsWorld on an ancestor node',
      );
    }
    _world = world;
    final handle = world.simulation.createBody(
      target: NodePoseTarget(node),
      type: _type,
      additionalMass: _mass,
    );
    _handle = handle;
    final s = world.simulation;
    if (_linearVelocity.length2 > 0) {
      s.setBodyLinearVelocity(handle, _linearVelocity);
    }
    if (_angularVelocity.length2 > 0) {
      s.setBodyAngularVelocity(handle, _angularVelocity);
    }
    if (_linearDamping != 0) s.setBodyLinearDamping(handle, _linearDamping);
    if (_angularDamping != 0) s.setBodyAngularDamping(handle, _angularDamping);
    if (!_useGravity) s.setBodyGravityScale(handle, 0);
    if (_ccdEnabled) s.setBodyCcdEnabled(handle, true);
    if (_linearAxisLocks != Vector3(1, 1, 1) ||
        _angularAxisLocks != Vector3(1, 1, 1)) {
      _pushAxisLocks();
    }
  }

  @override
  void onUnmount() {
    final handle = _handle;
    if (handle != null) _sim?.destroyBody(handle);
    _handle = null;
    _world = null;
  }

  @override
  void fixedUpdate(double fixedDt) {
    if (_type != sim.BodyType.kinematic) return;
    final handle = _handle;
    if (handle == null) return;
    // Kinematic bodies follow the node; push the pose it should reach by
    // the next step so contacts see its velocity.
    final transform = node.globalTransform;
    _sim!.setBodyKinematicTargetPose(
      handle,
      transform.getTranslation(),
      Quaternion.fromRotation(transform.getRotation()),
    );
  }
}
