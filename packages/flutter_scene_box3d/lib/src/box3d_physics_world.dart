import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:box3d/box3d.dart' as b3;
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// [PhysicsSimulation] backed by the box3d engine.
///
/// Wraps a box3d [b3.Box3dWorld] and addresses it through the contract's
/// integer handles; body and collider handles are box3d's own native
/// handles. [step] advances the simulation and captures each dynamic
/// body's pose; [interpolatePoses] lerps and slerps those poses between
/// steps and writes them back to each body's [PoseTarget]. Queries and
/// collision events report collider handles for the engine layer to
/// resolve.
///
/// Call [Box3dPhysicsWorld.ensureInitialized] once during startup before
/// constructing a world (a no-op on native platforms).
class Box3dPhysicsWorld extends PhysicsSimulation {
  Box3dPhysicsWorld({Vector3? gravity})
    : _world = b3.Box3dWorld(gravity: gravity) {
    if (gravity != null) this.gravity = gravity;
  }

  /// Prepares the box3d backend so a [Box3dPhysicsWorld] can be
  /// constructed. Returns immediately on native targets; on the web it
  /// loads the WebAssembly module. Await it once during startup.
  static Future<void> ensureInitialized() => b3.Box3d.ensureInitialized();

  final b3.Box3dWorld _world;

  /// The underlying box3d world, for direct access to backend features the
  /// contract does not cover.
  b3.Box3dWorld get nativeWorld => _world;

  // Tracks each body so interpolatePoses can write back dynamic poses.
  final Map<int, _BodyRecord> _bodies = {};

  // Maps a collider handle to its box3d shape for mutation and teardown,
  // and to its owning body handle.
  final Map<int, b3.Box3dShape> _shapes = {};
  final Map<int, int> _shapeOwners = {};

  final Map<int, b3.Box3dJoint> _joints = {};
  int _nextJointHandle = 1;

  @override
  String get backendName => 'box3d';

  final StreamController<SimCollisionEvent> _events =
      StreamController<SimCollisionEvent>.broadcast();

  @override
  Stream<SimCollisionEvent> get collisions => _events.stream;

  // --- Bodies ----------------------------------------------------------------

  static b3.Box3dBodyType _kind(BodyType type) => switch (type) {
    BodyType.fixed => b3.Box3dBodyType.static_,
    BodyType.kinematic => b3.Box3dBodyType.kinematic,
    BodyType.dynamic_ => b3.Box3dBodyType.dynamic_,
  };

  _BodyRecord _record(int bodyHandle) {
    final record = _bodies[bodyHandle];
    if (record == null) {
      throw StateError('Unknown box3d body handle $bodyHandle');
    }
    return record;
  }

  b3.Box3dBody _body(int bodyHandle) => _record(bodyHandle).body;

  @override
  int createBody({
    required PoseTarget target,
    required BodyType type,
    double? additionalMass,
  }) {
    final body = _world.createBody(
      type: _kind(type),
      position: target.worldTranslation,
      rotation: target.worldRotation,
    );
    // TODO(box3d-mass-override): additionalMass is stored but not pushed;
    // box3d derives mass from shape densities and the package exposes no
    // explicit mass setter.
    _bodies[body.handle] = _BodyRecord(body, target, type)
      ..additionalMass = additionalMass;
    return body.handle;
  }

  @override
  void destroyBody(int bodyHandle) {
    final record = _bodies.remove(bodyHandle);
    if (record == null) return;
    // box3d cascades body destruction to its shapes.
    for (final shapeHandle in record.shapeHandles) {
      _shapes.remove(shapeHandle);
      _shapeOwners.remove(shapeHandle);
    }
    record.body.destroy();
  }

  @override
  void setBodyKind(int bodyHandle, BodyType type) {
    final record = _record(bodyHandle);
    record.type = type;
    record.body.type = _kind(type);
    // Resync so a body becoming dynamic does not interpolate from a pose
    // captured at creation.
    record.resyncPoses();
  }

  @override
  int createAnchorBody() {
    final body = _world.createBody(type: b3.Box3dBodyType.static_);
    _bodies[body.handle] = _BodyRecord(
      body,
      SimplePoseTarget(),
      BodyType.fixed,
    );
    return body.handle;
  }

  @override
  void destroyAnchorBody(int bodyHandle) => destroyBody(bodyHandle);

  @override
  (Vector3, Quaternion) readBodyPose(int bodyHandle) {
    final body = _body(bodyHandle);
    return (body.position, body.rotation);
  }

  @override
  Vector3 readBodyLinearVelocity(int bodyHandle) =>
      _body(bodyHandle).linearVelocity;

  @override
  Vector3 readBodyAngularVelocity(int bodyHandle) =>
      _body(bodyHandle).angularVelocity;

  @override
  void setBodyLinearVelocity(int bodyHandle, Vector3 velocity) =>
      _body(bodyHandle).linearVelocity = velocity;

  @override
  void setBodyAngularVelocity(int bodyHandle, Vector3 velocity) =>
      _body(bodyHandle).angularVelocity = velocity;

  @override
  void setBodyLinearDamping(int bodyHandle, double damping) =>
      _body(bodyHandle).linearDamping = damping;

  @override
  void setBodyAngularDamping(int bodyHandle, double damping) =>
      _body(bodyHandle).angularDamping = damping;

  @override
  void setBodyGravityScale(int bodyHandle, double scale) =>
      _body(bodyHandle).gravityScale = scale;

  @override
  void setBodyCcdEnabled(int bodyHandle, bool enabled) =>
      _body(bodyHandle).isBullet = enabled;

  @override
  void setBodyAdditionalMass(int bodyHandle, double mass) {
    // TODO(box3d-mass-override): stored only; see createBody.
    _record(bodyHandle).additionalMass = mass;
  }

  @override
  void setBodyAxisLocks(int bodyHandle, Vector3 linear, Vector3 angular) =>
      _body(bodyHandle).setMotionLocks(
        linearX: linear.x == 0,
        linearY: linear.y == 0,
        linearZ: linear.z == 0,
        angularX: angular.x == 0,
        angularY: angular.y == 0,
        angularZ: angular.z == 0,
      );

  @override
  void setBodyKinematicTargetPose(
    int bodyHandle,
    Vector3 translation,
    Quaternion rotation,
  ) => _body(bodyHandle).setTransform(translation, rotation);

  @override
  void applyForce(int bodyHandle, Vector3 force, {Vector3? atWorldPoint}) =>
      _body(bodyHandle).applyForce(force, point: atWorldPoint);

  @override
  void applyImpulse(int bodyHandle, Vector3 impulse, {Vector3? atWorldPoint}) =>
      _body(bodyHandle).applyImpulse(impulse, point: atWorldPoint);

  @override
  void applyTorque(int bodyHandle, Vector3 torque) =>
      _body(bodyHandle).applyTorque(torque);

  @override
  void applyAngularImpulse(int bodyHandle, Vector3 impulse) =>
      _body(bodyHandle).applyAngularImpulse(impulse);

  @override
  bool isBodySleeping(int bodyHandle) => !_body(bodyHandle).isAwake;

  @override
  void wakeBody(int bodyHandle) => _body(bodyHandle).wakeUp();

  @override
  void sleepBody(int bodyHandle) => _body(bodyHandle).sleep();

  // --- Colliders ---------------------------------------------------------------
  //
  // [localPose] is baked into the shape geometry: a non-identity pose turns
  // a box into an equivalent convex hull and transforms hull/mesh points.
  // TODO(box3d-collider-localpose): a non-identity pose on a cylinder or
  // height field throws, since box3d cannot offset those through the
  // current package surface. TODO(box3d-combine-rules): PhysicsMaterial
  // combine rules are not represented by box3d.

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
    final record = _record(bodyHandle);
    final b3Material = _b3Material(material);
    final shapes = _cook(
      shape,
      localPose ?? Matrix4.identity(),
      record.body,
      b3Material,
      isTrigger,
    );
    final handles = <int>[];
    for (final b3Shape in shapes) {
      b3Shape.setCollisionFilter(category: collisionLayer, mask: collisionMask);
      b3Shape.contactEventsEnabled = true;
      b3Shape.sensorEventsEnabled = true;
      _shapes[b3Shape.handle] = b3Shape;
      _shapeOwners[b3Shape.handle] = bodyHandle;
      record.shapeHandles.add(b3Shape.handle);
      handles.add(b3Shape.handle);
    }
    return handles;
  }

  @override
  void destroyCollider(int colliderHandle) {
    final shape = _shapes.remove(colliderHandle);
    if (shape == null) return;
    final owner = _shapeOwners.remove(colliderHandle);
    _bodies[owner]?.shapeHandles.remove(colliderHandle);
    shape.destroy();
  }

  @override
  void setColliderMaterial(int colliderHandle, PhysicsMaterial material) =>
      _shape(colliderHandle).setMaterial(_b3Material(material));

  @override
  void setColliderFilter(int colliderHandle, int layer, int mask) =>
      _shape(colliderHandle).setCollisionFilter(category: layer, mask: mask);

  b3.Box3dShape _shape(int colliderHandle) {
    final shape = _shapes[colliderHandle];
    if (shape == null) {
      throw StateError('Unknown box3d collider handle $colliderHandle');
    }
    return shape;
  }

  static b3.Box3dMaterial _b3Material(PhysicsMaterial material) =>
      b3.Box3dMaterial(
        friction: material.friction,
        restitution: material.restitution,
        density: material.density,
      );

  List<b3.Box3dShape> _cook(
    Shape shape,
    Matrix4 pose,
    b3.Box3dBody body,
    b3.Box3dMaterial material,
    bool isTrigger,
  ) {
    switch (shape) {
      case SphereShape():
        return [
          body.addSphere(
            shape.radius,
            center: pose.getTranslation(),
            material: material,
            isSensor: isTrigger,
          ),
        ];
      case BoxShape():
        if (pose.isIdentity()) {
          return [
            body.addBox(
              shape.halfExtents,
              material: material,
              isSensor: isTrigger,
            ),
          ];
        }
        // An offset/rotated box is expressed as the convex hull of its eight
        // transformed corners.
        final hull = body.addConvexHull(
          _boxCorners(shape.halfExtents, pose),
          material: material,
          isSensor: isTrigger,
        );
        return hull == null ? const [] : [hull];
      case CapsuleShape():
        final a = pose.transformed3(Vector3(0, -shape.halfHeight, 0));
        final b = pose.transformed3(Vector3(0, shape.halfHeight, 0));
        return [
          body.addCapsule(
            shape.radius,
            pointA: a,
            pointB: b,
            material: material,
            isSensor: isTrigger,
          ),
        ];
      case CylinderShape():
        if (!pose.isIdentity()) {
          throw UnsupportedError(
            'Box3dPhysicsWorld does not support a non-identity localPose on '
            'a CylinderShape yet.',
          );
        }
        return [
          body.addCylinder(
            shape.halfHeight,
            shape.radius,
            material: material,
            isSensor: isTrigger,
          ),
        ];
      case ConvexHullShape():
        final hull = body.addConvexHull(
          _transformPoints(shape.points, pose),
          material: material,
          isSensor: isTrigger,
        );
        return hull == null ? const [] : [hull];
      case TriMeshShape():
        final mesh = body.addTriMesh(
          _transformPoints(shape.vertices, pose),
          shape.indices,
          material: material,
          isSensor: isTrigger,
        );
        return mesh == null ? const [] : [mesh];
      case HeightFieldShape():
        if (!pose.isIdentity()) {
          throw UnsupportedError(
            'Box3dPhysicsWorld does not support a non-identity localPose on '
            'a HeightFieldShape yet.',
          );
        }
        final field = body.addHeightField(
          countX: shape.width,
          countZ: shape.depth,
          heights: shape.heights,
          scale: shape.scale,
          material: material,
          isSensor: isTrigger,
        );
        return field == null ? const [] : [field];
      case CompoundShape():
        return [
          for (final child in shape.children)
            ..._cook(
              child.shape,
              pose.multiplied(child.localPose),
              body,
              material,
              isTrigger,
            ),
        ];
    }
  }

  // The eight corners of a box (half extents [h]) transformed by [pose],
  // packed as xyz triplets.
  static Float32List _boxCorners(Vector3 h, Matrix4 pose) {
    final out = Float32List(24);
    var i = 0;
    for (final sx in const [-1.0, 1.0]) {
      for (final sy in const [-1.0, 1.0]) {
        for (final sz in const [-1.0, 1.0]) {
          final v = pose.transformed3(Vector3(sx * h.x, sy * h.y, sz * h.z));
          out[i++] = v.x;
          out[i++] = v.y;
          out[i++] = v.z;
        }
      }
    }
    return out;
  }

  // Copies [src] (packed xyz) transformed by [pose].
  static Float32List _transformPoints(Float32List src, Matrix4 pose) {
    if (pose.isIdentity()) return src;
    final out = Float32List(src.length);
    for (var i = 0; i < src.length; i += 3) {
      final v = pose.transformed3(Vector3(src[i], src[i + 1], src[i + 2]));
      out[i] = v.x;
      out[i + 1] = v.y;
      out[i + 2] = v.z;
    }
    return out;
  }

  // --- Joints ----------------------------------------------------------------

  @override
  int createJoint(JointDesc desc) {
    final joint = _buildJoint(desc);
    final handle = _nextJointHandle++;
    _joints[handle] = joint;
    return handle;
  }

  @override
  void updateJoint(int jointHandle, JointDesc desc) {
    // box3d has no in-place reconfiguration, so recreate under the same
    // handle.
    final old = _joints[jointHandle];
    if (old == null) {
      throw StateError('Unknown box3d joint handle $jointHandle');
    }
    old.destroy();
    _joints[jointHandle] = _buildJoint(desc);
  }

  @override
  void destroyJoint(int jointHandle) => _joints.remove(jointHandle)?.destroy();

  b3.Box3dJoint _buildJoint(JointDesc desc) {
    final bodyA = _body(desc.bodyA);
    final bodyB = _body(desc.bodyB);
    switch (desc) {
      case FixedJointDesc():
        // Choose frames so the weld holds the current relative pose:
        // worldA * frameA == worldB * frameB with frameA at A's origin.
        // The anchors do not change a rigid weld's constraint set.
        final worldA = _worldOf(bodyA);
        final worldB = _worldOf(bodyB);
        final relative = Matrix4.inverted(worldB)..multiply(worldA);
        return _world.createWeldJoint(
          bodyA,
          bodyB,
          frameB: b3.Box3dFrame(
            position: relative.getTranslation(),
            rotation: Quaternion.fromRotation(relative.getRotation()),
          ),
          collideConnected: desc.collisionsEnabled,
        );
      case SphericalJointDesc():
        return _world.createSphericalJoint(
          bodyA,
          bodyB,
          frameA: b3.Box3dFrame(position: desc.localAnchorA),
          frameB: b3.Box3dFrame(position: desc.localAnchorB),
          collideConnected: desc.collisionsEnabled,
        );
      case RevoluteJointDesc():
        return _world.createRevoluteJoint(
          bodyA,
          bodyB,
          frameA: b3.Box3dFrame.pointAxis(
            desc.localAnchorA,
            desc.localAxisA.normalized(),
          ),
          frameB: b3.Box3dFrame.pointAxis(
            desc.localAnchorB,
            desc.localAxisB.normalized(),
          ),
          lowerLimit: desc.lowerLimit,
          upperLimit: desc.upperLimit,
          motorSpeed: desc.motorTargetVelocity,
          maxMotorTorque: desc.motorMaxForce,
          collideConnected: desc.collisionsEnabled,
        );
      case PrismaticJointDesc():
        return _world.createPrismaticJoint(
          bodyA,
          bodyB,
          // A prismatic joint's slide axis is the frame's local X.
          frameA: b3.Box3dFrame.pointAxisX(
            desc.localAnchorA,
            desc.localAxisA.normalized(),
          ),
          frameB: b3.Box3dFrame.pointAxisX(
            desc.localAnchorB,
            desc.localAxisB.normalized(),
          ),
          // box3d measures this joint's translation opposite to the
          // contract's convention (positive along +axis, measured from
          // body A), so negate and swap the limits and negate the motor
          // velocity.
          lowerLimit: desc.upperLimit == null ? null : -desc.upperLimit!,
          upperLimit: desc.lowerLimit == null ? null : -desc.lowerLimit!,
          motorSpeed: desc.motorTargetVelocity == null
              ? null
              : -desc.motorTargetVelocity!,
          maxMotorForce: desc.motorMaxForce,
          collideConnected: desc.collisionsEnabled,
        );
      case GenericJointDesc():
        // TODO(box3d-generic-joint): box3d has no 6-DOF generic joint. Use
        // the fixed, spherical, revolute, or prismatic joints instead.
        throw UnsupportedError('box3d has no generic 6-DOF joint');
    }
  }

  // The current world transform of a body, for joint frame math.
  static Matrix4 _worldOf(b3.Box3dBody body) =>
      Matrix4.compose(body.position, body.rotation, Vector3(1, 1, 1));

  // --- Queries ---------------------------------------------------------------
  //
  // box3d's category/mask filter matches the contract's layer/mask
  // semantics. The include* body-type flags are not part of box3d's query
  // filter; TODO(box3d-query-typefilter) apply them by post-filtering hits
  // on the owning body type once bodies expose it here.

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
    final hit = _world.raycast(
      ray.origin,
      ray.direction,
      maxDistance: maxDistance.isFinite ? maxDistance : 1e6,
      mask: layerMask,
    );
    return hit == null ? null : _raycastHit(hit);
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
    final hits = _world.raycastAll(
      ray.origin,
      ray.direction,
      maxDistance: maxDistance.isFinite ? maxDistance : 1e6,
      mask: layerMask,
    );
    return [for (final h in hits) _raycastHit(h)];
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
  }) => [
    for (final handle in _world.overlapSphere(center, radius, mask: layerMask))
      SimOverlapHit(colliderHandle: handle),
  ];

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
  }) => [
    for (final handle in _world.overlapBox(
      center,
      halfExtents,
      rotation: rotation,
      mask: layerMask,
    ))
      SimOverlapHit(colliderHandle: handle),
  ];

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
    final b3.Box3dRayHit? hit;
    switch (shape) {
      case SphereShape():
        hit = _world.shapeCastSphere(
          origin,
          shape.radius,
          direction,
          maxDistance: distance,
          mask: layerMask,
        );
      case BoxShape():
        hit = _world.shapeCastBox(
          origin,
          shape.halfExtents,
          direction,
          rotation: Quaternion.fromRotation(from.getRotation()),
          maxDistance: distance,
          mask: layerMask,
        );
      default:
        // TODO(box3d-shapecast-shapes): box3d shape casts are wired for
        // sphere and box probes; capsule, cylinder, hull, mesh, and
        // heightfield probes are not exposed through the package yet.
        throw UnsupportedError(
          'Box3dPhysicsWorld.shapeCast supports sphere and box probes; '
          '${shape.runtimeType} cannot be used as a cast probe.',
        );
    }
    if (hit == null) return null;
    return SimShapeCastHit(
      colliderHandle: hit.shape,
      worldPoint: hit.point,
      worldNormal: hit.normal,
      distance: hit.distance,
    );
  }

  static SimRaycastHit _raycastHit(b3.Box3dRayHit hit) => SimRaycastHit(
    colliderHandle: hit.shape,
    worldPoint: hit.point,
    worldNormal: hit.normal,
    distance: hit.distance,
  );

  // --- Stepping --------------------------------------------------------------

  @override
  void step(double fixedDt) {
    _world.gravity = gravity;
    _world.step(fixedDt);
    for (final record in _bodies.values) {
      if (record.type != BodyType.dynamic_) continue;
      record.prevTranslation.setFrom(record.currTranslation);
      record.prevRotation.setFrom(record.currRotation);
      record.currTranslation.setFrom(record.body.position);
      record.currRotation.setFrom(record.body.rotation);
    }
    _drainEvents();
  }

  @override
  void interpolatePoses(double alpha) {
    final t = Vector3.zero();
    for (final record in _bodies.values) {
      if (record.type != BodyType.dynamic_) continue;
      t
        ..setFrom(record.currTranslation)
        ..sub(record.prevTranslation)
        ..scale(alpha)
        ..add(record.prevTranslation);
      record.target.setWorldPose(
        t,
        _slerp(record.prevRotation, record.currRotation, alpha),
      );
    }
  }

  // Drains box3d's per-step events and re-emits them as contract events
  // keyed by collider handle.
  void _drainEvents() {
    if (!_events.hasListener) return;
    final events = _world.drainEvents();
    for (final e in events.contactBegan) {
      _events.add(
        SimCollisionBegan(
          colliderHandleA: e.shapeA,
          colliderHandleB: e.shapeB,
          contacts: [
            for (final p in e.points)
              ContactPoint(
                worldPosition: p.position,
                worldNormal: p.normal,
                impulse: p.impulse,
                separation: p.separation,
              ),
          ],
        ),
      );
    }
    for (final e in events.contactEnded) {
      _events.add(
        SimCollisionEnded(colliderHandleA: e.shapeA, colliderHandleB: e.shapeB),
      );
    }
    for (final e in events.sensorBegan) {
      _events.add(
        SimTriggerEntered(
          colliderHandleA: e.sensorShape,
          colliderHandleB: e.visitorShape,
        ),
      );
    }
    for (final e in events.sensorEnded) {
      _events.add(
        SimTriggerExited(
          colliderHandleA: e.sensorShape,
          colliderHandleB: e.visitorShape,
        ),
      );
    }
  }

  @override
  void dispose() {
    _events.close();
    _bodies.clear();
    _shapes.clear();
    _shapeOwners.clear();
    _joints.clear();
    _world.dispose();
  }
}

class _BodyRecord {
  _BodyRecord(this.body, this.target, this.type)
    : prevTranslation = body.position,
      currTranslation = body.position,
      prevRotation = body.rotation,
      currRotation = body.rotation;

  final b3.Box3dBody body;
  final PoseTarget target;
  BodyType type;
  double? additionalMass;
  final List<int> shapeHandles = [];
  final Vector3 prevTranslation;
  final Vector3 currTranslation;
  final Quaternion prevRotation;
  final Quaternion currRotation;

  // Snaps the interpolation window to the body's current pose.
  void resyncPoses() {
    prevTranslation.setFrom(body.position);
    currTranslation.setFrom(body.position);
    prevRotation.setFrom(body.rotation);
    currRotation.setFrom(body.rotation);
  }
}

/// Shortest-arc quaternion slerp between [a] and [b] by [t], falling back
/// to normalized-lerp when the rotations are nearly identical.
Quaternion _slerp(Quaternion a, Quaternion b, double t) {
  var bx = b.x, by = b.y, bz = b.z, bw = b.w;
  var dot = a.x * bx + a.y * by + a.z * bz + a.w * bw;
  if (dot < 0) {
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
    dot = -dot;
  }
  if (dot > 0.9995) {
    return Quaternion(
      a.x + t * (bx - a.x),
      a.y + t * (by - a.y),
      a.z + t * (bz - a.z),
      a.w + t * (bw - a.w),
    )..normalize();
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
