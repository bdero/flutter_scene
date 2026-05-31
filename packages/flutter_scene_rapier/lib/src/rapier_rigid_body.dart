import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/rapier_world.dart';
import 'package:vector_math/vector_math.dart';

/// [RigidBody] backed by Rapier 3D.
///
/// Registers itself with the nearest ancestor [RapierWorld] on mount
/// and inserts a Rapier rigid body using the owning node's transform
/// as the initial pose. Property reads route through the native world;
/// property writes that don't yet have FFI wiring (force/impulse,
/// damping, locks) are no-ops and land in subsequent commits.
class RapierRigidBody extends RigidBody {
  RapierRigidBody({
    BodyType type = BodyType.dynamic_,
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

  final BodyType _type;
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
  bool _sleeping = false;

  RapierWorld? _world;
  int? _handle;

  /// Native body handle once mounted, or null if no ancestor
  /// [RapierWorld] was found. Exposed so colliders (added in a later
  /// commit) can attach themselves to the right body.
  int? get nativeHandle => _handle;

  /// The owning [RapierWorld], available between [onMount] and
  /// [onUnmount].
  RapierWorld? get nativeWorld => _world;

  /// Reads the body's current world translation from the native side.
  /// Convenience helper for tests and debugging.
  Vector3 readNativeTranslation() {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) {
      throw StateError('RapierRigidBody is not mounted.');
    }
    return world.readBodyTranslation(handle);
  }

  /// Reads the body's current world rotation from the native side.
  Quaternion readNativeRotation() {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) {
      throw StateError('RapierRigidBody is not mounted.');
    }
    return world.readBodyRotation(handle);
  }

  /// Reads the body's current linear velocity from the native side.
  Vector3 readNativeLinearVelocity() {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) {
      throw StateError('RapierRigidBody is not mounted.');
    }
    return world.readBodyLinearVelocity(handle);
  }

  /// Reads the body's current angular velocity from the native side.
  Vector3 readNativeAngularVelocity() {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) {
      throw StateError('RapierRigidBody is not mounted.');
    }
    return world.readBodyAngularVelocity(handle);
  }

  @override
  void onMount() {
    final world = findAncestorRapierWorld(node);
    if (world == null) return;
    _world = world;
    final transform = node.globalTransform;
    final translation = transform.getTranslation();
    final rotation = Quaternion.fromRotation(transform.getRotation());
    _handle = world.createBody(
      node: node,
      type: _type,
      position: translation,
      rotation: rotation,
      additionalMass: _mass ?? 0.0,
    );
    // Push the configured initial state into native after creation so
    // the body picks up non-default velocity/damping the user set on
    // the component before mount.
    world.setBodyLinearVelocity(_handle!, _linearVelocity, wakeUp: false);
    world.setBodyAngularVelocity(_handle!, _angularVelocity, wakeUp: false);
    if (_linearDamping != 0) {
      world.setBodyLinearDamping(_handle!, _linearDamping);
    }
    if (_angularDamping != 0) {
      world.setBodyAngularDamping(_handle!, _angularDamping);
    }
    world.setBodyGravityScale(_handle!, _useGravity ? 1.0 : 0.0);
    if (_ccdEnabled) world.setBodyCcdEnabled(_handle!, true);
    if (!_isFullyFree(_linearAxisLocks) || !_isFullyFree(_angularAxisLocks)) {
      world.setBodyLockedAxes(_handle!, _linearAxisLocks, _angularAxisLocks);
    }
  }

  static bool _isFullyFree(Vector3 v) => v.x != 0 && v.y != 0 && v.z != 0;

  @override
  void onUnmount() {
    final world = _world;
    final handle = _handle;
    if (world != null && handle != null) {
      world.destroyBody(handle);
    }
    _world = null;
    _handle = null;
  }

  @override
  BodyType get type => _type;

  @override
  double? get mass => _mass;
  @override
  set mass(double? value) {
    _mass = value;
    final w = _world, h = _handle;
    if (w != null && h != null) {
      w.setBodyAdditionalMass(h, value ?? 0.0);
    }
  }

  @override
  Matrix3? get inertiaTensor => _inertiaTensor;
  @override
  set inertiaTensor(Matrix3? value) => _inertiaTensor = value;

  @override
  Vector3 get linearVelocity {
    final w = _world, h = _handle;
    if (w != null && h != null) return w.readBodyLinearVelocity(h);
    return _linearVelocity;
  }

  @override
  set linearVelocity(Vector3 value) {
    _linearVelocity = value;
    final w = _world, h = _handle;
    if (w != null && h != null) w.setBodyLinearVelocity(h, value);
  }

  @override
  Vector3 get angularVelocity {
    final w = _world, h = _handle;
    if (w != null && h != null) return w.readBodyAngularVelocity(h);
    return _angularVelocity;
  }

  @override
  set angularVelocity(Vector3 value) {
    _angularVelocity = value;
    final w = _world, h = _handle;
    if (w != null && h != null) w.setBodyAngularVelocity(h, value);
  }

  @override
  double get linearDamping => _linearDamping;
  @override
  set linearDamping(double value) {
    _linearDamping = value;
    final w = _world, h = _handle;
    if (w != null && h != null) w.setBodyLinearDamping(h, value);
  }

  @override
  double get angularDamping => _angularDamping;
  @override
  set angularDamping(double value) {
    _angularDamping = value;
    final w = _world, h = _handle;
    if (w != null && h != null) w.setBodyAngularDamping(h, value);
  }

  @override
  bool get useGravity => _useGravity;
  @override
  set useGravity(bool value) {
    _useGravity = value;
    final w = _world, h = _handle;
    if (w != null && h != null) w.setBodyGravityScale(h, value ? 1.0 : 0.0);
  }

  @override
  bool get ccdEnabled => _ccdEnabled;
  @override
  set ccdEnabled(bool value) {
    _ccdEnabled = value;
    final w = _world, h = _handle;
    if (w != null && h != null) w.setBodyCcdEnabled(h, value);
  }

  @override
  Vector3 get linearAxisLocks => _linearAxisLocks;
  @override
  set linearAxisLocks(Vector3 value) {
    _linearAxisLocks = value;
    final w = _world, h = _handle;
    if (w != null && h != null) {
      w.setBodyLockedAxes(h, _linearAxisLocks, _angularAxisLocks);
    }
  }

  @override
  Vector3 get angularAxisLocks => _angularAxisLocks;
  @override
  set angularAxisLocks(Vector3 value) {
    _angularAxisLocks = value;
    final w = _world, h = _handle;
    if (w != null && h != null) {
      w.setBodyLockedAxes(h, _linearAxisLocks, _angularAxisLocks);
    }
  }

  @override
  bool get isSleeping {
    final w = _world, h = _handle;
    if (w != null && h != null) return w.isBodySleeping(h);
    return _sleeping;
  }

  @override
  void wakeUp() {
    _sleeping = false;
    final w = _world, h = _handle;
    if (w != null && h != null) w.wakeBody(h);
  }

  @override
  void putToSleep() {
    _sleeping = true;
    final w = _world, h = _handle;
    if (w != null && h != null) w.sleepBody(h);
  }

  @override
  void fixedUpdate(double fixedDt) {
    if (_type != BodyType.kinematic) return;
    final w = _world, h = _handle;
    if (w == null || h == null) return;
    final transform = node.globalTransform;
    final t = transform.getTranslation();
    final r = Quaternion.fromRotation(transform.getRotation());
    w.setBodyNextKinematicPose(h, t, r);
  }

  @override
  void applyForce(Vector3 force, {Vector3? atWorldPoint}) {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) return;
    world.applyBodyForce(handle, force, atWorldPoint: atWorldPoint);
  }

  @override
  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint}) {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) return;
    world.applyBodyImpulse(handle, impulse, atWorldPoint: atWorldPoint);
  }

  @override
  void applyTorque(Vector3 torque) {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) return;
    world.applyBodyTorque(handle, torque);
  }

  @override
  void applyAngularImpulse(Vector3 impulse) {
    final world = _world;
    final handle = _handle;
    if (world == null || handle == null) return;
    world.applyBodyAngularImpulse(handle, impulse);
  }
}
