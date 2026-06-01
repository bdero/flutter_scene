// dart:ffi implementation of RapierBindings: calls the shim as a native
// dynamic library and owns the world pointer plus the reusable scratch
// buffers the struct-returning calls read through.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/ffi/bindings.dart' as native;
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings.dart';
import 'package:vector_math/vector_math.dart';

/// Sentinel a cooking call returns when Rapier rejects the shape (the
/// shim's `u64::MAX`). Native only; this literal cannot exist in a
/// web-compiled file, and the web backend detects rejection differently.
const int _invalidHandle = 0xFFFFFFFFFFFFFFFF;

/// A [RapierBindings] backed by the native shim over dart:ffi.
class NativeRapierBindings extends RapierBindings {
  NativeRapierBindings() : _handle = native.worldNew() {
    _finalizer.attach(this, _handle, detach: this);
  }

  static final Finalizer<Pointer<native.NativeWorld>> _finalizer =
      Finalizer<Pointer<native.NativeWorld>>(native.worldDestroy);

  final Pointer<native.NativeWorld> _handle;

  // Reusable scratch, allocated once and freed in [dispose]. The reads
  // never overlap a single call, so one buffer per result type is enough.
  late final Pointer<Float> _readBuffer = calloc<Float>(4);
  late final Pointer<native.FsrHit> _hitBuffer = calloc<native.FsrHit>();
  late final Pointer<native.FsrCollisionEvent> _eventBuffer =
      calloc<native.FsrCollisionEvent>();
  late final Pointer<native.FsrContactPoint> _contactBuffer =
      calloc<native.FsrContactPoint>();
  late final Pointer<Float> _jointFramesBuffer = calloc<Float>(14);
  late final Pointer<native.FsrJointAxis> _jointAxesBuffer =
      calloc<native.FsrJointAxis>(6);
  late final Pointer<native.FsrCharacterMovement> _characterBuffer =
      calloc<native.FsrCharacterMovement>();

  @override
  void setGravity(double x, double y, double z) =>
      native.worldSetGravity(_handle, x, y, z);

  @override
  void step(double dt) => native.worldStep(_handle, dt);

  @override
  void dispose() {
    _finalizer.detach(this);
    native.worldDestroy(_handle);
    calloc.free(_readBuffer);
    calloc.free(_hitBuffer);
    calloc.free(_eventBuffer);
    calloc.free(_contactBuffer);
    calloc.free(_jointFramesBuffer);
    calloc.free(_jointAxesBuffer);
    calloc.free(_characterBuffer);
  }

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
  ) => native.bodyCreate(
    _handle,
    kind,
    px,
    py,
    pz,
    qx,
    qy,
    qz,
    qw,
    additionalMass,
  );

  @override
  void destroyBody(int handle) => native.bodyDestroy(_handle, handle);

  @override
  Vector3 bodyTranslation(int handle) {
    native.bodyTranslation(_handle, handle, _readBuffer);
    return Vector3(_readBuffer[0], _readBuffer[1], _readBuffer[2]);
  }

  @override
  Quaternion bodyRotation(int handle) {
    native.bodyRotation(_handle, handle, _readBuffer);
    return Quaternion(
      _readBuffer[0],
      _readBuffer[1],
      _readBuffer[2],
      _readBuffer[3],
    );
  }

  @override
  Vector3 bodyLinearVelocity(int handle) {
    native.bodyLinearVelocity(_handle, handle, _readBuffer);
    return Vector3(_readBuffer[0], _readBuffer[1], _readBuffer[2]);
  }

  @override
  Vector3 bodyAngularVelocity(int handle) {
    native.bodyAngularVelocity(_handle, handle, _readBuffer);
    return Vector3(_readBuffer[0], _readBuffer[1], _readBuffer[2]);
  }

  @override
  void setBodyLinearVelocity(
    int handle,
    double x,
    double y,
    double z,
    bool wakeUp,
  ) => native.bodySetLinearVelocity(_handle, handle, x, y, z, wakeUp ? 1 : 0);

  @override
  void setBodyAngularVelocity(
    int handle,
    double x,
    double y,
    double z,
    bool wakeUp,
  ) => native.bodySetAngularVelocity(_handle, handle, x, y, z, wakeUp ? 1 : 0);

  @override
  void setBodyLinearDamping(int handle, double damping) =>
      native.bodySetLinearDamping(_handle, handle, damping);

  @override
  void setBodyAngularDamping(int handle, double damping) =>
      native.bodySetAngularDamping(_handle, handle, damping);

  @override
  void setBodyAdditionalMass(int handle, double additionalMass) =>
      native.bodySetAdditionalMass(_handle, handle, additionalMass);

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
  ) => native.bodySetNextKinematicPose(
    _handle,
    handle,
    px,
    py,
    pz,
    qx,
    qy,
    qz,
    qw,
  );

  @override
  void setBodyLockedAxes(int handle, int bits) =>
      native.bodySetLockedAxes(_handle, handle, bits);

  @override
  void setBodyGravityScale(int handle, double scale) =>
      native.bodySetGravityScale(_handle, handle, scale);

  @override
  void setBodyCcdEnabled(int handle, bool enabled) =>
      native.bodySetCcdEnabled(_handle, handle, enabled ? 1 : 0);

  @override
  void wakeBody(int handle) => native.bodyWakeUp(_handle, handle);

  @override
  void sleepBody(int handle) => native.bodySleep(_handle, handle);

  @override
  bool isBodySleeping(int handle) =>
      native.bodyIsSleeping(_handle, handle) != 0;

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
  ) => native.bodyApplyForce(
    _handle,
    handle,
    fx,
    fy,
    fz,
    hasPoint ? 1 : 0,
    px,
    py,
    pz,
  );

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
  ) => native.bodyApplyImpulse(
    _handle,
    handle,
    ix,
    iy,
    iz,
    hasPoint ? 1 : 0,
    px,
    py,
    pz,
  );

  @override
  void applyBodyTorque(int handle, double x, double y, double z) =>
      native.bodyApplyTorque(_handle, handle, x, y, z);

  @override
  void applyBodyAngularImpulse(int handle, double x, double y, double z) =>
      native.bodyApplyAngularImpulse(_handle, handle, x, y, z);

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
  ) => native.colliderSphere(
    _handle,
    bodyHandle,
    radius,
    material.friction,
    material.restitution,
    material.density,
    isTrigger ? 1 : 0,
    tx,
    ty,
    tz,
    rx,
    ry,
    rz,
    rw,
  );

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
  ) => native.colliderBox(
    _handle,
    bodyHandle,
    hx,
    hy,
    hz,
    material.friction,
    material.restitution,
    material.density,
    isTrigger ? 1 : 0,
    tx,
    ty,
    tz,
    rx,
    ry,
    rz,
    rw,
  );

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
  ) => native.colliderCapsule(
    _handle,
    bodyHandle,
    halfHeight,
    radius,
    material.friction,
    material.restitution,
    material.density,
    isTrigger ? 1 : 0,
    tx,
    ty,
    tz,
    rx,
    ry,
    rz,
    rw,
  );

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
  ) => native.colliderCylinder(
    _handle,
    bodyHandle,
    halfHeight,
    radius,
    material.friction,
    material.restitution,
    material.density,
    isTrigger ? 1 : 0,
    tx,
    ty,
    tz,
    rx,
    ry,
    rz,
    rw,
  );

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
    final ptr = calloc<Float>(points.length);
    try {
      for (var i = 0; i < points.length; i++) {
        ptr[i] = points[i];
      }
      final handle = native.colliderConvexHull(
        _handle,
        bodyHandle,
        ptr,
        points.length ~/ 3,
        material.friction,
        material.restitution,
        material.density,
        isTrigger ? 1 : 0,
        tx,
        ty,
        tz,
        rx,
        ry,
        rz,
        rw,
      );
      return handle == _invalidHandle ? null : handle;
    } finally {
      calloc.free(ptr);
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
    final vPtr = calloc<Float>(vertices.length);
    final iPtr = calloc<Uint32>(indices.length);
    try {
      for (var i = 0; i < vertices.length; i++) {
        vPtr[i] = vertices[i];
      }
      for (var i = 0; i < indices.length; i++) {
        iPtr[i] = indices[i];
      }
      final handle = native.colliderTriMesh(
        _handle,
        bodyHandle,
        vPtr,
        vertices.length ~/ 3,
        iPtr,
        indices.length ~/ 3,
        material.friction,
        material.restitution,
        material.density,
        isTrigger ? 1 : 0,
        tx,
        ty,
        tz,
        rx,
        ry,
        rz,
        rw,
      );
      return handle == _invalidHandle ? null : handle;
    } finally {
      calloc.free(vPtr);
      calloc.free(iPtr);
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
    final ptr = calloc<Float>(heights.length);
    try {
      for (var i = 0; i < heights.length; i++) {
        ptr[i] = heights[i];
      }
      return native.colliderHeightField(
        _handle,
        bodyHandle,
        nrows,
        ncols,
        ptr,
        scaleX,
        scaleY,
        scaleZ,
        material.friction,
        material.restitution,
        material.density,
        isTrigger ? 1 : 0,
        tx,
        ty,
        tz,
        rx,
        ry,
        rz,
        rw,
      );
    } finally {
      calloc.free(ptr);
    }
  }

  @override
  void setColliderMaterial(int handle, PhysicsMaterial material) =>
      native.colliderSetMaterial(
        _handle,
        handle,
        material.friction,
        material.restitution,
        material.density,
      );

  @override
  void setColliderCollisionGroups(int handle, int memberships, int filter) =>
      native.colliderSetCollisionGroups(_handle, handle, memberships, filter);

  @override
  void setColliderSensor(int handle, bool isSensor) =>
      native.colliderSetSensor(_handle, handle, isSensor ? 1 : 0);

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
  ) => native.colliderSetLocalPose(_handle, handle, tx, ty, tz, rx, ry, rz, rw);

  @override
  void destroyCollider(int handle) => native.colliderDestroy(_handle, handle);

  @override
  int jointFixed(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => native.jointFixed(
    _handle,
    bodyA,
    bodyB,
    anchorA.x,
    anchorA.y,
    anchorA.z,
    anchorB.x,
    anchorB.y,
    anchorB.z,
    collisionsEnabled ? 1 : 0,
  );

  @override
  int jointSpherical(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => native.jointSpherical(
    _handle,
    bodyA,
    bodyB,
    anchorA.x,
    anchorA.y,
    anchorA.z,
    anchorB.x,
    anchorB.y,
    anchorB.z,
    collisionsEnabled ? 1 : 0,
  );

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
  ) {
    final hasLimits = lowerLimit != null && upperLimit != null;
    final hasMotor = motorTargetVelocity != null && motorMaxForce != null;
    return native.jointRevolute(
      _handle,
      bodyA,
      bodyB,
      axis.x,
      axis.y,
      axis.z,
      anchorA.x,
      anchorA.y,
      anchorA.z,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      hasLimits ? 1 : 0,
      lowerLimit ?? 0,
      upperLimit ?? 0,
      hasMotor ? 1 : 0,
      motorTargetVelocity ?? 0,
      motorMaxForce ?? 0,
      collisionsEnabled ? 1 : 0,
    );
  }

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
  ) {
    final hasLimits = lowerLimit != null && upperLimit != null;
    final hasMotor = motorTargetVelocity != null && motorMaxForce != null;
    return native.jointPrismatic(
      _handle,
      bodyA,
      bodyB,
      axis.x,
      axis.y,
      axis.z,
      anchorA.x,
      anchorA.y,
      anchorA.z,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      hasLimits ? 1 : 0,
      lowerLimit ?? 0,
      upperLimit ?? 0,
      hasMotor ? 1 : 0,
      motorTargetVelocity ?? 0,
      motorMaxForce ?? 0,
      collisionsEnabled ? 1 : 0,
    );
  }

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
    return native.jointGeneric(
      _handle,
      bodyA,
      bodyB,
      _jointFramesBuffer,
      collisionsEnabled ? 1 : 0,
      _jointAxesBuffer,
    );
  }

  @override
  void jointUpdateFixed(
    int joint,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => native.jointUpdateFixed(
    _handle,
    joint,
    anchorA.x,
    anchorA.y,
    anchorA.z,
    anchorB.x,
    anchorB.y,
    anchorB.z,
    collisionsEnabled ? 1 : 0,
  );

  @override
  void jointUpdateSpherical(
    int joint,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  ) => native.jointUpdateSpherical(
    _handle,
    joint,
    anchorA.x,
    anchorA.y,
    anchorA.z,
    anchorB.x,
    anchorB.y,
    anchorB.z,
    collisionsEnabled ? 1 : 0,
  );

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
  ) {
    final hasLimits = lowerLimit != null && upperLimit != null;
    final hasMotor = motorTargetVelocity != null && motorMaxForce != null;
    native.jointUpdateRevolute(
      _handle,
      joint,
      axis.x,
      axis.y,
      axis.z,
      anchorA.x,
      anchorA.y,
      anchorA.z,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      hasLimits ? 1 : 0,
      lowerLimit ?? 0,
      upperLimit ?? 0,
      hasMotor ? 1 : 0,
      motorTargetVelocity ?? 0,
      motorMaxForce ?? 0,
      collisionsEnabled ? 1 : 0,
    );
  }

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
  ) {
    final hasLimits = lowerLimit != null && upperLimit != null;
    final hasMotor = motorTargetVelocity != null && motorMaxForce != null;
    native.jointUpdatePrismatic(
      _handle,
      joint,
      axis.x,
      axis.y,
      axis.z,
      anchorA.x,
      anchorA.y,
      anchorA.z,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      hasLimits ? 1 : 0,
      lowerLimit ?? 0,
      upperLimit ?? 0,
      hasMotor ? 1 : 0,
      motorTargetVelocity ?? 0,
      motorMaxForce ?? 0,
      collisionsEnabled ? 1 : 0,
    );
  }

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
    native.jointUpdateGeneric(
      _handle,
      joint,
      _jointFramesBuffer,
      collisionsEnabled ? 1 : 0,
      _jointAxesBuffer,
    );
  }

  @override
  void destroyJoint(int handle) => native.jointDestroy(_handle, handle);

  // Packs the two local frames and the six per-axis configs into the
  // reusable native scratch buffers.
  void _fillGenericJointBuffers(
    Vector3 anchorA,
    Quaternion basisA,
    Vector3 anchorB,
    Quaternion basisB,
    List<JointAxisConfig> axes,
  ) {
    final f = _jointFramesBuffer;
    f[0] = anchorA.x;
    f[1] = anchorA.y;
    f[2] = anchorA.z;
    f[3] = basisA.x;
    f[4] = basisA.y;
    f[5] = basisA.z;
    f[6] = basisA.w;
    f[7] = anchorB.x;
    f[8] = anchorB.y;
    f[9] = anchorB.z;
    f[10] = basisB.x;
    f[11] = basisB.y;
    f[12] = basisB.z;
    f[13] = basisB.w;
    for (var i = 0; i < 6; i++) {
      final cfg = axes[i];
      final motor = cfg.motor;
      final a = _jointAxesBuffer[i];
      a.motion = cfg.motion.index;
      a.hasMotor = motor != null ? 1 : 0;
      a.motorModel = motor?.model.index ?? 0;
      a.lower = cfg.lowerLimit;
      a.upper = cfg.upperLimit;
      a.targetPos = motor?.targetPosition ?? 0;
      a.targetVel = motor?.targetVelocity ?? 0;
      a.stiffness = motor?.stiffness ?? 0;
      a.damping = motor?.damping ?? 0;
      a.maxForce = motor?.maxForce ?? double.infinity;
    }
  }

  RawHit _hitFromBuffer() {
    final h = _hitBuffer.ref;
    return RawHit(
      collider: h.collider,
      distance: h.distance,
      point: Vector3(h.px, h.py, h.pz),
      normal: Vector3(h.nx, h.ny, h.nz),
    );
  }

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
    final hit = native.worldRaycast(
      _handle,
      ox,
      oy,
      oz,
      dx,
      dy,
      dz,
      maxDistance,
      1,
      flags,
      _hitBuffer,
    );
    return hit == 0 ? null : _hitFromBuffer();
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
    final count = native.worldRaycastAll(
      _handle,
      ox,
      oy,
      oz,
      dx,
      dy,
      dz,
      maxDistance,
      1,
      flags,
    );
    final results = <RawHit>[];
    for (var i = 0; i < count; i++) {
      if (native.worldQueryResultAt(_handle, i, _hitBuffer) == 0) continue;
      results.add(_hitFromBuffer());
    }
    return results;
  }

  List<int> _drainColliderHandles(int count) {
    final handles = <int>[];
    for (var i = 0; i < count; i++) {
      if (native.worldQueryResultAt(_handle, i, _hitBuffer) == 0) continue;
      handles.add(_hitBuffer.ref.collider);
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
    final count = native.worldOverlapSphere(_handle, cx, cy, cz, radius, flags);
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
    final count = native.worldOverlapBox(
      _handle,
      cx,
      cy,
      cz,
      hx,
      hy,
      hz,
      qx,
      qy,
      qz,
      qw,
      flags,
    );
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
    final hit = native.worldShapeCastSphere(
      _handle,
      ox,
      oy,
      oz,
      radius,
      dx,
      dy,
      dz,
      distance,
      flags,
      _hitBuffer,
    );
    return hit == 0 ? null : _hitFromBuffer();
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
    final hit = native.worldShapeCastBox(
      _handle,
      ox,
      oy,
      oz,
      qx,
      qy,
      qz,
      qw,
      hx,
      hy,
      hz,
      dx,
      dy,
      dz,
      distance,
      flags,
      _hitBuffer,
    );
    return hit == 0 ? null : _hitFromBuffer();
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
    final hit = native.worldShapeCastCapsule(
      _handle,
      ox,
      oy,
      oz,
      qx,
      qy,
      qz,
      qw,
      halfHeight,
      radius,
      dx,
      dy,
      dz,
      distance,
      flags,
      _hitBuffer,
    );
    return hit == 0 ? null : _hitFromBuffer();
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
    final hit = native.worldShapeCastCylinder(
      _handle,
      ox,
      oy,
      oz,
      qx,
      qy,
      qz,
      qw,
      halfHeight,
      radius,
      dx,
      dy,
      dz,
      distance,
      flags,
      _hitBuffer,
    );
    return hit == 0 ? null : _hitFromBuffer();
  }

  @override
  int collisionEventCount() => native.worldCollisionEventCount(_handle);

  @override
  RawCollisionEvent? collisionEventAt(int index) {
    if (native.worldCollisionEventAt(_handle, index, _eventBuffer) == 0) {
      return null;
    }
    final e = _eventBuffer.ref;
    return RawCollisionEvent(
      colliderA: e.colliderA,
      colliderB: e.colliderB,
      started: e.started != 0,
      sensor: e.sensor != 0,
      contactStart: e.contactStart,
      contactCount: e.contactCount,
    );
  }

  @override
  RawContactPoint? contactPointAt(int absoluteIndex) {
    if (native.worldContactPointAt(_handle, absoluteIndex, _contactBuffer) ==
        0) {
      return null;
    }
    final c = _contactBuffer.ref;
    return RawContactPoint(
      position: Vector3(c.px, c.py, c.pz),
      normal: Vector3(c.nx, c.ny, c.nz),
      impulse: c.impulse,
      separation: c.separation,
    );
  }

  @override
  CharacterMovement moveCharacter(
    int collider,
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
  ) {
    native.characterMove(
      _handle,
      collider,
      dtx,
      dty,
      dtz,
      deltaSeconds,
      ux,
      uy,
      uz,
      offset,
      slide ? 1 : 0,
      maxSlopeClimbAngle,
      minSlopeSlideAngle,
      snapToGround,
      autostep ? 1 : 0,
      autostepMaxHeight,
      autostepMinWidth,
      autostepIncludeDynamicBodies ? 1 : 0,
      _characterBuffer,
    );
    final m = _characterBuffer.ref;
    return (
      translation: Vector3(m.tx, m.ty, m.tz),
      grounded: m.grounded != 0,
      slidingDownSlope: m.sliding != 0,
    );
  }
}
