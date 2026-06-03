// dart:js_interop implementation of RapierBindings: drives the shim as a
// WebAssembly module. Functions are called on the instance's exports;
// pointers are byte offsets into the module's linear memory, and structs
// are marshalled at those offsets with the layouts the native bindings
// describe. One [JsWasmRuntime] (one module instance) can host several
// worlds; this owns one world plus its reusable scratch offsets.
//
// Handles are the shim's packed u64 values, carried across the boundary
// as BigInt. They round-trip exactly while they fit in 53 bits; beyond
// that the web loses precision (TODO(web-handle-precision): represent
// handles losslessly, e.g. as a low/high pair, if generation counts ever
// grow that large).

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/wasm_runtime_web.dart';
import 'package:vector_math/vector_math.dart';

@JS('BigInt')
external JSBigInt _bigInt(JSAny value);

@JS('Number')
external JSNumber _number(JSAny value);

/// A [RapierBindings] backed by a WebAssembly instance of the shim.
class WasmRapierBindings extends RapierBindings {
  WasmRapierBindings(this._runtime) {
    _world = _invokeInt('fsr_world_new', const []);
    // Reusable scratch, sized to the largest struct of each kind. Offsets
    // are stable for the world's lifetime and released in [dispose].
    _readScratch = _runtime.alloc(16); // up to 4 floats
    _hitScratch = _runtime.alloc(40); // FsrHit
    _eventScratch = _runtime.alloc(32); // FsrCollisionEvent
    _contactScratch = _runtime.alloc(32); // FsrContactPoint
    _characterScratch = _runtime.alloc(16); // FsrCharacterMovement
    _framesScratch = _runtime.alloc(56); // 14 floats
    _axesScratch = _runtime.alloc(192); // 6 * FsrJointAxis (32 each)
  }

  final JsWasmRuntime _runtime;
  late final int _world;
  late final int _readScratch;
  late final int _hitScratch;
  late final int _eventScratch;
  late final int _contactScratch;
  late final int _characterScratch;
  late final int _framesScratch;
  late final int _axesScratch;

  JSObject get _exports => _runtime.exports;

  // ---- call + argument helpers -------------------------------------------

  JSAny? _invoke(String name, List<JSAny?> args) =>
      _exports.callMethodVarArgs(name.toJS, args);

  int _invokeInt(String name, List<JSAny?> args) =>
      (_invoke(name, args)! as JSNumber).toDartInt;

  // u64 return (a BigInt) reduced to an int the same way struct handle
  // fields are read, so a returned handle and a stored handle match.
  int _invokeHandle(String name, List<JSAny?> args) =>
      _number(_invoke(name, args)!).toDartDouble.toInt();

  JSNumber _f(double v) => v.toJS;
  JSNumber _i(int v) => v.toJS;
  JSBigInt _h(int handle) => _bigInt(handle.toJS);
  JSNumber _b(bool v) => (v ? 1 : 0).toJS;
  JSNumber get _w => _world.toJS;

  // u64 read from a struct field as low + high * 2^32 (matches Number()
  // applied to the BigInt return path).
  int _readHandle(int ptr) {
    final low = _runtime.readU32(ptr);
    final high = _runtime.readU32(ptr + 4);
    return low + high * 0x100000000;
  }

  // ---- lifecycle ----------------------------------------------------------

  @override
  void setGravity(double x, double y, double z) =>
      _invoke('fsr_world_set_gravity', [_w, _f(x), _f(y), _f(z)]);

  @override
  void step(double dt) => _invoke('fsr_world_step', [_w, _f(dt)]);

  @override
  void dispose() {
    _invoke('fsr_world_destroy', [_w]);
    _runtime.free(_readScratch, 16);
    _runtime.free(_hitScratch, 40);
    _runtime.free(_eventScratch, 32);
    _runtime.free(_contactScratch, 32);
    _runtime.free(_characterScratch, 16);
    _runtime.free(_framesScratch, 56);
    _runtime.free(_axesScratch, 192);
  }

  // ---- bodies -------------------------------------------------------------

  @override
  int createBody(
    int kind,
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
    double additionalMass,
  ) => _invokeHandle('fsr_body_create', [
    _w,
    _i(kind),
    _f(px),
    _f(py),
    _f(pz),
    _f(qx),
    _f(qy),
    _f(qz),
    _f(qw),
    _f(additionalMass),
  ]);

  @override
  void destroyBody(int handle) => _invoke('fsr_body_destroy', [_w, _h(handle)]);

  Vector3 _readVec3(int ptr) => Vector3(
    _runtime.readF32(ptr),
    _runtime.readF32(ptr + 4),
    _runtime.readF32(ptr + 8),
  );

  @override
  Vector3 bodyTranslation(int handle) {
    _invoke('fsr_body_translation', [_w, _h(handle), _i(_readScratch)]);
    return _readVec3(_readScratch);
  }

  @override
  Quaternion bodyRotation(int handle) {
    _invoke('fsr_body_rotation', [_w, _h(handle), _i(_readScratch)]);
    return Quaternion(
      _runtime.readF32(_readScratch),
      _runtime.readF32(_readScratch + 4),
      _runtime.readF32(_readScratch + 8),
      _runtime.readF32(_readScratch + 12),
    );
  }

  @override
  Vector3 bodyLinearVelocity(int handle) {
    _invoke('fsr_body_linear_velocity', [_w, _h(handle), _i(_readScratch)]);
    return _readVec3(_readScratch);
  }

  @override
  Vector3 bodyAngularVelocity(int handle) {
    _invoke('fsr_body_angular_velocity', [_w, _h(handle), _i(_readScratch)]);
    return _readVec3(_readScratch);
  }

  @override
  void setBodyLinearVelocity(
    int handle,
    double x,
    double y,
    double z,
    bool wakeUp,
  ) => _invoke('fsr_body_set_linear_velocity', [
    _w,
    _h(handle),
    _f(x),
    _f(y),
    _f(z),
    _b(wakeUp),
  ]);

  @override
  void setBodyAngularVelocity(
    int handle,
    double x,
    double y,
    double z,
    bool wakeUp,
  ) => _invoke('fsr_body_set_angular_velocity', [
    _w,
    _h(handle),
    _f(x),
    _f(y),
    _f(z),
    _b(wakeUp),
  ]);

  @override
  void setBodyLinearDamping(int handle, double damping) =>
      _invoke('fsr_body_set_linear_damping', [_w, _h(handle), _f(damping)]);

  @override
  void setBodyAngularDamping(int handle, double damping) =>
      _invoke('fsr_body_set_angular_damping', [_w, _h(handle), _f(damping)]);

  @override
  void setBodyAdditionalMass(int handle, double additionalMass) => _invoke(
    'fsr_body_set_additional_mass',
    [_w, _h(handle), _f(additionalMass)],
  );

  @override
  void setBodyNextKinematicPose(
    int handle,
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
  ) => _invoke('fsr_body_set_next_kinematic_pose', [
    _w,
    _h(handle),
    _f(px),
    _f(py),
    _f(pz),
    _f(qx),
    _f(qy),
    _f(qz),
    _f(qw),
  ]);

  @override
  void setBodyLockedAxes(int handle, int bits) =>
      _invoke('fsr_body_set_locked_axes', [_w, _h(handle), _i(bits)]);

  @override
  void setBodyGravityScale(int handle, double scale) =>
      _invoke('fsr_body_set_gravity_scale', [_w, _h(handle), _f(scale)]);

  @override
  void setBodyCcdEnabled(int handle, bool enabled) =>
      _invoke('fsr_body_set_ccd_enabled', [_w, _h(handle), _b(enabled)]);

  @override
  void wakeBody(int handle) => _invoke('fsr_body_wake_up', [_w, _h(handle)]);

  @override
  void sleepBody(int handle) => _invoke('fsr_body_sleep', [_w, _h(handle)]);

  @override
  bool isBodySleeping(int handle) =>
      _invokeInt('fsr_body_is_sleeping', [_w, _h(handle)]) != 0;

  @override
  void applyBodyForce(
    int handle,
    double fx,
    double fy,
    double fz,
    bool hasPoint,
    double px,
    double py,
    double pz,
  ) => _invoke('fsr_body_apply_force', [
    _w,
    _h(handle),
    _f(fx),
    _f(fy),
    _f(fz),
    _b(hasPoint),
    _f(px),
    _f(py),
    _f(pz),
  ]);

  @override
  void applyBodyImpulse(
    int handle,
    double ix,
    double iy,
    double iz,
    bool hasPoint,
    double px,
    double py,
    double pz,
  ) => _invoke('fsr_body_apply_impulse', [
    _w,
    _h(handle),
    _f(ix),
    _f(iy),
    _f(iz),
    _b(hasPoint),
    _f(px),
    _f(py),
    _f(pz),
  ]);

  @override
  void applyBodyTorque(int handle, double x, double y, double z) =>
      _invoke('fsr_body_apply_torque', [_w, _h(handle), _f(x), _f(y), _f(z)]);

  @override
  void applyBodyAngularImpulse(int handle, double x, double y, double z) =>
      _invoke('fsr_body_apply_angular_impulse', [
        _w,
        _h(handle),
        _f(x),
        _f(y),
        _f(z),
      ]);

  // ---- colliders ----------------------------------------------------------

  @override
  int colliderSphere(
    int bodyHandle,
    double radius,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) => _invokeHandle('fsr_collider_sphere', [
    _w,
    _h(bodyHandle),
    _f(radius),
    _f(material.friction),
    _f(material.restitution),
    _f(material.density),
    _b(isTrigger),
    _f(tx),
    _f(ty),
    _f(tz),
    _f(rx),
    _f(ry),
    _f(rz),
    _f(rw),
  ]);

  @override
  int colliderBox(
    int bodyHandle,
    double hx,
    double hy,
    double hz,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) => _invokeHandle('fsr_collider_box', [
    _w,
    _h(bodyHandle),
    _f(hx),
    _f(hy),
    _f(hz),
    _f(material.friction),
    _f(material.restitution),
    _f(material.density),
    _b(isTrigger),
    _f(tx),
    _f(ty),
    _f(tz),
    _f(rx),
    _f(ry),
    _f(rz),
    _f(rw),
  ]);

  @override
  int colliderCapsule(
    int bodyHandle,
    double halfHeight,
    double radius,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) => _invokeHandle('fsr_collider_capsule', [
    _w,
    _h(bodyHandle),
    _f(halfHeight),
    _f(radius),
    _f(material.friction),
    _f(material.restitution),
    _f(material.density),
    _b(isTrigger),
    _f(tx),
    _f(ty),
    _f(tz),
    _f(rx),
    _f(ry),
    _f(rz),
    _f(rw),
  ]);

  @override
  int colliderCylinder(
    int bodyHandle,
    double halfHeight,
    double radius,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) => _invokeHandle('fsr_collider_cylinder', [
    _w,
    _h(bodyHandle),
    _f(halfHeight),
    _f(radius),
    _f(material.friction),
    _f(material.restitution),
    _f(material.density),
    _b(isTrigger),
    _f(tx),
    _f(ty),
    _f(tz),
    _f(rx),
    _f(ry),
    _f(rz),
    _f(rw),
  ]);

  @override
  int? colliderConvexHull(
    int bodyHandle,
    Float32List points,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) {
    final ptr = _runtime.alloc(points.length * 4);
    try {
      _runtime.writeF32List(ptr, points);
      final handle = _invokeHandle('fsr_collider_convex_hull', [
        _w,
        _h(bodyHandle),
        _i(ptr),
        _i(points.length ~/ 3),
        _f(material.friction),
        _f(material.restitution),
        _f(material.density),
        _b(isTrigger),
        _f(tx),
        _f(ty),
        _f(tz),
        _f(rx),
        _f(ry),
        _f(rz),
        _f(rw),
      ]);
      return _isInvalidHandle(handle) ? null : handle;
    } finally {
      _runtime.free(ptr, points.length * 4);
    }
  }

  @override
  int? colliderTriMesh(
    int bodyHandle,
    Float32List vertices,
    Uint32List indices,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) {
    final vBytes = vertices.length * 4;
    final iBytes = indices.length * 4;
    final vPtr = _runtime.alloc(vBytes);
    final iPtr = _runtime.alloc(iBytes);
    try {
      _runtime.writeF32List(vPtr, vertices);
      for (var i = 0; i < indices.length; i++) {
        _runtime.writeU32(iPtr + i * 4, indices[i]);
      }
      final handle = _invokeHandle('fsr_collider_trimesh', [
        _w,
        _h(bodyHandle),
        _i(vPtr),
        _i(vertices.length ~/ 3),
        _i(iPtr),
        _i(indices.length ~/ 3),
        _f(material.friction),
        _f(material.restitution),
        _f(material.density),
        _b(isTrigger),
        _f(tx),
        _f(ty),
        _f(tz),
        _f(rx),
        _f(ry),
        _f(rz),
        _f(rw),
      ]);
      return _isInvalidHandle(handle) ? null : handle;
    } finally {
      _runtime.free(vPtr, vBytes);
      _runtime.free(iPtr, iBytes);
    }
  }

  @override
  int colliderHeightField(
    int bodyHandle,
    int nrows,
    int ncols,
    Float32List heights,
    double scaleX,
    double scaleY,
    double scaleZ,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) {
    final bytes = heights.length * 4;
    final ptr = _runtime.alloc(bytes);
    try {
      _runtime.writeF32List(ptr, heights);
      return _invokeHandle('fsr_collider_heightfield', [
        _w,
        _h(bodyHandle),
        _i(nrows),
        _i(ncols),
        _i(ptr),
        _f(scaleX),
        _f(scaleY),
        _f(scaleZ),
        _f(material.friction),
        _f(material.restitution),
        _f(material.density),
        _b(isTrigger),
        _f(tx),
        _f(ty),
        _f(tz),
        _f(rx),
        _f(ry),
        _f(rz),
        _f(rw),
      ]);
    } finally {
      _runtime.free(ptr, bytes);
    }
  }

  // Number(u64::MAX) rounds to 2^64; any real handle stays well under
  // 2^53, so a value at or above 2^53 is the cooking-failure sentinel.
  bool _isInvalidHandle(int handle) => handle >= 0x20000000000000;

  @override
  void setColliderMaterial(int handle, PhysicsMaterial material) =>
      _invoke('fsr_collider_set_material', [
        _w,
        _h(handle),
        _f(material.friction),
        _f(material.restitution),
        _f(material.density),
      ]);

  @override
  void setColliderCollisionGroups(int handle, int memberships, int filter) =>
      _invoke('fsr_collider_set_collision_groups', [
        _w,
        _h(handle),
        _i(memberships),
        _i(filter),
      ]);

  @override
  void setColliderSensor(int handle, bool isSensor) =>
      _invoke('fsr_collider_set_sensor', [_w, _h(handle), _b(isSensor)]);

  @override
  void setColliderLocalPose(
    int handle,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  ) => _invoke('fsr_collider_set_local_pose', [
    _w,
    _h(handle),
    _f(tx),
    _f(ty),
    _f(tz),
    _f(rx),
    _f(ry),
    _f(rz),
    _f(rw),
  ]);

  @override
  void destroyCollider(int handle) =>
      _invoke('fsr_collider_destroy', [_w, _h(handle)]);

  // ---- joints -------------------------------------------------------------

  @override
  int jointFixed(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => _invokeHandle('fsr_joint_fixed', [
    _w,
    _h(bodyA),
    _h(bodyB),
    _f(anchorA.x),
    _f(anchorA.y),
    _f(anchorA.z),
    _f(anchorB.x),
    _f(anchorB.y),
    _f(anchorB.z),
    _b(collisionsEnabled),
  ]);

  @override
  int jointSpherical(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => _invokeHandle('fsr_joint_spherical', [
    _w,
    _h(bodyA),
    _h(bodyB),
    _f(anchorA.x),
    _f(anchorA.y),
    _f(anchorA.z),
    _f(anchorB.x),
    _f(anchorB.y),
    _f(anchorB.z),
    _b(collisionsEnabled),
  ]);

  List<JSAny?> _axisArgs(
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  ) {
    final hasLimits = lowerLimit != null && upperLimit != null;
    final hasMotor = motorTargetVelocity != null && motorMaxForce != null;
    return [
      _f(axis.x),
      _f(axis.y),
      _f(axis.z),
      _f(anchorA.x),
      _f(anchorA.y),
      _f(anchorA.z),
      _f(anchorB.x),
      _f(anchorB.y),
      _f(anchorB.z),
      _b(hasLimits),
      _f(lowerLimit ?? 0),
      _f(upperLimit ?? 0),
      _b(hasMotor),
      _f(motorTargetVelocity ?? 0),
      _f(motorMaxForce ?? 0),
      _b(collisionsEnabled),
    ];
  }

  @override
  int jointRevolute(
    int bodyA,
    int bodyB,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  ) => _invokeHandle('fsr_joint_revolute', [
    _w,
    _h(bodyA),
    _h(bodyB),
    ..._axisArgs(
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
    ),
  ]);

  @override
  int jointPrismatic(
    int bodyA,
    int bodyB,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  ) => _invokeHandle('fsr_joint_prismatic', [
    _w,
    _h(bodyA),
    _h(bodyB),
    ..._axisArgs(
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
    ),
  ]);

  @override
  int jointGeneric(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Quaternion basisA,
    Vector3 anchorB,
    Quaternion basisB,
    List<JointAxisConfig> axes,
    bool collisionsEnabled,
  ) {
    _fillGenericJointBuffers(anchorA, basisA, anchorB, basisB, axes);
    return _invokeHandle('fsr_joint_generic', [
      _w,
      _h(bodyA),
      _h(bodyB),
      _i(_framesScratch),
      _b(collisionsEnabled),
      _i(_axesScratch),
    ]);
  }

  @override
  void jointUpdateFixed(
    int joint,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => _invoke('fsr_joint_update_fixed', [
    _w,
    _h(joint),
    _f(anchorA.x),
    _f(anchorA.y),
    _f(anchorA.z),
    _f(anchorB.x),
    _f(anchorB.y),
    _f(anchorB.z),
    _b(collisionsEnabled),
  ]);

  @override
  void jointUpdateSpherical(
    int joint,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => _invoke('fsr_joint_update_spherical', [
    _w,
    _h(joint),
    _f(anchorA.x),
    _f(anchorA.y),
    _f(anchorA.z),
    _f(anchorB.x),
    _f(anchorB.y),
    _f(anchorB.z),
    _b(collisionsEnabled),
  ]);

  @override
  void jointUpdateRevolute(
    int joint,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  ) => _invoke('fsr_joint_update_revolute', [
    _w,
    _h(joint),
    ..._axisArgs(
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
    ),
  ]);

  @override
  void jointUpdatePrismatic(
    int joint,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  ) => _invoke('fsr_joint_update_prismatic', [
    _w,
    _h(joint),
    ..._axisArgs(
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
    ),
  ]);

  @override
  void jointUpdateGeneric(
    int joint,
    Vector3 anchorA,
    Quaternion basisA,
    Vector3 anchorB,
    Quaternion basisB,
    List<JointAxisConfig> axes,
    bool collisionsEnabled,
  ) {
    _fillGenericJointBuffers(anchorA, basisA, anchorB, basisB, axes);
    _invoke('fsr_joint_update_generic', [
      _w,
      _h(joint),
      _i(_framesScratch),
      _b(collisionsEnabled),
      _i(_axesScratch),
    ]);
  }

  @override
  void destroyJoint(int handle) =>
      _invoke('fsr_joint_destroy', [_w, _h(handle)]);

  // Packs the two local frames (14 floats) and six per-axis configs (32
  // bytes each) into the reusable scratch buffers, matching the
  // FsrJointAxis field layout.
  void _fillGenericJointBuffers(
    Vector3 anchorA,
    Quaternion basisA,
    Vector3 anchorB,
    Quaternion basisB,
    List<JointAxisConfig> axes,
  ) {
    _runtime.writeF32List(_framesScratch, [
      anchorA.x,
      anchorA.y,
      anchorA.z,
      basisA.x,
      basisA.y,
      basisA.z,
      basisA.w,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      basisB.x,
      basisB.y,
      basisB.z,
      basisB.w,
    ]);
    for (var i = 0; i < 6; i++) {
      final cfg = axes[i];
      final motor = cfg.motor;
      final base = _axesScratch + i * 32;
      _runtime.writeU8(base, cfg.motion.index);
      _runtime.writeU8(base + 1, motor != null ? 1 : 0);
      _runtime.writeU8(base + 2, motor?.model.index ?? 0);
      _runtime.writeF32(base + 4, cfg.lowerLimit);
      _runtime.writeF32(base + 8, cfg.upperLimit);
      _runtime.writeF32(base + 12, motor?.targetPosition ?? 0);
      _runtime.writeF32(base + 16, motor?.targetVelocity ?? 0);
      _runtime.writeF32(base + 20, motor?.stiffness ?? 0);
      _runtime.writeF32(base + 24, motor?.damping ?? 0);
      _runtime.writeF32(base + 28, motor?.maxForce ?? double.infinity);
    }
  }

  // ---- queries ------------------------------------------------------------

  // FsrHit: collider u64 @0, distance @8, point @12..20, normal @24..32.
  RawHit _readHit() => RawHit(
    collider: _readHandle(_hitScratch),
    distance: _runtime.readF32(_hitScratch + 8),
    point: _readVec3(_hitScratch + 12),
    normal: _readVec3(_hitScratch + 24),
  );

  @override
  RawHit? raycast(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxDistance,
    int flags,
  ) {
    final hit = _invokeInt('fsr_world_raycast', [
      _w,
      _f(ox),
      _f(oy),
      _f(oz),
      _f(dx),
      _f(dy),
      _f(dz),
      _f(maxDistance),
      _i(1),
      _i(flags),
      _i(_hitScratch),
    ]);
    return hit == 0 ? null : _readHit();
  }

  @override
  List<RawHit> raycastAll(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxDistance,
    int flags,
  ) {
    final count = _invokeInt('fsr_world_raycast_all', [
      _w,
      _f(ox),
      _f(oy),
      _f(oz),
      _f(dx),
      _f(dy),
      _f(dz),
      _f(maxDistance),
      _i(1),
      _i(flags),
    ]);
    final results = <RawHit>[];
    for (var i = 0; i < count; i++) {
      if (_invokeInt('fsr_world_query_result_at', [
            _w,
            _i(i),
            _i(_hitScratch),
          ]) ==
          0) {
        continue;
      }
      results.add(_readHit());
    }
    return results;
  }

  List<int> _drainColliderHandles(int count) {
    final handles = <int>[];
    for (var i = 0; i < count; i++) {
      if (_invokeInt('fsr_world_query_result_at', [
            _w,
            _i(i),
            _i(_hitScratch),
          ]) ==
          0) {
        continue;
      }
      handles.add(_readHandle(_hitScratch));
    }
    return handles;
  }

  @override
  List<int> overlapSphere(
    double cx,
    double cy,
    double cz,
    double radius,
    int flags,
  ) {
    final count = _invokeInt('fsr_world_overlap_sphere', [
      _w,
      _f(cx),
      _f(cy),
      _f(cz),
      _f(radius),
      _i(flags),
    ]);
    return _drainColliderHandles(count);
  }

  @override
  List<int> overlapBox(
    double cx,
    double cy,
    double cz,
    double hx,
    double hy,
    double hz,
    double qx,
    double qy,
    double qz,
    double qw,
    int flags,
  ) {
    final count = _invokeInt('fsr_world_overlap_box', [
      _w,
      _f(cx),
      _f(cy),
      _f(cz),
      _f(hx),
      _f(hy),
      _f(hz),
      _f(qx),
      _f(qy),
      _f(qz),
      _f(qw),
      _i(flags),
    ]);
    return _drainColliderHandles(count);
  }

  @override
  RawHit? shapeCastSphere(
    double ox,
    double oy,
    double oz,
    double radius,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  ) {
    final hit = _invokeInt('fsr_world_shape_cast_sphere', [
      _w,
      _f(ox),
      _f(oy),
      _f(oz),
      _f(radius),
      _f(dx),
      _f(dy),
      _f(dz),
      _f(distance),
      _i(flags),
      _i(_hitScratch),
    ]);
    return hit == 0 ? null : _readHit();
  }

  @override
  RawHit? shapeCastBox(
    double ox,
    double oy,
    double oz,
    double qx,
    double qy,
    double qz,
    double qw,
    double hx,
    double hy,
    double hz,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  ) {
    final hit = _invokeInt('fsr_world_shape_cast_box', [
      _w,
      _f(ox),
      _f(oy),
      _f(oz),
      _f(qx),
      _f(qy),
      _f(qz),
      _f(qw),
      _f(hx),
      _f(hy),
      _f(hz),
      _f(dx),
      _f(dy),
      _f(dz),
      _f(distance),
      _i(flags),
      _i(_hitScratch),
    ]);
    return hit == 0 ? null : _readHit();
  }

  @override
  RawHit? shapeCastCapsule(
    double ox,
    double oy,
    double oz,
    double qx,
    double qy,
    double qz,
    double qw,
    double halfHeight,
    double radius,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  ) {
    final hit = _invokeInt('fsr_world_shape_cast_capsule', [
      _w,
      _f(ox),
      _f(oy),
      _f(oz),
      _f(qx),
      _f(qy),
      _f(qz),
      _f(qw),
      _f(halfHeight),
      _f(radius),
      _f(dx),
      _f(dy),
      _f(dz),
      _f(distance),
      _i(flags),
      _i(_hitScratch),
    ]);
    return hit == 0 ? null : _readHit();
  }

  @override
  RawHit? shapeCastCylinder(
    double ox,
    double oy,
    double oz,
    double qx,
    double qy,
    double qz,
    double qw,
    double halfHeight,
    double radius,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  ) {
    final hit = _invokeInt('fsr_world_shape_cast_cylinder', [
      _w,
      _f(ox),
      _f(oy),
      _f(oz),
      _f(qx),
      _f(qy),
      _f(qz),
      _f(qw),
      _f(halfHeight),
      _f(radius),
      _f(dx),
      _f(dy),
      _f(dz),
      _f(distance),
      _i(flags),
      _i(_hitScratch),
    ]);
    return hit == 0 ? null : _readHit();
  }

  // ---- collision events ---------------------------------------------------

  @override
  int collisionEventCount() =>
      _invokeInt('fsr_world_collision_event_count', [_w]);

  // FsrCollisionEvent: colliderA u64 @0, colliderB u64 @8, started u8 @16,
  // sensor u8 @17, contactStart u32 @20, contactCount u32 @24.
  @override
  RawCollisionEvent? collisionEventAt(int index) {
    if (_invokeInt('fsr_world_collision_event_at', [
          _w,
          _i(index),
          _i(_eventScratch),
        ]) ==
        0) {
      return null;
    }
    return RawCollisionEvent(
      colliderA: _readHandle(_eventScratch),
      colliderB: _readHandle(_eventScratch + 8),
      started: _runtime.readU8(_eventScratch + 16) != 0,
      sensor: _runtime.readU8(_eventScratch + 17) != 0,
      contactStart: _runtime.readU32(_eventScratch + 20),
      contactCount: _runtime.readU32(_eventScratch + 24),
    );
  }

  // FsrContactPoint: point @0..8, normal @12..20, impulse @24,
  // separation @28.
  @override
  RawContactPoint? contactPointAt(int absoluteIndex) {
    if (_invokeInt('fsr_world_contact_point_at', [
          _w,
          _i(absoluteIndex),
          _i(_contactScratch),
        ]) ==
        0) {
      return null;
    }
    return RawContactPoint(
      position: _readVec3(_contactScratch),
      normal: _readVec3(_contactScratch + 12),
      impulse: _runtime.readF32(_contactScratch + 24),
      separation: _runtime.readF32(_contactScratch + 28),
    );
  }

  // ---- character controller ----------------------------------------------

  // FsrCharacterMovement: t @0..8, grounded u8 @12, sliding u8 @13.
  @override
  CharacterMovement moveCharacter(
    int collider,
    double cx,
    double cy,
    double cz,
    double dtx,
    double dty,
    double dtz,
    double deltaSeconds,
    double ux,
    double uy,
    double uz,
    double offset,
    bool slide,
    double maxSlopeClimbAngle,
    double minSlopeSlideAngle,
    double snapToGround,
    bool autostep,
    double autostepMaxHeight,
    double autostepMinWidth,
    bool autostepIncludeDynamicBodies,
    double characterMass,
  ) {
    _invoke('fsr_character_move', [
      _w,
      _h(collider),
      _f(cx),
      _f(cy),
      _f(cz),
      _f(dtx),
      _f(dty),
      _f(dtz),
      _f(deltaSeconds),
      _f(ux),
      _f(uy),
      _f(uz),
      _f(offset),
      _b(slide),
      _f(maxSlopeClimbAngle),
      _f(minSlopeSlideAngle),
      _f(snapToGround),
      _b(autostep),
      _f(autostepMaxHeight),
      _f(autostepMinWidth),
      _b(autostepIncludeDynamicBodies),
      _f(characterMass),
      _i(_characterScratch),
    ]);
    return (
      translation: _readVec3(_characterScratch),
      grounded: _runtime.readU8(_characterScratch + 12) != 0,
      slidingDownSlope: _runtime.readU8(_characterScratch + 13) != 0,
    );
  }
}
