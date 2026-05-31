import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/ffi/bindings.dart' as native;
import 'package:vector_math/vector_math.dart';

/// [PhysicsWorld] backed by Rapier 3D.
///
/// The native simulation state lives behind a [Pointer]; this class
/// allocates it on construction and releases it via a [Finalizer] when
/// the Dart wrapper is collected. [step] forwards directly into
/// Rapier's PhysicsPipeline. Body, collider, query, and event support
/// land in subsequent commits.
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

  /// The underlying native world pointer. Exposed for follow-on commits
  /// that wire body and collider lifecycle through their own FFI calls.
  Pointer<native.NativeWorld> get nativeHandle => _handle;

  // Tracks the Dart node + body type for each registered native body
  // handle, so [interpolateTransforms] can write back dynamic poses
  // and so collider creation can find its sibling body.
  final Map<int, _BodyRecord> _bodies = {};

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
    _bodies[handle] = _BodyRecord(node, type);
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

  /// Removes a collider previously inserted by one of the
  /// `create*Collider` methods.
  void destroyCollider(int handle) {
    native.colliderDestroy(_handle, handle);
  }

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
  }

  @override
  void step(double fixedDt) {
    final g = gravity;
    native.worldSetGravity(_handle, g.x, g.y, g.z);
    native.worldStep(_handle, fixedDt);
  }

  @override
  void interpolateTransforms(double alpha) {
    // Snap each dynamic body's owning node to the body's current world
    // pose. Proper alpha-based interpolation between previous and
    // current step (slerp on rotation) is a follow-on refinement;
    // snapping is sufficient for visible motion and the unit tests in
    // this commit. Fixed and kinematic bodies are not touched: the
    // user owns their node transforms.
    for (final entry in _bodies.entries) {
      final record = entry.value;
      if (record.type != BodyType.dynamic_) continue;
      final translation = readBodyTranslation(entry.key);
      final rotation = readBodyRotation(entry.key);
      final worldPose = Matrix4.compose(
        translation,
        rotation,
        Vector3(1, 1, 1),
      );
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
    throw UnimplementedError('RapierWorld.raycast lands in Stage 5.');
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
    throw UnimplementedError('RapierWorld.raycastAll lands in Stage 5.');
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
    throw UnimplementedError('RapierWorld.overlapSphere lands in Stage 5.');
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
    throw UnimplementedError('RapierWorld.overlapBox lands in Stage 5.');
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
    throw UnimplementedError('RapierWorld.shapeCast lands in Stage 5.');
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
  _BodyRecord(this.node, this.type);
  final Node node;
  final BodyType type;
}
