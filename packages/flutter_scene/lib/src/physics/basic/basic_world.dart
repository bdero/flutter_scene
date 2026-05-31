import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/physics/basic/basic_collider.dart';
import 'package:flutter_scene/src/physics/basic/basic_kinematic_body.dart';
import 'package:flutter_scene/src/physics/basic/basic_queries.dart';
import 'package:flutter_scene/src/physics/events.dart';
import 'package:flutter_scene/src/physics/physics_world.dart';
import 'package:flutter_scene/src/physics/queries.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:flutter_scene/src/physics/shape.dart';
import 'package:vector_math/vector_math.dart';

/// Pure-Dart [PhysicsWorld] suitable for picking, area triggers, and
/// kinematic-only gameplay.
///
/// Supports scene queries (raycast, raycastAll, overlapSphere,
/// overlapBox, shapeCast) and trigger events. Does not simulate
/// dynamics (no constraint solver, no contact response). Construct
/// [BasicCollider]s for geometry the queries should see, and attach
/// [BasicKinematicBody]s to nodes you intend to move under your own
/// control. For full rigid-body simulation, depend on a backend
/// package with a solver.
class BasicPhysicsWorld extends PhysicsWorld {
  BasicPhysicsWorld({Vector3? gravity}) {
    if (gravity != null) this.gravity = gravity;
  }

  @override
  String get backendName => 'basic';

  final List<BasicCollider> _colliders = [];
  final List<BasicKinematicBody> _bodies = [];

  /// Trigger overlap pairs from the previous step, used to compute the
  /// per-step entered/exited diff. Order within a pair is normalized by
  /// identity hash so each unordered pair has one representation.
  final Set<_Pair> _prevTriggerPairs = {};

  final StreamController<CollisionEvent> _events =
      StreamController<CollisionEvent>.broadcast();

  @override
  Stream<CollisionEvent> get collisions => _events.stream;

  @internal
  void registerCollider(BasicCollider collider) => _colliders.add(collider);

  @internal
  void unregisterCollider(BasicCollider collider) {
    _colliders.remove(collider);
    _prevTriggerPairs.removeWhere(
      (p) => identical(p.a, collider) || identical(p.b, collider),
    );
  }

  @internal
  void registerBody(BasicKinematicBody body) => _bodies.add(body);

  @internal
  void unregisterBody(BasicKinematicBody body) => _bodies.remove(body);

  @override
  void onUnmount() {
    _events.close();
    _colliders.clear();
    _bodies.clear();
    _prevTriggerPairs.clear();
  }

  // --- Substepping driver hooks ---

  @override
  void step(double fixedDt) {
    _stepTriggers();
  }

  @override
  void interpolateTransforms(double alpha) {
    // No dynamics, no transforms to interpolate. Static and kinematic
    // bodies move only when the user moves the owning node.
  }

  void _stepTriggers() {
    if (_colliders.isEmpty) return;

    final triggers = <BasicCollider>[];
    final solids = <BasicCollider>[];
    for (final c in _colliders) {
      (c.isTrigger ? triggers : solids).add(c);
    }
    if (triggers.isEmpty) {
      // No triggers means nothing to emit; just discard the old set.
      _prevTriggerPairs.clear();
      return;
    }

    final newPairs = <_Pair>{};
    // Cache trigger AABBs once per step for the broad-phase prune.
    final triggerAabbs = <BasicCollider, Aabb3>{
      for (final t in triggers) t: shapeWorldAabb(t.shape, t.worldPose),
    };
    for (final trigger in triggers) {
      final aTrigger = triggerAabbs[trigger]!;
      for (final other in solids) {
        if (!_layerMatch(trigger, other)) continue;
        // Broad-phase: prune by AABB first.
        final aOther = shapeWorldAabb(other.shape, other.worldPose);
        if (!_aabbOverlap(aTrigger, aOther)) continue;
        // Narrow-phase: exact test for sphere/box pairs, AABB fallback
        // for the rest.
        if (!shapesOverlap(
          trigger.shape,
          trigger.worldPose,
          other.shape,
          other.worldPose,
        )) {
          continue;
        }
        final pair = _Pair(trigger, other);
        newPairs.add(pair);
      }
    }

    for (final pair in newPairs) {
      if (_prevTriggerPairs.contains(pair)) continue;
      _events.add(
        TriggerEntered(
          nodeA: pair.a.node,
          nodeB: pair.b.node,
          colliderA: pair.a,
          colliderB: pair.b,
        ),
      );
    }
    for (final pair in _prevTriggerPairs) {
      if (newPairs.contains(pair)) continue;
      _events.add(
        TriggerExited(
          nodeA: pair.a.node,
          nodeB: pair.b.node,
          colliderA: pair.a,
          colliderB: pair.b,
        ),
      );
    }

    _prevTriggerPairs
      ..clear()
      ..addAll(newPairs);
  }

  // --- Scene queries ---

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
    RaycastHit? best;
    for (final collider in _colliders) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        continue;
      }
      final hit = rayHitsShape(
        ray,
        collider.shape,
        collider.worldPose,
        maxDistance,
      );
      if (hit == null) continue;
      if (best == null || hit.distance < best.distance) {
        best = _wrapHit(collider, hit);
      }
    }
    return best;
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
    final hits = <RaycastHit>[];
    for (final collider in _colliders) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        continue;
      }
      final hit = rayHitsShape(
        ray,
        collider.shape,
        collider.worldPose,
        maxDistance,
      );
      if (hit == null) continue;
      hits.add(_wrapHit(collider, hit));
    }
    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
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
    final out = <OverlapHit>[];
    for (final collider in _colliders) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        continue;
      }
      final aabb = shapeWorldAabb(collider.shape, collider.worldPose);
      if (!sphereOverlapsAabb(center, radius, aabb)) continue;
      out.add(OverlapHit(node: collider.node, collider: collider));
    }
    return out;
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
    // Conservative AABB-of-OBB approximation. Adequate for Stage 2; a
    // future revision could SAT-test the OBB against each collider.
    final r = Matrix4.compose(center, rotation, Vector3(1, 1, 1));
    final probeAabb = shapeWorldAabb(BoxShape(halfExtents: halfExtents), r);
    final out = <OverlapHit>[];
    for (final collider in _colliders) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        continue;
      }
      final aabb = shapeWorldAabb(collider.shape, collider.worldPose);
      if (!_aabbOverlap(probeAabb, aabb)) continue;
      out.add(OverlapHit(node: collider.node, collider: collider));
    }
    return out;
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
    if (shape is! SphereShape) {
      throw UnsupportedError(
        'BasicPhysicsWorld.shapeCast currently supports SphereShape only.',
      );
    }
    // Sphere cast = expand each collider's AABB by the sphere radius
    // and raycast from `from`'s translation along `direction` against
    // the inflated volumes. Returns the closest hit collider.
    final origin = from.getTranslation();
    final ray = Ray.originDirection(origin, direction);
    ShapeCastHit? best;
    for (final collider in _colliders) {
      if (!_passesFilters(
        collider,
        layerMask: layerMask,
        includeFixed: includeFixed,
        includeKinematic: includeKinematic,
        includeTriggers: includeTriggers,
      )) {
        continue;
      }
      final aabb = shapeWorldAabb(collider.shape, collider.worldPose);
      final inflated = Aabb3.minMax(
        aabb.min - Vector3.all(shape.radius),
        aabb.max + Vector3.all(shape.radius),
      );
      final hit = _aabbRaycast(ray, inflated, distance);
      if (hit == null) continue;
      if (best == null || hit.distance < best.distance) {
        best = ShapeCastHit(
          node: collider.node,
          collider: collider,
          worldPoint: hit.worldPoint,
          worldNormal: hit.worldNormal,
          distance: hit.distance,
        );
      }
    }
    return best;
  }

  // --- Helpers ---

  RaycastHit _wrapHit(BasicCollider collider, RayShapeHit hit) => RaycastHit(
    node: collider.node,
    collider: collider,
    worldPoint: hit.worldPoint,
    worldNormal: hit.worldNormal,
    distance: hit.distance,
  );

  bool _passesFilters(
    BasicCollider collider, {
    required int layerMask,
    required bool includeFixed,
    required bool includeKinematic,
    required bool includeTriggers,
  }) {
    if (collider.isTrigger && !includeTriggers) return false;
    if ((collider.collisionLayer & layerMask) == 0) return false;
    final body = collider.node.getComponent<RigidBody>();
    if (body == null) {
      if (!includeFixed) return false;
    } else if (body.type == BodyType.kinematic) {
      if (!includeKinematic) return false;
    } else if (body.type == BodyType.fixed) {
      if (!includeFixed) return false;
    }
    return true;
  }

  bool _layerMatch(BasicCollider a, BasicCollider b) =>
      (a.collisionLayer & b.collisionMask) != 0 &&
      (b.collisionLayer & a.collisionMask) != 0;

  bool _aabbOverlap(Aabb3 a, Aabb3 b) =>
      a.min.x <= b.max.x &&
      a.max.x >= b.min.x &&
      a.min.y <= b.max.y &&
      a.max.y >= b.min.y &&
      a.min.z <= b.max.z &&
      a.max.z >= b.min.z;

  // Inline AABB raycast used by shapeCast; kept here to avoid widening
  // basic_queries.dart's public surface.
  RayShapeHit? _aabbRaycast(Ray ray, Aabb3 box, double maxDistance) {
    final dir = ray.direction.normalized();
    var tmin = -double.infinity;
    var tmax = double.infinity;
    var hitAxis = -1;
    var hitSign = 1.0;
    for (var axis = 0; axis < 3; axis++) {
      final o = ray.origin[axis];
      final d = dir[axis];
      final lo = box.min[axis];
      final hi = box.max[axis];
      if (d.abs() < 1e-9) {
        if (o < lo || o > hi) return null;
        continue;
      }
      var t1 = (lo - o) / d;
      var t2 = (hi - o) / d;
      var nearSign = -1.0;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
        nearSign = 1.0;
      }
      if (t1 > tmin) {
        tmin = t1;
        hitAxis = axis;
        hitSign = nearSign;
      }
      if (t2 < tmax) tmax = t2;
      if (tmin > tmax || tmax < 0) return null;
    }
    final t = tmin >= 0 ? tmin : tmax;
    if (t < 0 || t > maxDistance) return null;
    final hitPoint = ray.origin + dir.scaled(t);
    final normal = Vector3.zero();
    if (hitAxis >= 0) normal[hitAxis] = hitSign;
    return RayShapeHit(t, hitPoint, normal);
  }
}

class _Pair {
  _Pair(BasicCollider x, BasicCollider y)
    : a = identityHashCode(x) <= identityHashCode(y) ? x : y,
      b = identityHashCode(x) <= identityHashCode(y) ? y : x;

  final BasicCollider a;
  final BasicCollider b;

  @override
  bool operator ==(Object other) =>
      other is _Pair && identical(a, other.a) && identical(b, other.b);

  @override
  int get hashCode => Object.hash(identityHashCode(a), identityHashCode(b));
}
