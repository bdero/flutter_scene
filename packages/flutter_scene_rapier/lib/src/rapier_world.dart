import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/ffi/bindings.dart' as native;
import 'package:flutter_scene_rapier/src/rapier_collider.dart';
import 'package:vector_math/vector_math.dart';

/// [PhysicsWorld] backed by Rapier 3D.
///
/// The native simulation state lives behind a [Pointer]; this class
/// allocates it on construction and releases it via a [Finalizer] when
/// the Dart wrapper is collected. [step] forwards directly into
/// Rapier's PhysicsPipeline; [interpolateTransforms] lerps and slerps
/// dynamic-body poses between substeps and writes them back to each
/// owning [Node.localTransform]. Scene queries ([raycast],
/// [raycastAll], [overlapSphere], [overlapBox], [shapeCast]) run
/// through Rapier's QueryPipeline. Contact and trigger lifecycle
/// events are emitted on [collisions] after each step, with
/// [CollisionBegan] carrying the solved contact-manifold points.
///
/// Scene queries run against the broad-phase acceleration structure
/// Rapier rebuilds during [step], so they see colliders as of the most
/// recent step. Apps that step every frame before querying never
/// notice; a query issued before the first step (or against a collider
/// added since the last step) will not see that collider.
///
/// TODO(shape-cast-shapes): [shapeCast] only accepts a [SphereShape]
/// probe; widen the native surface to box / capsule / cylinder probes.
class RapierWorld extends PhysicsWorld {
  RapierWorld({Vector3? gravity}) : _handle = native.worldNew() {
    _finalizer.attach(this, _handle, detach: this);
    final g = gravity ?? this.gravity;
    if (gravity != null) this.gravity = g;
    native.worldSetGravity(_handle, g.x, g.y, g.z);
  }

  static final Finalizer<Pointer<native.NativeWorld>> _finalizer =
      Finalizer<Pointer<native.NativeWorld>>(native.worldDestroy);

  final Pointer<native.NativeWorld> _handle;

  // Reusable 4-float scratch buffer for translation (uses 3) and
  // rotation (uses 4) reads from the native side. Allocated once,
  // freed in onUnmount.
  late final Pointer<Float> _readBuffer = calloc<Float>(4);

  // Reusable single-hit scratch for raycast / shapeCast results, and
  // for reading multi-hit results out of the native query buffer one
  // entry at a time. Allocated once, freed in onUnmount.
  late final Pointer<native.FsrHit> _hitBuffer = calloc<native.FsrHit>();

  // Reusable scratch for reading collision events out of the native
  // per-step buffer one at a time. Allocated once, freed in onUnmount.
  late final Pointer<native.FsrCollisionEvent> _eventBuffer =
      calloc<native.FsrCollisionEvent>();

  // Reusable scratch for reading a collision event's contact points out
  // of the native per-step buffer one at a time. Allocated once, freed
  // in onUnmount.
  late final Pointer<native.FsrContactPoint> _contactBuffer =
      calloc<native.FsrContactPoint>();

  /// The underlying native world pointer. Exposed so [RapierRigidBody]
  /// and [RapierCollider] can pass it back into the FFI for body and
  /// collider operations.
  Pointer<native.NativeWorld> get nativeHandle => _handle;

  // Tracks the Dart node + body type for each registered native body
  // handle, so [interpolateTransforms] can write back dynamic poses
  // and so collider creation can find its sibling body.
  final Map<int, _BodyRecord> _bodies = {};

  // Reverse map from a Rapier collider handle to the owning Dart
  // [RapierCollider]. Populated when a collider is cooked and removed
  // when it's destroyed. Used by the scene-query routines to resolve
  // native hits back to the right component.
  final Map<int, RapierCollider> _collidersByHandle = {};

  /// Records ownership of [handle] by [collider] so scene queries can
  /// resolve hits back to the owning component. Called from
  /// [RapierCollider.onMount] after each successful cook; the matching
  /// [forgetCollider] runs on unmount or rebuild.
  void rememberCollider(int handle, RapierCollider collider) {
    _collidersByHandle[handle] = collider;
  }

  void forgetCollider(int handle) {
    _collidersByHandle.remove(handle);
  }

  /// Looks up the Dart wrapper for a Rapier collider handle. Returns
  /// null when the handle is stale (the collider was just removed) or
  /// belongs to a body / collider this world did not register.
  RapierCollider? colliderFromHandle(int handle) => _collidersByHandle[handle];

  /// Inserts a rigid body into the native world and returns its packed
  /// handle. Called from [RapierRigidBody.onMount].
  int createBody({
    required Node node,
    required BodyType type,
    required Vector3 position,
    required Quaternion rotation,
    required double additionalMass,
  }) {
    final handle = native.bodyCreate(
      _handle,
      _bodyKindByte(type),
      position.x,
      position.y,
      position.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
      additionalMass,
    );
    _bodies[handle] = _BodyRecord(
      node,
      type,
      position.clone(),
      rotation.clone(),
    );
    return handle;
  }

  /// Removes a rigid body previously inserted by [createBody].
  void destroyBody(int handle) {
    _bodies.remove(handle);
    native.bodyDestroy(_handle, handle);
  }

  /// Cooks a sphere collider, attaches it to the rigid body identified
  /// by [bodyHandle], and returns the collider's packed handle.
  int createSphereCollider({
    required int bodyHandle,
    required double radius,
    required PhysicsMaterial material,
    required bool isTrigger,
    required Matrix4 localPose,
  }) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
    return native.colliderSphere(
      _handle,
      bodyHandle,
      radius,
      material.friction,
      material.restitution,
      material.density,
      isTrigger ? 1 : 0,
      t.x,
      t.y,
      t.z,
      r.x,
      r.y,
      r.z,
      r.w,
    );
  }

  /// Cooks a cuboid collider and attaches it to a rigid body.
  int createBoxCollider({
    required int bodyHandle,
    required Vector3 halfExtents,
    required PhysicsMaterial material,
    required bool isTrigger,
    required Matrix4 localPose,
  }) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
    return native.colliderBox(
      _handle,
      bodyHandle,
      halfExtents.x,
      halfExtents.y,
      halfExtents.z,
      material.friction,
      material.restitution,
      material.density,
      isTrigger ? 1 : 0,
      t.x,
      t.y,
      t.z,
      r.x,
      r.y,
      r.z,
      r.w,
    );
  }

  /// Cooks a Y-axis capsule collider and attaches it to a rigid body.
  int createCapsuleCollider({
    required int bodyHandle,
    required double halfHeight,
    required double radius,
    required PhysicsMaterial material,
    required bool isTrigger,
    required Matrix4 localPose,
  }) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
    return native.colliderCapsule(
      _handle,
      bodyHandle,
      halfHeight,
      radius,
      material.friction,
      material.restitution,
      material.density,
      isTrigger ? 1 : 0,
      t.x,
      t.y,
      t.z,
      r.x,
      r.y,
      r.z,
      r.w,
    );
  }

  /// Cooks a Y-axis cylinder collider and attaches it to a rigid body.
  int createCylinderCollider({
    required int bodyHandle,
    required double halfHeight,
    required double radius,
    required PhysicsMaterial material,
    required bool isTrigger,
    required Matrix4 localPose,
  }) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
    return native.colliderCylinder(
      _handle,
      bodyHandle,
      halfHeight,
      radius,
      material.friction,
      material.restitution,
      material.density,
      isTrigger ? 1 : 0,
      t.x,
      t.y,
      t.z,
      r.x,
      r.y,
      r.z,
      r.w,
    );
  }

  void setColliderMaterial(int handle, PhysicsMaterial material) {
    native.colliderSetMaterial(
      _handle,
      handle,
      material.friction,
      material.restitution,
      material.density,
    );
  }

  void setColliderCollisionGroups(int handle, int memberships, int filter) {
    native.colliderSetCollisionGroups(_handle, handle, memberships, filter);
  }

  void setColliderSensor(int handle, bool isSensor) {
    native.colliderSetSensor(_handle, handle, isSensor ? 1 : 0);
  }

  void setColliderLocalPose(int handle, Matrix4 localPose) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
    native.colliderSetLocalPose(
      _handle,
      handle,
      t.x,
      t.y,
      t.z,
      r.x,
      r.y,
      r.z,
      r.w,
    );
  }

  /// Cooks a convex hull collider from packed `xyz` points. Returns
  /// null when Rapier cannot construct a valid hull (degenerate or
  /// near-coplanar point sets).
  int? createConvexHullCollider({
    required int bodyHandle,
    required Float32List points,
    required PhysicsMaterial material,
    required bool isTrigger,
    required Matrix4 localPose,
  }) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
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
        t.x,
        t.y,
        t.z,
        r.x,
        r.y,
        r.z,
        r.w,
      );
      if (handle == 0xFFFFFFFFFFFFFFFF) return null;
      return handle;
    } finally {
      calloc.free(ptr);
    }
  }

  /// Cooks a triangle mesh collider. Returns null when Rapier rejects
  /// the mesh (degenerate triangles, out-of-range indices, etc.).
  int? createTriMeshCollider({
    required int bodyHandle,
    required Float32List vertices,
    required Uint32List indices,
    required PhysicsMaterial material,
    required bool isTrigger,
    required Matrix4 localPose,
  }) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
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
        t.x,
        t.y,
        t.z,
        r.x,
        r.y,
        r.z,
        r.w,
      );
      if (handle == 0xFFFFFFFFFFFFFFFF) return null;
      return handle;
    } finally {
      calloc.free(vPtr);
      calloc.free(iPtr);
    }
  }

  /// Cooks a heightfield collider. The Dart heights are row-major
  /// (`heights[z * width + x]`); this method transposes into the
  /// column-major layout Rapier wants.
  int createHeightFieldCollider({
    required int bodyHandle,
    required int width,
    required int depth,
    required Float32List heights,
    required Vector3 scale,
    required PhysicsMaterial material,
    required bool isTrigger,
    required Matrix4 localPose,
  }) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
    final ptr = calloc<Float>(heights.length);
    try {
      for (var i = 0; i < heights.length; i++) {
        ptr[i] = heights[i];
      }
      return native.colliderHeightField(
        _handle,
        bodyHandle,
        depth, // nrows = Z dimension
        width, // ncols = X dimension
        ptr,
        scale.x,
        scale.y,
        scale.z,
        material.friction,
        material.restitution,
        material.density,
        isTrigger ? 1 : 0,
        t.x,
        t.y,
        t.z,
        r.x,
        r.y,
        r.z,
        r.w,
      );
    } finally {
      calloc.free(ptr);
    }
  }

  /// Removes a collider previously inserted by one of the
  /// `create*Collider` methods.
  void destroyCollider(int handle) {
    native.colliderDestroy(_handle, handle);
  }

  /// Welds [bodyA] and [bodyB] together at the given local anchors and
  /// returns the joint handle. Called from [RapierFixedJoint].
  int createFixedJoint({
    required int bodyA,
    required int bodyB,
    required Vector3 anchorA,
    required Vector3 anchorB,
    required bool collisionsEnabled,
  }) {
    return native.jointFixed(
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
  }

  /// Inserts a ball-and-socket joint between [bodyA] and [bodyB].
  int createSphericalJoint({
    required int bodyA,
    required int bodyB,
    required Vector3 anchorA,
    required Vector3 anchorB,
    required bool collisionsEnabled,
  }) {
    return native.jointSpherical(
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
  }

  /// Inserts a hinge joint about [axis] between [bodyA] and [bodyB].
  /// Null limit or motor values disable that feature.
  int createRevoluteJoint({
    required int bodyA,
    required int bodyB,
    required Vector3 axis,
    required Vector3 anchorA,
    required Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    required bool collisionsEnabled,
  }) {
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

  /// Inserts a slider joint along [axis] between [bodyA] and [bodyB].
  /// Null limit or motor values disable that feature.
  int createPrismaticJoint({
    required int bodyA,
    required int bodyB,
    required Vector3 axis,
    required Vector3 anchorA,
    required Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    required bool collisionsEnabled,
  }) {
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

  /// Removes a joint previously inserted by a `create*Joint` method.
  void destroyJoint(int handle) => native.jointDestroy(_handle, handle);

  /// Reads the body's current world translation. Returns a fresh
  /// [Vector3]; the underlying scratch buffer is reused on each call,
  /// so do not hold a reference to it.
  Vector3 readBodyTranslation(int handle) {
    native.bodyTranslation(_handle, handle, _readBuffer);
    return Vector3(_readBuffer[0], _readBuffer[1], _readBuffer[2]);
  }

  /// Reads the body's current world rotation as a unit quaternion.
  Quaternion readBodyRotation(int handle) {
    native.bodyRotation(_handle, handle, _readBuffer);
    return Quaternion(
      _readBuffer[0],
      _readBuffer[1],
      _readBuffer[2],
      _readBuffer[3],
    );
  }

  /// Reads the body's current linear velocity (world space).
  Vector3 readBodyLinearVelocity(int handle) {
    native.bodyLinearVelocity(_handle, handle, _readBuffer);
    return Vector3(_readBuffer[0], _readBuffer[1], _readBuffer[2]);
  }

  /// Reads the body's current angular velocity (rad/sec, world axes).
  Vector3 readBodyAngularVelocity(int handle) {
    native.bodyAngularVelocity(_handle, handle, _readBuffer);
    return Vector3(_readBuffer[0], _readBuffer[1], _readBuffer[2]);
  }

  void setBodyLinearVelocity(int handle, Vector3 v, {bool wakeUp = true}) {
    native.bodySetLinearVelocity(
      _handle,
      handle,
      v.x,
      v.y,
      v.z,
      wakeUp ? 1 : 0,
    );
  }

  void setBodyAngularVelocity(int handle, Vector3 w, {bool wakeUp = true}) {
    native.bodySetAngularVelocity(
      _handle,
      handle,
      w.x,
      w.y,
      w.z,
      wakeUp ? 1 : 0,
    );
  }

  void setBodyLinearDamping(int handle, double damping) {
    native.bodySetLinearDamping(_handle, handle, damping);
  }

  void setBodyAngularDamping(int handle, double damping) {
    native.bodySetAngularDamping(_handle, handle, damping);
  }

  void setBodyAdditionalMass(int handle, double additionalMass) {
    native.bodySetAdditionalMass(_handle, handle, additionalMass);
  }

  /// Pushes the next-step pose for a kinematic body. Rapier integrates
  /// from the current pose to this target during the next step.
  void setBodyNextKinematicPose(
    int handle,
    Vector3 translation,
    Quaternion rotation,
  ) {
    native.bodySetNextKinematicPose(
      _handle,
      handle,
      translation.x,
      translation.y,
      translation.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
    );
  }

  /// Packs [linear] and [angular] into a 6-bit lock field (translation
  /// XYZ in low bits, rotation XYZ in high bits, value 0 = locked) and
  /// pushes it to native.
  void setBodyLockedAxes(int handle, Vector3 linear, Vector3 angular) {
    var bits = 0;
    if (linear.x == 0) bits |= 1;
    if (linear.y == 0) bits |= 2;
    if (linear.z == 0) bits |= 4;
    if (angular.x == 0) bits |= 8;
    if (angular.y == 0) bits |= 16;
    if (angular.z == 0) bits |= 32;
    native.bodySetLockedAxes(_handle, handle, bits);
  }

  void setBodyGravityScale(int handle, double scale) {
    native.bodySetGravityScale(_handle, handle, scale);
  }

  void setBodyCcdEnabled(int handle, bool enabled) {
    native.bodySetCcdEnabled(_handle, handle, enabled ? 1 : 0);
  }

  void wakeBody(int handle) => native.bodyWakeUp(_handle, handle);

  void sleepBody(int handle) => native.bodySleep(_handle, handle);

  bool isBodySleeping(int handle) =>
      native.bodyIsSleeping(_handle, handle) != 0;

  /// Continuous force applied to a body for one step.
  void applyBodyForce(int handle, Vector3 force, {Vector3? atWorldPoint}) {
    final p = atWorldPoint;
    native.bodyApplyForce(
      _handle,
      handle,
      force.x,
      force.y,
      force.z,
      p != null ? 1 : 0,
      p?.x ?? 0,
      p?.y ?? 0,
      p?.z ?? 0,
    );
  }

  /// Instantaneous impulse applied to a body.
  void applyBodyImpulse(int handle, Vector3 impulse, {Vector3? atWorldPoint}) {
    final p = atWorldPoint;
    native.bodyApplyImpulse(
      _handle,
      handle,
      impulse.x,
      impulse.y,
      impulse.z,
      p != null ? 1 : 0,
      p?.x ?? 0,
      p?.y ?? 0,
      p?.z ?? 0,
    );
  }

  void applyBodyTorque(int handle, Vector3 torque) {
    native.bodyApplyTorque(_handle, handle, torque.x, torque.y, torque.z);
  }

  void applyBodyAngularImpulse(int handle, Vector3 impulse) {
    native.bodyApplyAngularImpulse(
      _handle,
      handle,
      impulse.x,
      impulse.y,
      impulse.z,
    );
  }

  static int _bodyKindByte(BodyType type) {
    switch (type) {
      case BodyType.fixed:
        return native.bodyKindFixed;
      case BodyType.kinematic:
        return native.bodyKindKinematic;
      case BodyType.dynamic_:
        return native.bodyKindDynamic;
    }
  }

  @override
  String get backendName => 'rapier3d';

  final StreamController<CollisionEvent> _events =
      StreamController<CollisionEvent>.broadcast();

  @override
  Stream<CollisionEvent> get collisions => _events.stream;

  @override
  void onUnmount() {
    _events.close();
    _finalizer.detach(this);
    native.worldDestroy(_handle);
    calloc.free(_readBuffer);
    calloc.free(_hitBuffer);
    calloc.free(_eventBuffer);
    calloc.free(_contactBuffer);
  }

  // Drains the collision events Rapier generated during the last step
  // and emits them on the [collisions] stream, resolving each collider
  // handle back to its Dart wrapper. A pair involving a sensor maps to
  // the trigger events; a solid pair maps to the collision events, whose
  // [CollisionBegan] carries the solved contact-manifold points.
  void _drainCollisionEvents() {
    if (!_events.hasListener) return;
    final count = native.worldCollisionEventCount(_handle);
    for (var i = 0; i < count; i++) {
      if (native.worldCollisionEventAt(_handle, i, _eventBuffer) == 0) {
        continue;
      }
      final raw = _eventBuffer.ref;
      final a = _collidersByHandle[raw.colliderA];
      final b = _collidersByHandle[raw.colliderB];
      if (a == null || b == null) continue;
      final started = raw.started != 0;
      final isTrigger = raw.sensor != 0;
      final CollisionEvent event;
      if (isTrigger) {
        event = started
            ? TriggerEntered(
                nodeA: a.node,
                nodeB: b.node,
                colliderA: a,
                colliderB: b,
              )
            : TriggerExited(
                nodeA: a.node,
                nodeB: b.node,
                colliderA: a,
                colliderB: b,
              );
      } else {
        event = started
            ? CollisionBegan(
                nodeA: a.node,
                nodeB: b.node,
                colliderA: a,
                colliderB: b,
                contacts: _readContacts(raw.contactStart, raw.contactCount),
              )
            : CollisionEnded(
                nodeA: a.node,
                nodeB: b.node,
                colliderA: a,
                colliderB: b,
              );
      }
      _events.add(event);
    }
  }

  // Reads [count] contact points starting at absolute index [start] from
  // the most recent step's native contact buffer.
  List<ContactPoint> _readContacts(int start, int count) {
    if (count == 0) return const [];
    final contacts = <ContactPoint>[];
    for (var i = 0; i < count; i++) {
      if (native.worldContactPointAt(_handle, start + i, _contactBuffer) == 0) {
        continue;
      }
      final c = _contactBuffer.ref;
      contacts.add(
        ContactPoint(
          worldPosition: Vector3(c.px, c.py, c.pz),
          worldNormal: Vector3(c.nx, c.ny, c.nz),
          impulse: c.impulse,
          separation: c.separation,
        ),
      );
    }
    return contacts;
  }

  @override
  void step(double fixedDt) {
    final g = gravity;
    native.worldSetGravity(_handle, g.x, g.y, g.z);
    native.worldStep(_handle, fixedDt);
    // Capture this step's pose for dynamic bodies so
    // interpolateTransforms can lerp/slerp between substeps.
    for (final entry in _bodies.entries) {
      final r = entry.value;
      if (r.type != BodyType.dynamic_) continue;
      r.prevTranslation.setFrom(r.currTranslation);
      r.prevRotation.setFrom(r.currRotation);
      final t = readBodyTranslation(entry.key);
      final rot = readBodyRotation(entry.key);
      r.currTranslation.setFrom(t);
      r.currRotation.setFrom(rot);
    }
    _drainCollisionEvents();
  }

  @override
  void interpolateTransforms(double alpha) {
    // Blend each dynamic body's pose by alpha between the previous and
    // current step (alpha == 0 snaps to previous, alpha == 1 snaps to
    // current). Fixed and kinematic bodies are not touched; the user
    // owns those node transforms.
    final t = Vector3.zero();
    for (final entry in _bodies.entries) {
      final record = entry.value;
      if (record.type != BodyType.dynamic_) continue;
      t
        ..setFrom(record.currTranslation)
        ..sub(record.prevTranslation)
        ..scale(alpha)
        ..add(record.prevTranslation);
      final rot = _slerp(record.prevRotation, record.currRotation, alpha);
      final worldPose = Matrix4.compose(t, rot, Vector3(1, 1, 1));
      final parent = record.node.parent;
      if (parent == null) {
        record.node.localTransform = worldPose;
      } else {
        final parentInverse = Matrix4.inverted(parent.globalTransform);
        record.node.localTransform = parentInverse.multiplied(worldPose);
      }
      record.node.markTransformDirty();
    }
  }

  // Packs the include* flags into the bitmask the native query filter
  // expects.
  int _filterFlags({
    required bool includeFixed,
    required bool includeKinematic,
    required bool includeDynamic,
    required bool includeTriggers,
  }) {
    var flags = 0;
    if (includeFixed) flags |= native.queryIncludeFixed;
    if (includeKinematic) flags |= native.queryIncludeKinematic;
    if (includeDynamic) flags |= native.queryIncludeDynamic;
    if (includeTriggers) flags |= native.queryIncludeSensors;
    return flags;
  }

  // Builds a RaycastHit from the native scratch hit, resolving the
  // collider handle back to its Dart wrapper. Returns null when the
  // handle no longer maps to a live collider.
  RaycastHit? _raycastHitFromBuffer() {
    final hit = _hitBuffer.ref;
    final collider = _collidersByHandle[hit.collider];
    if (collider == null) return null;
    return RaycastHit(
      node: collider.node,
      collider: collider,
      worldPoint: Vector3(hit.px, hit.py, hit.pz),
      worldNormal: Vector3(hit.nx, hit.ny, hit.nz),
      distance: hit.distance,
    );
  }

  // Reads [count] entries out of the native query buffer, mapping each
  // to a result of type [T]. Entries whose collider handle no longer
  // resolves to a live Dart collider are skipped.
  List<T> _drainHits<T>(
    int count,
    T Function(RapierCollider collider, native.FsrHit hit) build,
  ) {
    final results = <T>[];
    for (var i = 0; i < count; i++) {
      if (native.worldQueryResultAt(_handle, i, _hitBuffer) == 0) continue;
      final hit = _hitBuffer.ref;
      final collider = _collidersByHandle[hit.collider];
      if (collider == null) continue;
      results.add(build(collider, hit));
    }
    return results;
  }

  @override
  RaycastHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    final dir = ray.direction.normalized();
    final hit = native.worldRaycast(
      _handle,
      ray.origin.x,
      ray.origin.y,
      ray.origin.z,
      dir.x,
      dir.y,
      dir.z,
      maxDistance.isFinite ? maxDistance : double.maxFinite,
      1,
      _filterFlags(
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeDynamic: includeDynamic,
        includeTriggers: includeTriggers,
      ),
      _hitBuffer,
    );
    if (hit == 0) return null;
    return _raycastHitFromBuffer();
  }

  @override
  List<RaycastHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    final dir = ray.direction.normalized();
    final count = native.worldRaycastAll(
      _handle,
      ray.origin.x,
      ray.origin.y,
      ray.origin.z,
      dir.x,
      dir.y,
      dir.z,
      maxDistance.isFinite ? maxDistance : double.maxFinite,
      1,
      _filterFlags(
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeDynamic: includeDynamic,
        includeTriggers: includeTriggers,
      ),
    );
    return _drainHits(count, (collider, hit) {
      return RaycastHit(
        node: collider.node,
        collider: collider,
        worldPoint: Vector3(hit.px, hit.py, hit.pz),
        worldNormal: Vector3(hit.nx, hit.ny, hit.nz),
        distance: hit.distance,
      );
    });
  }

  @override
  List<OverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    final count = native.worldOverlapSphere(
      _handle,
      center.x,
      center.y,
      center.z,
      radius,
      _filterFlags(
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeDynamic: includeDynamic,
        includeTriggers: includeTriggers,
      ),
    );
    return _drainHits(
      count,
      (collider, _) => OverlapHit(node: collider.node, collider: collider),
    );
  }

  @override
  List<OverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    final count = native.worldOverlapBox(
      _handle,
      center.x,
      center.y,
      center.z,
      halfExtents.x,
      halfExtents.y,
      halfExtents.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
      _filterFlags(
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeDynamic: includeDynamic,
        includeTriggers: includeTriggers,
      ),
    );
    return _drainHits(
      count,
      (collider, _) => OverlapHit(node: collider.node, collider: collider),
    );
  }

  @override
  ShapeCastHit? shapeCast(
    Shape shape,
    Matrix4 from,
    Vector3 direction,
    double distance, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    // TODO(shape-cast-shapes): only SphereShape is cooked for the cast
    // probe today. Add box / capsule / cylinder probes by widening the
    // native fsr_world_shape_cast_* surface.
    if (shape is! SphereShape) {
      throw UnsupportedError(
        'RapierWorld.shapeCast currently supports SphereShape probes only.',
      );
    }
    final origin = from.getTranslation();
    final dir = direction.normalized();
    final hit = native.worldShapeCastSphere(
      _handle,
      origin.x,
      origin.y,
      origin.z,
      shape.radius,
      dir.x,
      dir.y,
      dir.z,
      distance,
      _filterFlags(
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeDynamic: includeDynamic,
        includeTriggers: includeTriggers,
      ),
      _hitBuffer,
    );
    if (hit == 0) return null;
    final h = _hitBuffer.ref;
    final collider = _collidersByHandle[h.collider];
    if (collider == null) return null;
    return ShapeCastHit(
      node: collider.node,
      collider: collider,
      worldPoint: Vector3(h.px, h.py, h.pz),
      worldNormal: Vector3(h.nx, h.ny, h.nz),
      distance: h.distance,
    );
  }
}

/// Walks [start] and its ancestors looking for a [RapierWorld] on a
/// node component. Used by bodies and colliders to find the simulation
/// they belong to.
RapierWorld? findAncestorRapierWorld(Node start) {
  Node? current = start;
  while (current != null) {
    final world = current.getComponent<RapierWorld>();
    if (world != null) return world;
    current = current.parent;
  }
  return null;
}

class _BodyRecord {
  _BodyRecord(
    this.node,
    this.type,
    Vector3 initialTranslation,
    Quaternion initialRotation,
  ) : prevTranslation = initialTranslation.clone(),
      currTranslation = initialTranslation,
      prevRotation = initialRotation.clone(),
      currRotation = initialRotation;

  final Node node;
  final BodyType type;
  // Pose after the previous physics step (or the initial pose, on the
  // first step). Used by [RapierWorld.interpolateTransforms] to blend
  // between substeps for smooth rendering.
  final Vector3 prevTranslation;
  final Quaternion prevRotation;
  // Pose after the most recent physics step.
  final Vector3 currTranslation;
  final Quaternion currRotation;
}

/// Shortest-arc quaternion slerp between [a] and [b] by [t]. Falls
/// back to normalized-lerp when the rotations are nearly identical.
/// Inputs are not modified.
Quaternion _slerp(Quaternion a, Quaternion b, double t) {
  var bx = b.x;
  var by = b.y;
  var bz = b.z;
  var bw = b.w;
  var dot = a.x * bx + a.y * by + a.z * bz + a.w * bw;
  if (dot < 0) {
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
    dot = -dot;
  }
  if (dot > 0.9995) {
    final r = Quaternion(
      a.x + t * (bx - a.x),
      a.y + t * (by - a.y),
      a.z + t * (bz - a.z),
      a.w + t * (bw - a.w),
    );
    r.normalize();
    return r;
  }
  final theta0 = math.acos(dot.clamp(-1.0, 1.0));
  final theta = theta0 * t;
  final sinTheta = math.sin(theta);
  final sinTheta0 = math.sin(theta0);
  final s0 = math.cos(theta) - dot * sinTheta / sinTheta0;
  final s1 = sinTheta / sinTheta0;
  return Quaternion(
    a.x * s0 + bx * s1,
    a.y * s0 + by * s1,
    a.z * s0 + bz * s1,
    a.w * s0 + bw * s1,
  );
}
