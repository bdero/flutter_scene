import 'package:box3d/box3d.dart' as b3;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'box3d_physics_world.dart';

/// [RigidBody] backed by box3d.
///
/// Registers with the nearest ancestor [Box3dPhysicsWorld] on mount and
/// creates a box3d body at the owning node's world transform. Velocity and
/// sleep state read live from box3d; other properties are cached and pushed
/// on each setter.
///
/// TODO(box3d-mass-override): [mass] and [inertiaTensor] are stored but not
/// pushed to box3d, which derives mass and inertia from collider density.
/// Applying an explicit mass needs box3d's SetMassData, not yet exposed by
/// the box3d package.
class Box3dRigidBody extends RigidBody {
  Box3dRigidBody({
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

  BodyType _type;
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

  Box3dPhysicsWorld? _world;
  b3.Box3dBody? _body;

  /// The box3d body once mounted, or null. Used by [Box3dCollider] to
  /// attach shapes to the right body.
  b3.Box3dBody? get nativeBody => _body;

  static b3.Box3dBodyType _kind(BodyType type) => switch (type) {
    BodyType.fixed => b3.Box3dBodyType.static_,
    BodyType.kinematic => b3.Box3dBodyType.kinematic,
    BodyType.dynamic_ => b3.Box3dBodyType.dynamic_,
  };

  void _applyLocks() {
    final body = _body;
    if (body == null) return;
    body.setMotionLocks(
      linearX: _linearAxisLocks.x == 0,
      linearY: _linearAxisLocks.y == 0,
      linearZ: _linearAxisLocks.z == 0,
      angularX: _angularAxisLocks.x == 0,
      angularY: _angularAxisLocks.y == 0,
      angularZ: _angularAxisLocks.z == 0,
    );
  }

  @override
  void onMount() {
    final world = findAncestorBox3dWorld(node);
    if (world == null) return;
    _world = world;
    final transform = node.globalTransform;
    final body = world.nativeWorld.createBody(
      type: _kind(_type),
      position: transform.getTranslation(),
      rotation: Quaternion.fromRotation(transform.getRotation()),
    );
    _body = body;
    world.registerBody(body, node, _type);

    body.linearVelocity = _linearVelocity;
    body.angularVelocity = _angularVelocity;
    if (_linearDamping != 0) body.linearDamping = _linearDamping;
    if (_angularDamping != 0) body.angularDamping = _angularDamping;
    if (!_useGravity) body.gravityScale = 0;
    if (_ccdEnabled) body.isBullet = true;
    _applyLocks();
  }

  @override
  void onUnmount() {
    final world = _world;
    final body = _body;
    if (world != null && body != null) {
      world.unregisterBody(body.handle);
      body.destroy();
    }
    _world = null;
    _body = null;
  }

  @override
  void fixedUpdate(double fixedDt) {
    // Drive a kinematic body from its node transform each step so it sweeps
    // through the simulation.
    if (_type != BodyType.kinematic) return;
    final body = _body;
    if (body == null) return;
    final transform = node.globalTransform;
    body.setTransform(
      transform.getTranslation(),
      Quaternion.fromRotation(transform.getRotation()),
    );
  }

  @override
  BodyType get type => _type;
  set type(BodyType value) {
    if (_type == value) return;
    _type = value;
    _body?.type = _kind(value);
  }

  @override
  double? get mass => _mass;
  @override
  set mass(double? value) => _mass = value;

  @override
  Matrix3? get inertiaTensor => _inertiaTensor;
  @override
  set inertiaTensor(Matrix3? value) => _inertiaTensor = value;

  @override
  Vector3 get linearVelocity => _body?.linearVelocity ?? _linearVelocity;
  @override
  set linearVelocity(Vector3 value) {
    _linearVelocity = value;
    _body?.linearVelocity = value;
  }

  @override
  Vector3 get angularVelocity => _body?.angularVelocity ?? _angularVelocity;
  @override
  set angularVelocity(Vector3 value) {
    _angularVelocity = value;
    _body?.angularVelocity = value;
  }

  @override
  double get linearDamping => _linearDamping;
  @override
  set linearDamping(double value) {
    _linearDamping = value;
    _body?.linearDamping = value;
  }

  @override
  double get angularDamping => _angularDamping;
  @override
  set angularDamping(double value) {
    _angularDamping = value;
    _body?.angularDamping = value;
  }

  @override
  bool get useGravity => _useGravity;
  @override
  set useGravity(bool value) {
    _useGravity = value;
    _body?.gravityScale = value ? 1.0 : 0.0;
  }

  @override
  bool get ccdEnabled => _ccdEnabled;
  @override
  set ccdEnabled(bool value) {
    _ccdEnabled = value;
    _body?.isBullet = value;
  }

  @override
  Vector3 get linearAxisLocks => _linearAxisLocks;
  @override
  set linearAxisLocks(Vector3 value) {
    _linearAxisLocks = value;
    _applyLocks();
  }

  @override
  Vector3 get angularAxisLocks => _angularAxisLocks;
  @override
  set angularAxisLocks(Vector3 value) {
    _angularAxisLocks = value;
    _applyLocks();
  }

  @override
  bool get isSleeping {
    final body = _body;
    return body != null ? !body.isAwake : _sleeping;
  }

  @override
  void wakeUp() {
    _sleeping = false;
    _body?.wakeUp();
  }

  @override
  void putToSleep() {
    _sleeping = true;
    _body?.sleep();
  }

  @override
  void applyForce(Vector3 force, {Vector3? atWorldPoint}) =>
      _body?.applyForce(force, point: atWorldPoint);

  @override
  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint}) =>
      _body?.applyImpulse(impulse, point: atWorldPoint);

  @override
  void applyTorque(Vector3 torque) => _body?.applyTorque(torque);

  @override
  void applyAngularImpulse(Vector3 impulse) =>
      _body?.applyAngularImpulse(impulse);
}
