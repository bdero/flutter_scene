import 'dart:async';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'aabb_bvh.dart';
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
/// {@category Physics}
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

  // --- Broad phase ---
  //
  // A hierarchy over the colliders' world AABBs, so a query runs the exact
  // shape test only on what it can actually reach. Bodies here move whenever
  // their owner moves the pose target, with no notification, so the boxes are
  // re-read on every query; only the topology is cached, and it is refit
  // (O(n), no sort, no allocation) rather than rebuilt unless the collider
  // set itself changed.
  final List<_BasicCollider> _phaseColliders = [];
  final List<int> _phaseHandles = [];
  final List<Matrix4> _phasePoses = [];
  Float32List _phaseBoxes = Float32List(0);
  AabbBvh? _phaseBvh;
  int _colliderSetVersion = 0;
  int _phaseVersion = -1;

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

  /// Re-reads every collider's world pose and box, then refreshes the
  /// hierarchy: a refit while the collider set is unchanged, a rebuild
  /// otherwise.
  ///
  /// Returns the number of live colliders. The poses it computes are kept in
  /// [_phasePoses] so the query that follows does not compose them again.
  int _refreshBroadPhase() {
    final count = _colliders.length;
    final rebuild = _phaseVersion != _colliderSetVersion;
    if (rebuild) {
      _phaseColliders.clear();
      _phaseHandles.clear();
      _phasePoses.clear();
      _colliders.forEach((handle, collider) {
        _phaseHandles.add(handle);
        _phaseColliders.add(collider);
        _phasePoses.add(Matrix4.zero());
      });
      if (_phaseBoxes.length < count * 6) {
        _phaseBoxes = Float32List(count * 6);
      }
    }
    for (var i = 0; i < count; i++) {
      final pose = _colliderWorldPose(_phaseColliders[i]);
      _phasePoses[i].setFrom(pose);
      final box = shapeWorldAabb(_phaseColliders[i].shape, pose);
      final o = i * 6;
      _phaseBoxes[o] = box.min.x;
      _phaseBoxes[o + 1] = box.min.y;
      _phaseBoxes[o + 2] = box.min.z;
      _phaseBoxes[o + 3] = box.max.x;
      _phaseBoxes[o + 4] = box.max.y;
      _phaseBoxes[o + 5] = box.max.z;
    }
    if (rebuild) {
      _phaseBvh = count == 0 ? null : AabbBvh.build(_phaseBoxes, count);
      _phaseVersion = _colliderSetVersion;
    } else {
      _phaseBvh?.refit(_phaseBoxes);
    }
    return count;
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
    _colliderSetVersion++;
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
    _colliderSetVersion++;
    return [handle];
  }

  @override
  void destroyCollider(int colliderHandle) {
    _colliders.remove(colliderHandle);
    _colliderSetVersion++;
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
    _refreshBroadPhase();
    final bvh = _phaseBvh;
    if (bvh == null) return null;
    final direction = ray.direction.normalized();
    SimRaycastHit? best;
    bvh.queryRay(
      ray.origin.x,
      ray.origin.y,
      ray.origin.z,
      direction.x,
      direction.y,
      direction.z,
      maxDistance,
      (i) {
        final collider = _phaseColliders[i];
        if (!_passesFilters(
          collider,
          layerMask: layerMask,
          includeFixed: includeFixed,
          includeKinematic: includeKinematic,
          includeTriggers: includeTriggers,
        )) {
          return;
        }
        // Candidates arrive unordered, so the exact test still runs against
        // the caller's full distance; the hierarchy has already rejected
        // everything the ray cannot reach at all.
        final hit = rayHitsShape(
          ray,
          collider.shape,
          _phasePoses[i],
          best == null ? maxDistance : best!.distance,
        );
        if (hit == null) return;
        if (best == null || hit.distance < best!.distance) {
          best = SimRaycastHit(
            colliderHandle: _phaseHandles[i],
            worldPoint: hit.worldPoint,
            worldNormal: hit.worldNormal,
            distance: hit.distance,
          );
        }
      },
    );
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
    _refreshBroadPhase();
    final bvh = _phaseBvh;
    if (bvh == null) return hits;
    final direction = ray.direction.normalized();
    bvh.queryRay(
      ray.origin.x,
      ray.origin.y,
      ray.origin.z,
      direction.x,
      direction.y,
      direction.z,
      maxDistance,
      (i) {
        final collider = _phaseColliders[i];
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
          _phasePoses[i],
          maxDistance,
        );
        if (hit == null) return;
        hits.add(
          SimRaycastHit(
            colliderHandle: _phaseHandles[i],
            worldPoint: hit.worldPoint,
            worldNormal: hit.worldNormal,
            distance: hit.distance,
          ),
        );
      },
    );
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
    _refreshBroadPhase();
    final bvh = _phaseBvh;
    if (bvh == null) return out;
    final boxes = _phaseBoxes;
    bvh.queryAabb(
      center.x - radius,
      center.y - radius,
      center.z - radius,
      center.x + radius,
      center.y + radius,
      center.z + radius,
      (i) {
        if (!_passesFilters(
          _phaseColliders[i],
          layerMask: layerMask,
          includeFixed: includeFixed,
          includeKinematic: includeKinematic,
          includeTriggers: includeTriggers,
        )) {
          return;
        }
        // The hierarchy rejected on the probe's own AABB; the exact
        // sphere-vs-box test still has to run on what survives. The box is
        // the one [_refreshBroadPhase] just computed, so no shape scan.
        final o = i * 6;
        if (!sphereOverlapsAabb(
          center,
          radius,
          Aabb3.minMax(
            Vector3(boxes[o], boxes[o + 1], boxes[o + 2]),
            Vector3(boxes[o + 3], boxes[o + 4], boxes[o + 5]),
          ),
        )) {
          return;
        }
        out.add(SimOverlapHit(colliderHandle: _phaseHandles[i]));
      },
    );
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
    // The hierarchy is descended with the probe's enclosing AABB, which is
    // only a broad-phase reject; every survivor then gets the exact
    // separating-axis test against the real oriented probe, so a rotated
    // probe no longer reports the colliders that only touched the corners of
    // its bounding box.
    final probePose = Matrix4.compose(center, rotation, Vector3(1, 1, 1));
    final probeAabb = shapeWorldAabb(
      BoxShape(halfExtents: halfExtents),
      probePose,
    );
    final out = <SimOverlapHit>[];
    _refreshBroadPhase();
    final bvh = _phaseBvh;
    if (bvh == null) return out;
    bvh.queryAabb(
      probeAabb.min.x,
      probeAabb.min.y,
      probeAabb.min.z,
      probeAabb.max.x,
      probeAabb.max.y,
      probeAabb.max.z,
      (i) {
        final collider = _phaseColliders[i];
        if (!_passesFilters(
          collider,
          layerMask: layerMask,
          includeFixed: includeFixed,
          includeKinematic: includeKinematic,
          includeTriggers: includeTriggers,
        )) {
          return;
        }
        if (!obbOverlapsShape(
          probePose,
          halfExtents,
          collider.shape,
          _phasePoses[i],
        )) {
          return;
        }
        out.add(SimOverlapHit(colliderHandle: _phaseHandles[i]));
      },
    );
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
    // sphere radius; closest hit wins. The hierarchy is descended with the
    // ray inflated the same way, by widening the search distance and testing
    // the inflated box per candidate.
    final origin = from.getTranslation();
    final ray = Ray.originDirection(origin, direction);
    _refreshBroadPhase();
    final bvh = _phaseBvh;
    if (bvh == null) return null;
    final unit = direction.normalized();
    final boxes = _phaseBoxes;
    final radius = shape.radius;
    SimShapeCastHit? best;
    // Nodes are tested against the un-inflated ray, so grow the traversal by
    // the sphere radius on each side: a collider whose inflated box the ray
    // enters has its own box within radius of the ray's line.
    bvh.queryRay(
      origin.x - unit.x * radius,
      origin.y - unit.y * radius,
      origin.z - unit.z * radius,
      unit.x,
      unit.y,
      unit.z,
      distance + radius * 2,
      (i) {
        if (!_passesFilters(
          _phaseColliders[i],
          layerMask: layerMask,
          includeFixed: includeFixed,
          includeKinematic: includeKinematic,
          includeTriggers: includeTriggers,
        )) {
          return;
        }
        final o = i * 6;
        final inflated = Aabb3.minMax(
          Vector3(boxes[o] - radius, boxes[o + 1] - radius, boxes[o + 2] - radius),
          Vector3(boxes[o + 3] + radius, boxes[o + 4] + radius, boxes[o + 5] + radius),
        );
        final hit = aabbRaycast(ray, inflated, distance);
        if (hit == null) return;
        if (best == null || hit.distance < best!.distance) {
          best = SimShapeCastHit(
            colliderHandle: _phaseHandles[i],
            worldPoint: hit.worldPoint,
            worldNormal: hit.worldNormal,
            distance: hit.distance,
          );
        }
      },
    );
    return best;
  }

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
    final count = _refreshBroadPhase();
    final bvh = _phaseBvh;
    if (bvh == null) return;

    var anyTrigger = false;
    for (var i = 0; i < count; i++) {
      if (_phaseColliders[i].isTrigger) {
        anyTrigger = true;
        break;
      }
    }
    if (!anyTrigger) {
      _prevTriggerPairs.clear();
      return;
    }

    // Each trigger asks the hierarchy for the colliders near it rather than
    // sweeping the whole world, and the world poses and boxes computed by the
    // refresh above are reused instead of being composed again per pair.
    final newPairs = <_Pair>{};
    final boxes = _phaseBoxes;
    for (var t = 0; t < count; t++) {
      final trigger = _phaseColliders[t];
      if (!trigger.isTrigger) continue;
      final o = t * 6;
      bvh.queryAabb(
        boxes[o],
        boxes[o + 1],
        boxes[o + 2],
        boxes[o + 3],
        boxes[o + 4],
        boxes[o + 5],
        (i) {
          final other = _phaseColliders[i];
          if (other.isTrigger) return;
          if (!_layerMatch(trigger, other)) return;
          if (!shapesOverlap(
            trigger.shape,
            _phasePoses[t],
            other.shape,
            _phasePoses[i],
          )) {
            return;
          }
          newPairs.add(_Pair(_phaseHandles[t], _phaseHandles[i]));
        },
      );
    }

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
    _colliderSetVersion++;
    _phaseColliders.clear();
    _phaseHandles.clear();
    _phasePoses.clear();
    _phaseBvh = null;
    _prevTriggerPairs.clear();
  }
}
