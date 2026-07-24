import 'dart:async';

import 'package:vector_math/vector_math.dart';

import 'joint_desc.dart';
import 'material.dart';
import 'pose_target.dart';
import 'shape.dart';
import 'shape_queries.dart';
import 'sim_types.dart';
import 'simulation.dart';

class _BasicBody {
  _BasicBody(this.target, this.type);

  final PoseTarget target;
  BodyType type;
  final Vector3 linearVelocity = Vector3.zero();
  final Vector3 angularVelocity = Vector3.zero();
}

class _BasicCollider {
  _BasicCollider(
    this.bodyHandle,
    this.shape,
    this.isTrigger,
    this.layer,
    this.mask,
    this.localPose,
  );

  final int bodyHandle;
  final Shape shape;
  bool isTrigger;
  int layer;
  int mask;
  final Matrix4 localPose;
}

class _Pair {
  _Pair(int a, int b) : a = a <= b ? a : b, b = a <= b ? b : a;

  final int a;
  final int b;

  @override
  bool operator ==(Object other) =>
      other is _Pair && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}

/// Pure-Dart [PhysicsSimulation] suitable for picking, area triggers, and
/// kinematic-only gameplay.
///
/// Supports scene queries and trigger events; does not simulate dynamics
/// (no solver, no contact response, no joints). Dynamic bodies and joints
/// throw [UnsupportedError]; for full rigid-body simulation use a backend
/// package with a solver.
class BasicSimulation extends PhysicsSimulation {
  BasicSimulation({Vector3? gravity}) {
    if (gravity != null) this.gravity = gravity;
  }

  @override
  String get backendName => 'basic';

  int _nextHandle = 1;
  final Map<int, _BasicBody> _bodies = {};
  final Map<int, _BasicCollider> _colliders = {};
  final Set<_Pair> _prevTriggerPairs = {};
  final StreamController<SimCollisionEvent> _events =
      StreamController<SimCollisionEvent>.broadcast();

  @override
  Stream<SimCollisionEvent> get collisions => _events.stream;

  Matrix4 _colliderWorldPose(_BasicCollider collider) {
    final body = _bodies[collider.bodyHandle]!;
    return Matrix4.compose(
      body.target.worldTranslation,
      body.target.worldRotation,
      Vector3(1, 1, 1),
    ).multiplied(collider.localPose);
  }

  // --- Bodies ---

  @override
  int createBody({
    required PoseTarget target,
    required BodyType type,
    double? additionalMass,
  }) {
    if (type == BodyType.dynamic_) {
      throw UnsupportedError(
        'BasicSimulation does not simulate dynamics; use a backend with a '
        'solver for BodyType.dynamic_.',
      );
    }
    final handle = _nextHandle++;
    _bodies[handle] = _BasicBody(target, type);
    return handle;
  }

  @override
  void destroyBody(int bodyHandle) {
    _bodies.remove(bodyHandle);
    _colliders.removeWhere((_, c) => c.bodyHandle == bodyHandle);
  }

  @override
  void setBodyKind(int bodyHandle, BodyType type) {
    if (type == BodyType.dynamic_) {
      throw UnsupportedError('BasicSimulation does not simulate dynamics.');
    }
    _bodies[bodyHandle]?.type = type;
  }

  @override
  int createAnchorBody() =>
      createBody(target: SimplePoseTarget(), type: BodyType.fixed);

  @override
  void destroyAnchorBody(int bodyHandle) => destroyBody(bodyHandle);

  @override
  (Vector3, Quaternion) readBodyPose(int bodyHandle) {
    final body = _bodies[bodyHandle]!;
    return (
      body.target.worldTranslation.clone(),
      body.target.worldRotation.clone(),
    );
  }

  @override
  Vector3 readBodyLinearVelocity(int bodyHandle) =>
      _bodies[bodyHandle]!.linearVelocity.clone();

  @override
  Vector3 readBodyAngularVelocity(int bodyHandle) =>
      _bodies[bodyHandle]!.angularVelocity.clone();

  @override
  void setBodyLinearVelocity(int bodyHandle, Vector3 velocity) =>
      _bodies[bodyHandle]?.linearVelocity.setFrom(velocity);

  @override
  void setBodyAngularVelocity(int bodyHandle, Vector3 velocity) =>
      _bodies[bodyHandle]?.angularVelocity.setFrom(velocity);

  // Recorded for readers; no solver consumes them.
  @override
  void setBodyLinearDamping(int bodyHandle, double damping) {}

  @override
  void setBodyAngularDamping(int bodyHandle, double damping) {}

  @override
  void setBodyGravityScale(int bodyHandle, double scale) {}

  @override
  void setBodyCcdEnabled(int bodyHandle, bool enabled) {}

  @override
  void setBodyAdditionalMass(int bodyHandle, double mass) {}

  @override
  void setBodyAxisLocks(int bodyHandle, Vector3 linear, Vector3 angular) {}

  @override
  void setBodyKinematicTargetPose(
    int bodyHandle,
    Vector3 translation,
    Quaternion rotation,
  ) {
    // Kinematic owners already hold the pose target; nothing to push.
  }

  @override
  void applyForce(int bodyHandle, Vector3 force, {Vector3? atWorldPoint}) {}

  @override
  void applyImpulse(int bodyHandle, Vector3 impulse, {Vector3? atWorldPoint}) {}

  @override
  void applyTorque(int bodyHandle, Vector3 torque) {}

  @override
  void applyAngularImpulse(int bodyHandle, Vector3 impulse) {}

  @override
  bool isBodySleeping(int bodyHandle) => false;

  @override
  void wakeBody(int bodyHandle) {}

  @override
  void sleepBody(int bodyHandle) {}

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
    final handle = _nextHandle++;
    _colliders[handle] = _BasicCollider(
      bodyHandle,
      shape,
      isTrigger,
      collisionLayer,
      collisionMask,
      localPose ?? Matrix4.identity(),
    );
    return [handle];
  }

  @override
  void destroyCollider(int colliderHandle) {
    _colliders.remove(colliderHandle);
    _prevTriggerPairs.removeWhere(
      (p) => p.a == colliderHandle || p.b == colliderHandle,
    );
  }

  @override
  void setColliderMaterial(int colliderHandle, PhysicsMaterial material) {}

  @override
  void setColliderFilter(int colliderHandle, int layer, int mask) {
    final collider = _colliders[colliderHandle];
    if (collider == null) return;
    collider
      ..layer = layer
      ..mask = mask;
  }

  // --- Joints ---

  @override
  bool get supportsJoints => false;

  @override
  int createJoint(JointDesc desc) =>
      throw UnsupportedError('BasicSimulation has no joints.');

  @override
  void updateJoint(int jointHandle, JointDesc desc) =>
      throw UnsupportedError('BasicSimulation has no joints.');

  @override
  void destroyJoint(int jointHandle) {}

  // --- Queries ---

  bool _passesFilters(
    _BasicCollider collider, {
    required int layerMask,
    required bool includeFixed,
    required bool includeKinematic,
    required bool includeTriggers,
  }) {
    if (collider.isTrigger && !includeTriggers) return false;
    if ((collider.layer & layerMask) == 0) return false;
    final type = _bodies[collider.bodyHandle]?.type ?? BodyType.fixed;
    if (type == BodyType.kinematic && !includeKinematic) return false;
    if (type == BodyType.fixed && !includeFixed) return false;
    return true;
  }

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
    SimRaycastHit? best;
    _colliders.forEach((handle, collider) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        return;
      }
      final hit = rayHitsShape(
        ray,
        collider.shape,
        _colliderWorldPose(collider),
        maxDistance,
      );
      if (hit == null) return;
      if (best == null || hit.distance < best!.distance) {
        best = SimRaycastHit(
          colliderHandle: handle,
          worldPoint: hit.worldPoint,
          worldNormal: hit.worldNormal,
          distance: hit.distance,
        );
      }
    });
    return best;
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
    final hits = <SimRaycastHit>[];
    _colliders.forEach((handle, collider) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        return;
      }
      final hit = rayHitsShape(
        ray,
        collider.shape,
        _colliderWorldPose(collider),
        maxDistance,
      );
      if (hit == null) return;
      hits.add(
        SimRaycastHit(
          colliderHandle: handle,
          worldPoint: hit.worldPoint,
          worldNormal: hit.worldNormal,
          distance: hit.distance,
        ),
      );
    });
    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
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
    final out = <SimOverlapHit>[];
    _colliders.forEach((handle, collider) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        return;
      }
      final aabb = shapeWorldAabb(collider.shape, _colliderWorldPose(collider));
      if (!sphereOverlapsAabb(center, radius, aabb)) return;
      out.add(SimOverlapHit(colliderHandle: handle));
    });
    return out;
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
    // Conservative AABB-of-OBB approximation.
    // TODO(exact-obb-overlap): SAT-test the probe OBB against each
    // collider for exact results; the current AABB-of-OBB produces
    // false positives at corners when the probe is rotated.
    final probePose = Matrix4.compose(center, rotation, Vector3(1, 1, 1));
    final probeAabb = shapeWorldAabb(
      BoxShape(halfExtents: halfExtents),
      probePose,
    );
    final out = <SimOverlapHit>[];
    _colliders.forEach((handle, collider) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        return;
      }
      final aabb = shapeWorldAabb(collider.shape, _colliderWorldPose(collider));
      if (!_aabbOverlap(probeAabb, aabb)) return;
      out.add(SimOverlapHit(colliderHandle: handle));
    });
    return out;
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
    if (shape is! SphereShape) {
      throw UnsupportedError(
        'BasicSimulation.shapeCast currently supports SphereShape only.',
      );
    }
    // Sphere cast = raycast against each collider's AABB inflated by the
    // sphere radius; closest hit wins.
    final origin = from.getTranslation();
    final ray = Ray.originDirection(origin, direction);
    SimShapeCastHit? best;
    _colliders.forEach((handle, collider) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        return;
      }
      final aabb = shapeWorldAabb(collider.shape, _colliderWorldPose(collider));
      final inflated = Aabb3.minMax(
        aabb.min - Vector3.all(shape.radius),
        aabb.max + Vector3.all(shape.radius),
      );
      final hit = aabbRaycast(ray, inflated, distance);
      if (hit == null) return;
      if (best == null || hit.distance < best!.distance) {
        best = SimShapeCastHit(
          colliderHandle: handle,
          worldPoint: hit.worldPoint,
          worldNormal: hit.worldNormal,
          distance: hit.distance,
        );
      }
    });
    return best;
  }

  bool _aabbOverlap(Aabb3 a, Aabb3 b) =>
      a.min.x <= b.max.x &&
      a.max.x >= b.min.x &&
      a.min.y <= b.max.y &&
      a.max.y >= b.min.y &&
      a.min.z <= b.max.z &&
      a.max.z >= b.min.z;

  // --- Stepping ---

  @override
  void step(double fixedDt) {
    _stepTriggers();
  }

  @override
  void interpolatePoses(double alpha) {
    // No dynamics, no poses to interpolate. Fixed and kinematic bodies
    // move only when their owner moves the pose target.
  }

  void _stepTriggers() {
    if (_colliders.isEmpty) return;

    final triggers = <int, _BasicCollider>{};
    final solids = <int, _BasicCollider>{};
    _colliders.forEach((handle, collider) {
      (collider.isTrigger ? triggers : solids)[handle] = collider;
    });
    if (triggers.isEmpty) {
      _prevTriggerPairs.clear();
      return;
    }

    final newPairs = <_Pair>{};
    final triggerAabbs = <int, Aabb3>{
      for (final MapEntry(key: handle, value: t) in triggers.entries)
        handle: shapeWorldAabb(t.shape, _colliderWorldPose(t)),
    };
    triggers.forEach((triggerHandle, trigger) {
      final aTrigger = triggerAabbs[triggerHandle]!;
      solids.forEach((otherHandle, other) {
        if (!_layerMatch(trigger, other)) return;
        final aOther = shapeWorldAabb(other.shape, _colliderWorldPose(other));
        if (!_aabbOverlap(aTrigger, aOther)) return;
        if (!shapesOverlap(
          trigger.shape,
          _colliderWorldPose(trigger),
          other.shape,
          _colliderWorldPose(other),
        )) {
          return;
        }
        newPairs.add(_Pair(triggerHandle, otherHandle));
      });
    });

    for (final pair in newPairs) {
      if (_prevTriggerPairs.contains(pair)) continue;
      _events.add(
        SimTriggerEntered(colliderHandleA: pair.a, colliderHandleB: pair.b),
      );
    }
    for (final pair in _prevTriggerPairs) {
      if (newPairs.contains(pair)) continue;
      _events.add(
        SimTriggerExited(colliderHandleA: pair.a, colliderHandleB: pair.b),
      );
    }
    _prevTriggerPairs
      ..clear()
      ..addAll(newPairs);
  }

  bool _layerMatch(_BasicCollider a, _BasicCollider b) =>
      (a.layer & b.mask) != 0 && (b.layer & a.mask) != 0;

  @override
  void dispose() {
    _events.close();
    _bodies.clear();
    _colliders.clear();
    _prevTriggerPairs.clear();
  }
}
