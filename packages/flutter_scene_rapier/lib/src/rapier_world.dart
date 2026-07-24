import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_scene_rapier/src/ffi/rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings_factory.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// [PhysicsSimulation] backed by Rapier 3D.
///
/// The simulation state lives in a [RapierBindings] backend, which owns
/// the world and releases it on [dispose]. [step] forwards directly into
/// Rapier's PhysicsPipeline; [interpolatePoses] lerps and slerps
/// dynamic-body poses between substeps and writes them back to each
/// body's [PoseTarget]. Scene queries ([raycast], [raycastAll],
/// [overlapSphere], [overlapBox], [shapeCast]) run through Rapier's
/// QueryPipeline. Contact and trigger lifecycle events are emitted on
/// [collisions] after each step, with [SimCollisionBegan] carrying the
/// solved contact-manifold points.
///
/// Scene queries run against the broad-phase acceleration structure
/// Rapier rebuilds during [step], so they see colliders as of the most
/// recent step. Apps that step every frame before querying never
/// notice; a query issued before the first step (or against a collider
/// added since the last step) will not see that collider.
///
/// TODO(query-layer-mask): the query methods accept `layerMask` but the
/// backend surface has no per-query group filter yet, so the mask is not
/// applied; wire it into the shim's query filter.
///
/// TODO(shape-cast-hulls): [shapeCast] accepts sphere / box / capsule /
/// cylinder probes; convex-hull, trimesh, heightfield, and compound
/// probes are not wired through the backend surface yet.
class RapierWorld extends PhysicsSimulation {
  RapierWorld({Vector3? gravity}) : _bindings = createRapierBindings() {
    if (gravity != null) this.gravity = gravity;
    final g = this.gravity;
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

  // Tracks the pose target + body type for each registered body handle,
  // so [interpolatePoses] can write back dynamic poses.
  final Map<int, _BodyRecord> _bodies = {};

  @override
  String get backendName => 'rapier3d';

  final StreamController<SimCollisionEvent> _events =
      StreamController<SimCollisionEvent>.broadcast();

  @override
  Stream<SimCollisionEvent> get collisions => _events.stream;

  // --- Bodies ---

  @override
  int createBody({
    required PoseTarget target,
    required BodyType type,
    double? additionalMass,
  }) {
    final position = target.worldTranslation;
    final rotation = target.worldRotation;
    final handle = _bindings.createBody(
      _bodyKindByte(type),
      position.x,
      position.y,
      position.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
      additionalMass ?? 0.0,
    );
    _bodies[handle] = _BodyRecord(
      target,
      type,
      position.clone(),
      rotation.clone(),
    );
    return handle;
  }

  @override
  void destroyBody(int bodyHandle) {
    _bodies.remove(bodyHandle);
    _bindings.destroyBody(bodyHandle);
  }

  @override
  void setBodyKind(int bodyHandle, BodyType type) {
    _bodies[bodyHandle]?.type = type;
    _bindings.setBodyKind(bodyHandle, _bodyKindByte(type));
  }

  /// Creates a fixed body at the world origin to stand in as the static
  /// side of a world-anchored joint, returning its handle. It is not
  /// registered for pose interpolation; the joint that owns it releases
  /// it with [destroyAnchorBody].
  @override
  int createAnchorBody() {
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

  @override
  void destroyAnchorBody(int bodyHandle) => _bindings.destroyBody(bodyHandle);

  @override
  (Vector3, Quaternion) readBodyPose(int bodyHandle) => (
    _bindings.bodyTranslation(bodyHandle),
    _bindings.bodyRotation(bodyHandle),
  );

  @override
  Vector3 readBodyLinearVelocity(int bodyHandle) =>
      _bindings.bodyLinearVelocity(bodyHandle);

  @override
  Vector3 readBodyAngularVelocity(int bodyHandle) =>
      _bindings.bodyAngularVelocity(bodyHandle);

  @override
  void setBodyLinearVelocity(int bodyHandle, Vector3 velocity) {
    _bindings.setBodyLinearVelocity(
      bodyHandle,
      velocity.x,
      velocity.y,
      velocity.z,
      true,
    );
  }

  @override
  void setBodyAngularVelocity(int bodyHandle, Vector3 velocity) {
    _bindings.setBodyAngularVelocity(
      bodyHandle,
      velocity.x,
      velocity.y,
      velocity.z,
      true,
    );
  }

  @override
  void setBodyLinearDamping(int bodyHandle, double damping) =>
      _bindings.setBodyLinearDamping(bodyHandle, damping);

  @override
  void setBodyAngularDamping(int bodyHandle, double damping) =>
      _bindings.setBodyAngularDamping(bodyHandle, damping);

  @override
  void setBodyGravityScale(int bodyHandle, double scale) =>
      _bindings.setBodyGravityScale(bodyHandle, scale);

  @override
  void setBodyCcdEnabled(int bodyHandle, bool enabled) =>
      _bindings.setBodyCcdEnabled(bodyHandle, enabled);

  @override
  void setBodyAdditionalMass(int bodyHandle, double mass) =>
      _bindings.setBodyAdditionalMass(bodyHandle, mass);

  /// Packs [linear] and [angular] into a 6-bit lock field (translation
  /// XYZ in low bits, rotation XYZ in high bits, value 0 = locked) and
  /// pushes it to the backend.
  @override
  void setBodyAxisLocks(int bodyHandle, Vector3 linear, Vector3 angular) {
    var bits = 0;
    if (linear.x == 0) bits |= 1;
    if (linear.y == 0) bits |= 2;
    if (linear.z == 0) bits |= 4;
    if (angular.x == 0) bits |= 8;
    if (angular.y == 0) bits |= 16;
    if (angular.z == 0) bits |= 32;
    _bindings.setBodyLockedAxes(bodyHandle, bits);
  }

  /// Pushes the next-step pose for a kinematic body. Rapier integrates
  /// from the current pose to this target during the next step.
  @override
  void setBodyKinematicTargetPose(
    int bodyHandle,
    Vector3 translation,
    Quaternion rotation,
  ) {
    _bindings.setBodyNextKinematicPose(
      bodyHandle,
      translation.x,
      translation.y,
      translation.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
    );
  }

  @override
  void applyForce(int bodyHandle, Vector3 force, {Vector3? atWorldPoint}) {
    final p = atWorldPoint;
    _bindings.applyBodyForce(
      bodyHandle,
      force.x,
      force.y,
      force.z,
      p != null,
      p?.x ?? 0,
      p?.y ?? 0,
      p?.z ?? 0,
    );
  }

  @override
  void applyImpulse(int bodyHandle, Vector3 impulse, {Vector3? atWorldPoint}) {
    final p = atWorldPoint;
    _bindings.applyBodyImpulse(
      bodyHandle,
      impulse.x,
      impulse.y,
      impulse.z,
      p != null,
      p?.x ?? 0,
      p?.y ?? 0,
      p?.z ?? 0,
    );
  }

  @override
  void applyTorque(int bodyHandle, Vector3 torque) =>
      _bindings.applyBodyTorque(bodyHandle, torque.x, torque.y, torque.z);

  @override
  void applyAngularImpulse(int bodyHandle, Vector3 impulse) => _bindings
      .applyBodyAngularImpulse(bodyHandle, impulse.x, impulse.y, impulse.z);

  @override
  bool isBodySleeping(int bodyHandle) => _bindings.isBodySleeping(bodyHandle);

  @override
  void wakeBody(int bodyHandle) => _bindings.wakeBody(bodyHandle);

  @override
  void sleepBody(int bodyHandle) => _bindings.sleepBody(bodyHandle);

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

  // --- Colliders ---

  @override
  List<int> createColliders(
    int bodyHandle,
    Shape shape, {
    PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
    bool isTrigger = false,
    Matrix4? localPose,
    int collisionLayer = 0xFFFFFFFF,
    int collisionMask = 0xFFFFFFFF,
  }) {
    final handles = _cookShape(
      bodyHandle,
      shape,
      material,
      isTrigger,
      localPose ?? Matrix4.identity(),
    );
    if (collisionLayer != 0xFFFFFFFF || collisionMask != 0xFFFFFFFF) {
      for (final handle in handles) {
        _bindings.setColliderCollisionGroups(
          handle,
          collisionLayer,
          collisionMask,
        );
      }
    }
    return handles;
  }

  // Cooks [shape] into Rapier colliders on [bodyHandle], recursing into
  // compound children (each child becomes its own collider, so a Dart
  // compound produces multiple handles). Returns an empty list when
  // Rapier rejects the shape (degenerate hull, malformed trimesh).
  List<int> _cookShape(
    int bodyHandle,
    Shape shape,
    PhysicsMaterial material,
    bool isTrigger,
    Matrix4 pose,
  ) {
    final t = pose.getTranslation();
    final r = Quaternion.fromRotation(pose.getRotation());
    switch (shape) {
      case SphereShape():
        return [
          _bindings.colliderSphere(
            bodyHandle,
            shape.radius,
            material,
            isTrigger,
            t.x,
            t.y,
            t.z,
            r.x,
            r.y,
            r.z,
            r.w,
          ),
        ];
      case BoxShape():
        return [
          _bindings.colliderBox(
            bodyHandle,
            shape.halfExtents.x,
            shape.halfExtents.y,
            shape.halfExtents.z,
            material,
            isTrigger,
            t.x,
            t.y,
            t.z,
            r.x,
            r.y,
            r.z,
            r.w,
          ),
        ];
      case CapsuleShape():
        return [
          _bindings.colliderCapsule(
            bodyHandle,
            shape.halfHeight,
            shape.radius,
            material,
            isTrigger,
            t.x,
            t.y,
            t.z,
            r.x,
            r.y,
            r.z,
            r.w,
          ),
        ];
      case CylinderShape():
        return [
          _bindings.colliderCylinder(
            bodyHandle,
            shape.halfHeight,
            shape.radius,
            material,
            isTrigger,
            t.x,
            t.y,
            t.z,
            r.x,
            r.y,
            r.z,
            r.w,
          ),
        ];
      case ConvexHullShape():
        final handle = _bindings.colliderConvexHull(
          bodyHandle,
          shape.points,
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
        return handle == null ? const [] : [handle];
      case TriMeshShape():
        final handle = _bindings.colliderTriMesh(
          bodyHandle,
          shape.vertices,
          shape.indices,
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
        return handle == null ? const [] : [handle];
      case HeightFieldShape():
        // The Dart heights are row-major (heights[z * width + x]); the
        // backend transposes into the column-major layout Rapier wants.
        return [
          _bindings.colliderHeightField(
            bodyHandle,
            shape.depth, // nrows = Z dimension
            shape.width, // ncols = X dimension
            shape.heights,
            shape.scale.x,
            shape.scale.y,
            shape.scale.z,
            material,
            isTrigger,
            t.x,
            t.y,
            t.z,
            r.x,
            r.y,
            r.z,
            r.w,
          ),
        ];
      case CompoundShape():
        final result = <int>[];
        for (final child in shape.children) {
          result.addAll(
            _cookShape(
              bodyHandle,
              child.shape,
              material,
              isTrigger,
              pose.multiplied(child.localPose),
            ),
          );
        }
        return result;
    }
  }

  @override
  void destroyCollider(int colliderHandle) =>
      _bindings.destroyCollider(colliderHandle);

  @override
  void setColliderMaterial(int colliderHandle, PhysicsMaterial material) =>
      _bindings.setColliderMaterial(colliderHandle, material);

  @override
  void setColliderFilter(int colliderHandle, int layer, int mask) =>
      _bindings.setColliderCollisionGroups(colliderHandle, layer, mask);

  // --- Joints ---

  // TODO(revolute-axis-b): the shim takes a single joint axis, so
  // RevoluteJointDesc.localAxisB and PrismaticJointDesc.localAxisB are
  // ignored; extend the shim to take per-body axes.
  @override
  int createJoint(JointDesc desc) {
    switch (desc) {
      case FixedJointDesc():
        return _bindings.jointFixed(
          desc.bodyA,
          desc.bodyB,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.collisionsEnabled,
        );
      case SphericalJointDesc():
        return _bindings.jointSpherical(
          desc.bodyA,
          desc.bodyB,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.collisionsEnabled,
        );
      case RevoluteJointDesc():
        return _bindings.jointRevolute(
          desc.bodyA,
          desc.bodyB,
          desc.localAxisA,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.lowerLimit,
          desc.upperLimit,
          desc.motorTargetVelocity,
          desc.motorMaxForce,
          desc.collisionsEnabled,
        );
      case PrismaticJointDesc():
        return _bindings.jointPrismatic(
          desc.bodyA,
          desc.bodyB,
          desc.localAxisA,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.lowerLimit,
          desc.upperLimit,
          desc.motorTargetVelocity,
          desc.motorMaxForce,
          desc.collisionsEnabled,
        );
      case GenericJointDesc():
        return _bindings.jointGeneric(
          desc.bodyA,
          desc.bodyB,
          desc.localAnchorA,
          desc.localBasisA,
          desc.localAnchorB,
          desc.localBasisB,
          desc.axes,
          desc.collisionsEnabled,
        );
    }
  }

  @override
  void updateJoint(int jointHandle, JointDesc desc) {
    switch (desc) {
      case FixedJointDesc():
        _bindings.jointUpdateFixed(
          jointHandle,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.collisionsEnabled,
        );
      case SphericalJointDesc():
        _bindings.jointUpdateSpherical(
          jointHandle,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.collisionsEnabled,
        );
      case RevoluteJointDesc():
        _bindings.jointUpdateRevolute(
          jointHandle,
          desc.localAxisA,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.lowerLimit,
          desc.upperLimit,
          desc.motorTargetVelocity,
          desc.motorMaxForce,
          desc.collisionsEnabled,
        );
      case PrismaticJointDesc():
        _bindings.jointUpdatePrismatic(
          jointHandle,
          desc.localAxisA,
          desc.localAnchorA,
          desc.localAnchorB,
          desc.lowerLimit,
          desc.upperLimit,
          desc.motorTargetVelocity,
          desc.motorMaxForce,
          desc.collisionsEnabled,
        );
      case GenericJointDesc():
        _bindings.jointUpdateGeneric(
          jointHandle,
          desc.localAnchorA,
          desc.localBasisA,
          desc.localAnchorB,
          desc.localBasisB,
          desc.axes,
          desc.collisionsEnabled,
        );
    }
  }

  @override
  void destroyJoint(int jointHandle) => _bindings.destroyJoint(jointHandle);

  // --- Queries ---

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

  SimRaycastHit _hitFromRaw(RawHit hit) => SimRaycastHit(
    colliderHandle: hit.collider,
    worldPoint: hit.point,
    worldNormal: hit.normal,
    distance: hit.distance,
  );

  @override
  SimRaycastHit? raycast(
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
    return _hitFromRaw(hit);
  }

  @override
  List<SimRaycastHit> raycastAll(
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
    return [for (final hit in hits) _hitFromRaw(hit)];
  }

  @override
  List<SimOverlapHit> overlapSphere(
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
    return [
      for (final handle in handles) SimOverlapHit(colliderHandle: handle),
    ];
  }

  @override
  List<SimOverlapHit> overlapBox(
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
    return [
      for (final handle in handles) SimOverlapHit(colliderHandle: handle),
    ];
  }

  @override
  SimShapeCastHit? shapeCast(
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
    return SimShapeCastHit(
      colliderHandle: hit.collider,
      worldPoint: hit.point,
      worldNormal: hit.normal,
      distance: hit.distance,
    );
  }

  // --- Characters ---

  @override
  bool get supportsCharacters => true;

  /// Runs one kinematic-character move for the character whose shape is
  /// [colliderHandle]. Returns the corrected world-space translation to
  /// apply plus the grounded / sliding flags. Pass a null [snapToGround]
  /// to disable snapping and `autostep: false` to disable stepping.
  @override
  CharacterMovement moveCharacter(
    int colliderHandle, {
    required Vector3 position,
    required Vector3 desiredTranslation,
    double? deltaSeconds,
    Vector3? up,
    double offset = 0.01,
    bool slide = true,
    double maxSlopeClimbAngle = math.pi / 4,
    double minSlopeSlideAngle = math.pi / 4,
    double? snapToGround = 0.1,
    bool autostep = false,
    double autostepMaxHeight = 0.3,
    double autostepMinWidth = 0.1,
    bool autostepIncludeDynamicBodies = true,
    double characterMass = 0.0,
  }) {
    final upDir = up ?? Vector3(0, 1, 0);
    final movement = _bindings.moveCharacter(
      colliderHandle,
      position.x,
      position.y,
      position.z,
      desiredTranslation.x,
      desiredTranslation.y,
      desiredTranslation.z,
      deltaSeconds ?? fixedTimestep,
      upDir.x,
      upDir.y,
      upDir.z,
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
    return CharacterMovement(
      translation: movement.translation,
      grounded: movement.grounded,
      slidingDownSlope: movement.slidingDownSlope,
    );
  }

  // --- Stepping ---

  @override
  void step(double fixedDt) {
    final g = gravity;
    _bindings.setGravity(g.x, g.y, g.z);
    _bindings.step(fixedDt);
    // Capture this step's pose for dynamic bodies so interpolatePoses
    // can lerp/slerp between substeps.
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
  void interpolatePoses(double alpha) {
    // Blend each dynamic body's pose by alpha between the previous and
    // current step (alpha == 0 snaps to previous, alpha == 1 snaps to
    // current). Fixed and kinematic bodies are not touched; the owner
    // drives those poses.
    final t = Vector3.zero();
    for (final record in _bodies.values) {
      if (record.type != BodyType.dynamic_) continue;
      t
        ..setFrom(record.currTranslation)
        ..sub(record.prevTranslation)
        ..scale(alpha)
        ..add(record.prevTranslation);
      final rot = _slerp(record.prevRotation, record.currRotation, alpha);
      record.target.setWorldPose(t, rot);
    }
  }

  @override
  void dispose() {
    _events.close();
    _bodies.clear();
    _bindings.dispose();
  }

  // Drains the collision events Rapier generated during the last step
  // and emits them on the [collisions] stream, keyed by collider handle.
  // A pair involving a sensor maps to the trigger events; a solid pair
  // maps to the collision events, whose [SimCollisionBegan] carries the
  // solved contact-manifold points.
  void _drainCollisionEvents() {
    if (!_events.hasListener) return;
    final count = _bindings.collisionEventCount();
    for (var i = 0; i < count; i++) {
      final raw = _bindings.collisionEventAt(i);
      if (raw == null) continue;
      final SimCollisionEvent event;
      if (raw.sensor) {
        event = raw.started
            ? SimTriggerEntered(
                colliderHandleA: raw.colliderA,
                colliderHandleB: raw.colliderB,
              )
            : SimTriggerExited(
                colliderHandleA: raw.colliderA,
                colliderHandleB: raw.colliderB,
              );
      } else {
        event = raw.started
            ? SimCollisionBegan(
                colliderHandleA: raw.colliderA,
                colliderHandleB: raw.colliderB,
                contacts: _readContacts(raw.contactStart, raw.contactCount),
              )
            : SimCollisionEnded(
                colliderHandleA: raw.colliderA,
                colliderHandleB: raw.colliderB,
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
}

class _BodyRecord {
  _BodyRecord(
    this.target,
    this.type,
    Vector3 initialTranslation,
    Quaternion initialRotation,
  ) : prevTranslation = initialTranslation.clone(),
      currTranslation = initialTranslation,
      prevRotation = initialRotation.clone(),
      currRotation = initialRotation;

  final PoseTarget target;
  BodyType type;
  // Pose after the previous physics step (or the initial pose, on the
  // first step). Used by [RapierWorld.interpolatePoses] to blend between
  // substeps for smooth rendering.
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
