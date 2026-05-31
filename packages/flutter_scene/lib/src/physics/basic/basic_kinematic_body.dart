import 'package:flutter_scene/src/physics/basic/basic_collider.dart';
import 'package:flutter_scene/src/physics/basic/basic_world.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:vector_math/vector_math.dart';

/// Pure-Dart [RigidBody] implementation. Always [BodyType.kinematic];
/// the user moves the owning node's transform directly and the body
/// records velocity for components that read it. There is no dynamics
/// solver in the basic backend, so force and impulse APIs are no-ops.
///
/// For fully simulated rigid bodies, depend on a backend package that
/// ships a constraint solver. The constructor rejects
/// [BodyType.dynamic_] with a clear error to make the limitation
/// obvious instead of silently producing wrong results.
class BasicKinematicBody extends RigidBody {
  BasicKinematicBody({
    BodyType type = BodyType.kinematic,
    double? mass,
    Matrix3? inertiaTensor,
    Vector3? linearVelocity,
    Vector3? angularVelocity,
    double linearDamping = 0,
    double angularDamping = 0,
    bool useGravity = false,
    bool ccdEnabled = false,
    Vector3? linearAxisLocks,
    Vector3? angularAxisLocks,
  }) : _type = _checkType(type),
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

  static BodyType _checkType(BodyType type) {
    if (type == BodyType.dynamic_) {
      throw StateError(
        'BasicPhysicsWorld does not support BodyType.dynamic_. Depend on '
        'a physics backend package with a constraint solver to simulate '
        'dynamic bodies.',
      );
    }
    return type;
  }

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

  BasicPhysicsWorld? _world;

  @override
  BodyType get type => _type;

  @override
  double? get mass => _mass;
  @override
  set mass(double? value) => _mass = value;

  @override
  Matrix3? get inertiaTensor => _inertiaTensor;
  @override
  set inertiaTensor(Matrix3? value) => _inertiaTensor = value;

  @override
  Vector3 get linearVelocity => _linearVelocity;
  @override
  set linearVelocity(Vector3 value) => _linearVelocity = value;

  @override
  Vector3 get angularVelocity => _angularVelocity;
  @override
  set angularVelocity(Vector3 value) => _angularVelocity = value;

  @override
  double get linearDamping => _linearDamping;
  @override
  set linearDamping(double value) => _linearDamping = value;

  @override
  double get angularDamping => _angularDamping;
  @override
  set angularDamping(double value) => _angularDamping = value;

  @override
  bool get useGravity => _useGravity;
  @override
  set useGravity(bool value) => _useGravity = value;

  @override
  bool get ccdEnabled => _ccdEnabled;
  @override
  set ccdEnabled(bool value) => _ccdEnabled = value;

  @override
  Vector3 get linearAxisLocks => _linearAxisLocks;
  @override
  set linearAxisLocks(Vector3 value) => _linearAxisLocks = value;

  @override
  Vector3 get angularAxisLocks => _angularAxisLocks;
  @override
  set angularAxisLocks(Vector3 value) => _angularAxisLocks = value;

  @override
  bool get isSleeping => _sleeping;

  @override
  void wakeUp() => _sleeping = false;

  @override
  void putToSleep() => _sleeping = true;

  /// No-op in the basic backend. There is no constraint solver, so
  /// applied forces have nowhere to integrate. Kept on the API surface
  /// for portability: code written against the abstract [RigidBody]
  /// works against any backend.
  @override
  void applyForce(Vector3 force, {Vector3? atWorldPoint}) {}

  @override
  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint}) {}

  @override
  void applyTorque(Vector3 torque) {}

  @override
  void applyAngularImpulse(Vector3 impulse) {}

  @override
  void onMount() {
    final world = findAncestorWorld(node);
    if (world == null) return;
    _world = world;
    world.registerBody(this);
  }

  @override
  void onUnmount() {
    _world?.unregisterBody(this);
    _world = null;
  }
}
