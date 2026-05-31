import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// [RigidBody] backed by Rapier 3D.
///
/// Stage 3 scaffold: property storage exists and the abstract surface
/// compiles. Forwarding to Rapier's body interface (registration,
/// velocity/force routing, transform writeback) lands in Stage 4.
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

  @override
  void applyForce(Vector3 force, {Vector3? atWorldPoint}) {
    // Stage 4 forwards through the FFI bindings.
  }

  @override
  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint}) {}

  @override
  void applyTorque(Vector3 torque) {}

  @override
  void applyAngularImpulse(Vector3 impulse) {}
}
