import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings_factory.dart';
import 'package:flutter_scene_rapier/src/rapier_collider.dart';
import 'package:vector_math/vector_math.dart';

/// [PhysicsWorld] backed by Rapier 3D.
///
/// The simulation state lives in a [RapierBindings] backend, which owns
/// the world and releases it on [onUnmount]. [step] forwards directly
/// into Rapier's PhysicsPipeline; [interpolateTransforms] lerps and
/// slerps dynamic-body poses between substeps and writes them back to
/// each owning [Node.localTransform]. Scene queries ([raycast],
/// [raycastAll], [overlapSphere], [overlapBox], [shapeCast]) run through
/// Rapier's QueryPipeline. Contact and trigger lifecycle events are
/// emitted on [collisions] after each step, with [CollisionBegan]
/// carrying the solved contact-manifold points.
///
/// Scene queries run against the broad-phase acceleration structure
/// Rapier rebuilds during [step], so they see colliders as of the most
/// recent step. Apps that step every frame before querying never
/// notice; a query issued before the first step (or against a collider
/// added since the last step) will not see that collider.
///
/// TODO(shape-cast-hulls): [shapeCast] accepts sphere / box / capsule /
/// cylinder probes; convex-hull, trimesh, heightfield, and compound
/// probes are not wired through the backend surface yet.
class RapierWorld extends PhysicsWorld {
  RapierWorld({Vector3? gravity}) : _bindings = createRapierBindings() {
    final g = gravity ?? this.gravity;
    if (gravity != null) this.gravity = g;
    _bindings.setGravity(g.x, g.y, g.z);
  }

  /// Prepares the Rapier backend so a [RapierWorld] can be constructed.
  ///
  /// On native targets this returns immediately. On the web it loads and
  /// instantiates the shim's WebAssembly module, which is asynchronous,
  /// so await it once during startup before creating any [RapierWorld]
  /// (alongside the rest of your scene initialization). Calling it again
  /// is cheap.
  static Future<void> ensureInitialized() => ensureRapierReady();

  final RapierBindings _bindings;

  // Tracks the Dart node + body type for each registered body handle, so
  // [interpolateTransforms] can write back dynamic poses and so collider
  // creation can find its sibling body.
  final Map<int, _BodyRecord> _bodies = {};

  // Reverse map from a Rapier collider handle to the owning Dart
  // [RapierCollider]. Populated when a collider is cooked and removed
  // when it's destroyed. Used by the scene-query routines to resolve
  // hits back to the right component.
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

  double _interpolationAlpha = 0.0;

  /// The residual fraction in `[0, 1]` of the last [interpolateTransforms]
  /// call: how far the renderer is between the previous and current fixed
  /// steps. Kinematic bodies the engine does not interpolate (for example
  /// a character driven by [RapierKinematicCharacterController]) can read
  /// this to smooth their own rendering between steps.
  double get interpolationAlpha => _interpolationAlpha;

  /// Inserts a rigid body into the world and returns its packed handle.
  /// Called from [RapierRigidBody.onMount].
  int createBody({
    required Node node,
    required BodyType type,
    required Vector3 position,
    required Quaternion rotation,
    required double additionalMass,
  }) {
    final handle = _bindings.createBody(
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
    _bindings.destroyBody(handle);
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
    return _bindings.colliderSphere(
      bodyHandle,
      radius,
      material,
      isTrigger,
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
    return _bindings.colliderBox(
      bodyHandle,
      halfExtents.x,
      halfExtents.y,
      halfExtents.z,
      material,
      isTrigger,
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
    return _bindings.colliderCapsule(
      bodyHandle,
      halfHeight,
      radius,
      material,
      isTrigger,
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
    return _bindings.colliderCylinder(
      bodyHandle,
      halfHeight,
      radius,
      material,
      isTrigger,
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
    _bindings.setColliderMaterial(handle, material);
  }

  void setColliderCollisionGroups(int handle, int memberships, int filter) {
    _bindings.setColliderCollisionGroups(handle, memberships, filter);
  }

  void setColliderSensor(int handle, bool isSensor) {
    _bindings.setColliderSensor(handle, isSensor);
  }

  void setColliderLocalPose(int handle, Matrix4 localPose) {
    final t = localPose.getTranslation();
    final r = Quaternion.fromRotation(localPose.getRotation());
    _bindings.setColliderLocalPose(handle, t.x, t.y, t.z, r.x, r.y, r.z, r.w);
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
    return _bindings.colliderConvexHull(
      bodyHandle,
      points,
      material,
      isTrigger,
      t.x,
      t.y,
      t.z,
      r.x,
      r.y,
      r.z,
      r.w,
    );
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
    return _bindings.colliderTriMesh(
      bodyHandle,
      vertices,
      indices,
      material,
      isTrigger,
      t.x,
      t.y,
      t.z,
      r.x,
      r.y,
      r.z,
      r.w,
    );
  }

  /// Cooks a heightfield collider. The Dart heights are row-major
  /// (`heights[z * width + x]`); the backend transposes into the
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
    return _bindings.colliderHeightField(
      bodyHandle,
      depth, // nrows = Z dimension
      width, // ncols = X dimension
      heights,
      scale.x,
      scale.y,
      scale.z,
      material,
      isTrigger,
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
    _bindings.destroyCollider(handle);
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
    return _bindings.jointFixed(
      bodyA,
      bodyB,
      anchorA,
      anchorB,
      collisionsEnabled,
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
    return _bindings.jointSpherical(
      bodyA,
      bodyB,
      anchorA,
      anchorB,
      collisionsEnabled,
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
    return _bindings.jointRevolute(
      bodyA,
      bodyB,
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
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
    return _bindings.jointPrismatic(
      bodyA,
      bodyB,
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
    );
  }

  /// Removes a joint previously inserted by a `create*Joint` method.
  void destroyJoint(int handle) => _bindings.destroyJoint(handle);

  /// Reconfigures an existing fixed joint in place.
  void updateFixedJoint(
    int joint, {
    required Vector3 anchorA,
    required Vector3 anchorB,
    required bool collisionsEnabled,
  }) {
    _bindings.jointUpdateFixed(joint, anchorA, anchorB, collisionsEnabled);
  }

  /// Reconfigures an existing spherical joint in place.
  void updateSphericalJoint(
    int joint, {
    required Vector3 anchorA,
    required Vector3 anchorB,
    required bool collisionsEnabled,
  }) {
    _bindings.jointUpdateSpherical(joint, anchorA, anchorB, collisionsEnabled);
  }

  /// Reconfigures an existing revolute joint in place.
  void updateRevoluteJoint(
    int joint, {
    required Vector3 axis,
    required Vector3 anchorA,
    required Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    required bool collisionsEnabled,
  }) {
    _bindings.jointUpdateRevolute(
      joint,
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
    );
  }

  /// Reconfigures an existing prismatic joint in place.
  void updatePrismaticJoint(
    int joint, {
    required Vector3 axis,
    required Vector3 anchorA,
    required Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    required bool collisionsEnabled,
  }) {
    _bindings.jointUpdatePrismatic(
      joint,
      axis,
      anchorA,
      anchorB,
      lowerLimit,
      upperLimit,
      motorTargetVelocity,
      motorMaxForce,
      collisionsEnabled,
    );
  }

  /// Inserts a generic (6DOF) joint between [bodyA] and [bodyB]. [axes]
  /// is the six per-axis configs in `JointAxis` order. Returns the joint
  /// handle.
  int createGenericJoint(
    int bodyA,
    int bodyB, {
    required Vector3 anchorA,
    required Quaternion basisA,
    required Vector3 anchorB,
    required Quaternion basisB,
    required List<JointAxisConfig> axes,
    required bool collisionsEnabled,
  }) {
    return _bindings.jointGeneric(
      bodyA,
      bodyB,
      anchorA,
      basisA,
      anchorB,
      basisB,
      axes,
      collisionsEnabled,
    );
  }

  /// Reconfigures an existing generic joint in place.
  void updateGenericJoint(
    int joint, {
    required Vector3 anchorA,
    required Quaternion basisA,
    required Vector3 anchorB,
    required Quaternion basisB,
    required List<JointAxisConfig> axes,
    required bool collisionsEnabled,
  }) {
    _bindings.jointUpdateGeneric(
      joint,
      anchorA,
      basisA,
      anchorB,
      basisB,
      axes,
      collisionsEnabled,
    );
  }

  /// Runs one kinematic-character move for the character whose shape is
  /// the collider [collider]. Returns the corrected world-space
  /// translation to apply plus the grounded / sliding flags. Pass a null
  /// [snapToGround] to disable snapping and `autostep: false` to disable
  /// stepping.
  CharacterMovement moveCharacter(
    int collider, {
    required Vector3 position,
    required Vector3 desiredTranslation,
    required double deltaSeconds,
    required Vector3 up,
    required double offset,
    required bool slide,
    required double maxSlopeClimbAngle,
    required double minSlopeSlideAngle,
    required double? snapToGround,
    required bool autostep,
    required double autostepMaxHeight,
    required double autostepMinWidth,
    required bool autostepIncludeDynamicBodies,
    required double characterMass,
  }) {
    return _bindings.moveCharacter(
      collider,
      position.x,
      position.y,
      position.z,
      desiredTranslation.x,
      desiredTranslation.y,
      desiredTranslation.z,
      deltaSeconds,
      up.x,
      up.y,
      up.z,
      offset,
      slide,
      maxSlopeClimbAngle,
      minSlopeSlideAngle,
      snapToGround ?? -1.0,
      autostep,
      autostepMaxHeight,
      autostepMinWidth,
      autostepIncludeDynamicBodies,
      characterMass,
    );
  }

  /// Creates a fixed body at the world origin to stand in as the static
  /// side of a world-anchored joint, returning its handle. It is not
  /// registered for transform interpolation; the joint that owns it
  /// releases it with [destroyJointAnchorBody].
  int createJointAnchorBody() {
    return _bindings.createBody(
      bodyKindFixed,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
    );
  }

  /// Releases a body created by [createJointAnchorBody].
  void destroyJointAnchorBody(int handle) => _bindings.destroyBody(handle);

  /// Reads the body's current world translation.
  Vector3 readBodyTranslation(int handle) => _bindings.bodyTranslation(handle);

  /// Reads the body's current world rotation as a unit quaternion.
  Quaternion readBodyRotation(int handle) => _bindings.bodyRotation(handle);

  /// Reads the body's current linear velocity (world space).
  Vector3 readBodyLinearVelocity(int handle) =>
      _bindings.bodyLinearVelocity(handle);

  /// Reads the body's current angular velocity (rad/sec, world axes).
  Vector3 readBodyAngularVelocity(int handle) =>
      _bindings.bodyAngularVelocity(handle);

  void setBodyLinearVelocity(int handle, Vector3 v, {bool wakeUp = true}) {
    _bindings.setBodyLinearVelocity(handle, v.x, v.y, v.z, wakeUp);
  }

  void setBodyAngularVelocity(int handle, Vector3 w, {bool wakeUp = true}) {
    _bindings.setBodyAngularVelocity(handle, w.x, w.y, w.z, wakeUp);
  }

  void setBodyLinearDamping(int handle, double damping) {
    _bindings.setBodyLinearDamping(handle, damping);
  }

  void setBodyAngularDamping(int handle, double damping) {
    _bindings.setBodyAngularDamping(handle, damping);
  }

  void setBodyAdditionalMass(int handle, double additionalMass) {
    _bindings.setBodyAdditionalMass(handle, additionalMass);
  }

  /// Pushes the next-step pose for a kinematic body. Rapier integrates
  /// from the current pose to this target during the next step.
  void setBodyNextKinematicPose(
    int handle,
    Vector3 translation,
    Quaternion rotation,
  ) {
    _bindings.setBodyNextKinematicPose(
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
  /// pushes it to the backend.
  void setBodyLockedAxes(int handle, Vector3 linear, Vector3 angular) {
    var bits = 0;
    if (linear.x == 0) bits |= 1;
    if (linear.y == 0) bits |= 2;
    if (linear.z == 0) bits |= 4;
    if (angular.x == 0) bits |= 8;
    if (angular.y == 0) bits |= 16;
    if (angular.z == 0) bits |= 32;
    _bindings.setBodyLockedAxes(handle, bits);
  }

  void setBodyGravityScale(int handle, double scale) {
    _bindings.setBodyGravityScale(handle, scale);
  }

  void setBodyCcdEnabled(int handle, bool enabled) {
    _bindings.setBodyCcdEnabled(handle, enabled);
  }

  void wakeBody(int handle) => _bindings.wakeBody(handle);

  void sleepBody(int handle) => _bindings.sleepBody(handle);

  bool isBodySleeping(int handle) => _bindings.isBodySleeping(handle);

  /// Continuous force applied to a body for one step.
  void applyBodyForce(int handle, Vector3 force, {Vector3? atWorldPoint}) {
    final p = atWorldPoint;
    _bindings.applyBodyForce(
      handle,
      force.x,
      force.y,
      force.z,
      p != null,
      p?.x ?? 0,
      p?.y ?? 0,
      p?.z ?? 0,
    );
  }

  /// Instantaneous impulse applied to a body.
  void applyBodyImpulse(int handle, Vector3 impulse, {Vector3? atWorldPoint}) {
    final p = atWorldPoint;
    _bindings.applyBodyImpulse(
      handle,
      impulse.x,
      impulse.y,
      impulse.z,
      p != null,
      p?.x ?? 0,
      p?.y ?? 0,
      p?.z ?? 0,
    );
  }

  void applyBodyTorque(int handle, Vector3 torque) {
    _bindings.applyBodyTorque(handle, torque.x, torque.y, torque.z);
  }

  void applyBodyAngularImpulse(int handle, Vector3 impulse) {
    _bindings.applyBodyAngularImpulse(handle, impulse.x, impulse.y, impulse.z);
  }

  static int _bodyKindByte(BodyType type) {
    switch (type) {
      case BodyType.fixed:
        return bodyKindFixed;
      case BodyType.kinematic:
        return bodyKindKinematic;
      case BodyType.dynamic_:
        return bodyKindDynamic;
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
    _bindings.dispose();
  }

  // Drains the collision events Rapier generated during the last step
  // and emits them on the [collisions] stream, resolving each collider
  // handle back to its Dart wrapper. A pair involving a sensor maps to
  // the trigger events; a solid pair maps to the collision events, whose
  // [CollisionBegan] carries the solved contact-manifold points.
  void _drainCollisionEvents() {
    if (!_events.hasListener) return;
    final count = _bindings.collisionEventCount();
    for (var i = 0; i < count; i++) {
      final raw = _bindings.collisionEventAt(i);
      if (raw == null) continue;
      final a = _collidersByHandle[raw.colliderA];
      final b = _collidersByHandle[raw.colliderB];
      if (a == null || b == null) continue;
      final started = raw.started;
      final isTrigger = raw.sensor;
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
  // the most recent step's contact buffer.
  List<ContactPoint> _readContacts(int start, int count) {
    if (count == 0) return const [];
    final contacts = <ContactPoint>[];
    for (var i = 0; i < count; i++) {
      final c = _bindings.contactPointAt(start + i);
      if (c == null) continue;
      contacts.add(
        ContactPoint(
          worldPosition: c.position,
          worldNormal: c.normal,
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
    _bindings.setGravity(g.x, g.y, g.z);
    _bindings.step(fixedDt);
    // Capture this step's pose for dynamic bodies so
    // interpolateTransforms can lerp/slerp between substeps.
    for (final entry in _bodies.entries) {
      final r = entry.value;
      if (r.type != BodyType.dynamic_) continue;
      r.prevTranslation.setFrom(r.currTranslation);
      r.prevRotation.setFrom(r.currRotation);
      r.currTranslation.setFrom(_bindings.bodyTranslation(entry.key));
      r.currRotation.setFrom(_bindings.bodyRotation(entry.key));
    }
    _drainCollisionEvents();
  }

  @override
  void interpolateTransforms(double alpha) {
    _interpolationAlpha = alpha;
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

  // Packs the include* flags into the bitmask the query filter expects.
  int _filterFlags({
    required bool includeFixed,
    required bool includeKinematic,
    required bool includeDynamic,
    required bool includeTriggers,
  }) {
    var flags = 0;
    if (includeFixed) flags |= queryIncludeFixed;
    if (includeKinematic) flags |= queryIncludeKinematic;
    if (includeDynamic) flags |= queryIncludeDynamic;
    if (includeTriggers) flags |= queryIncludeSensors;
    return flags;
  }

  // Resolves a raw hit's collider handle to a RaycastHit, or null when
  // the handle no longer maps to a live collider.
  RaycastHit? _raycastHitFromRaw(RawHit hit) {
    final collider = _collidersByHandle[hit.collider];
    if (collider == null) return null;
    return RaycastHit(
      node: collider.node,
      collider: collider,
      worldPoint: hit.point,
      worldNormal: hit.normal,
      distance: hit.distance,
    );
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
    final hit = _bindings.raycast(
      ray.origin.x,
      ray.origin.y,
      ray.origin.z,
      dir.x,
      dir.y,
      dir.z,
      maxDistance.isFinite ? maxDistance : double.maxFinite,
      _filterFlags(
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeDynamic: includeDynamic,
        includeTriggers: includeTriggers,
      ),
    );
    if (hit == null) return null;
    return _raycastHitFromRaw(hit);
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
    final hits = _bindings.raycastAll(
      ray.origin.x,
      ray.origin.y,
      ray.origin.z,
      dir.x,
      dir.y,
      dir.z,
      maxDistance.isFinite ? maxDistance : double.maxFinite,
      _filterFlags(
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeDynamic: includeDynamic,
        includeTriggers: includeTriggers,
      ),
    );
    final results = <RaycastHit>[];
    for (final hit in hits) {
      final resolved = _raycastHitFromRaw(hit);
      if (resolved != null) results.add(resolved);
    }
    return results;
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
    final handles = _bindings.overlapSphere(
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
    return _overlapHits(handles);
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
    final handles = _bindings.overlapBox(
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
    return _overlapHits(handles);
  }

  List<OverlapHit> _overlapHits(List<int> handles) {
    final results = <OverlapHit>[];
    for (final handle in handles) {
      final collider = _collidersByHandle[handle];
      if (collider == null) continue;
      results.add(OverlapHit(node: collider.node, collider: collider));
    }
    return results;
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
    final origin = from.getTranslation();
    final dir = direction.normalized();
    final flags = _filterFlags(
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    );
    // The probe's world rotation matters for every shape except the
    // rotation-invariant sphere.
    final RawHit? hit;
    if (shape is SphereShape) {
      hit = _bindings.shapeCastSphere(
        origin.x,
        origin.y,
        origin.z,
        shape.radius,
        dir.x,
        dir.y,
        dir.z,
        distance,
        flags,
      );
    } else if (shape is BoxShape) {
      final r = Quaternion.fromRotation(from.getRotation());
      hit = _bindings.shapeCastBox(
        origin.x,
        origin.y,
        origin.z,
        r.x,
        r.y,
        r.z,
        r.w,
        shape.halfExtents.x,
        shape.halfExtents.y,
        shape.halfExtents.z,
        dir.x,
        dir.y,
        dir.z,
        distance,
        flags,
      );
    } else if (shape is CapsuleShape) {
      final r = Quaternion.fromRotation(from.getRotation());
      hit = _bindings.shapeCastCapsule(
        origin.x,
        origin.y,
        origin.z,
        r.x,
        r.y,
        r.z,
        r.w,
        shape.halfHeight,
        shape.radius,
        dir.x,
        dir.y,
        dir.z,
        distance,
        flags,
      );
    } else if (shape is CylinderShape) {
      final r = Quaternion.fromRotation(from.getRotation());
      hit = _bindings.shapeCastCylinder(
        origin.x,
        origin.y,
        origin.z,
        r.x,
        r.y,
        r.z,
        r.w,
        shape.halfHeight,
        shape.radius,
        dir.x,
        dir.y,
        dir.z,
        distance,
        flags,
      );
    } else {
      // TODO(shape-cast-hulls): convex-hull / trimesh / heightfield /
      // compound cast probes are not wired through the backend surface.
      throw UnsupportedError(
        'RapierWorld.shapeCast supports sphere, box, capsule, and cylinder '
        'probes; ${shape.runtimeType} cannot be used as a cast probe.',
      );
    }
    if (hit == null) return null;
    final collider = _collidersByHandle[hit.collider];
    if (collider == null) return null;
    return ShapeCastHit(
      node: collider.node,
      collider: collider,
      worldPoint: hit.point,
      worldNormal: hit.normal,
      distance: hit.distance,
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
