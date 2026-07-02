import 'dart:async';
import 'dart:math' as math;

import 'package:box3d/box3d.dart' as b3;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'box3d_collider.dart';

/// [PhysicsWorld] backed by the box3d engine.
///
/// Wraps a box3d [b3.Box3dWorld]. [step] advances the simulation and
/// captures each dynamic body's pose; [interpolateTransforms] lerps and
/// slerps those poses between steps and writes them back to the owning
/// [Node]. Scene queries forward to box3d and resolve hits to the owning
/// [Box3dCollider]. Contact and trigger lifecycle events are emitted on
/// [collisions] after each step.
///
/// Call [Box3dPhysicsWorld.ensureInitialized] once during startup before
/// constructing a world (a no-op on native platforms).
class Box3dPhysicsWorld extends PhysicsWorld {
  Box3dPhysicsWorld({Vector3? gravity})
    : _world = b3.Box3dWorld(gravity: gravity) {
    if (gravity != null) this.gravity = gravity;
  }

  /// Prepares the box3d backend so a [Box3dPhysicsWorld] can be
  /// constructed. Returns immediately on native targets; on the web it
  /// loads the WebAssembly module. Await it once during startup.
  static Future<void> ensureInitialized() => b3.Box3d.ensureInitialized();

  final b3.Box3dWorld _world;

  /// The underlying box3d world. For use by [Box3dRigidBody] and
  /// [Box3dCollider] to create bodies and shapes.
  b3.Box3dWorld get nativeWorld => _world;

  // Tracks each registered body so interpolateTransforms can write back
  // dynamic poses.
  final Map<int, _BodyRecord> _bodies = {};

  // Maps a box3d shape handle to the owning collider, for resolving query
  // hits and collision events back to components.
  final Map<int, Box3dCollider> _collidersByHandle = {};

  double _interpolationAlpha = 0.0;

  /// The residual fraction in `[0, 1]` of the last [interpolateTransforms]:
  /// how far the renderer is between the previous and current fixed steps.
  double get interpolationAlpha => _interpolationAlpha;

  @override
  String get backendName => 'box3d';

  final StreamController<CollisionEvent> _events =
      StreamController<CollisionEvent>.broadcast();

  @override
  Stream<CollisionEvent> get collisions => _events.stream;

  /// Registers a body created on [nativeWorld] so its dynamic pose is
  /// interpolated. Called from [Box3dRigidBody.onMount].
  void registerBody(b3.Box3dBody body, Node node, BodyType type) {
    _bodies[body.handle] = _BodyRecord(body, node, type);
  }

  /// Stops tracking a body. Called from [Box3dRigidBody.onUnmount].
  void unregisterBody(int handle) => _bodies.remove(handle);

  void rememberCollider(int handle, Box3dCollider collider) =>
      _collidersByHandle[handle] = collider;

  void forgetCollider(int handle) => _collidersByHandle.remove(handle);

  @override
  void onUnmount() {
    _events.close();
    _world.dispose();
  }

  @override
  void step(double fixedDt) {
    final g = gravity;
    _world.gravity = g;
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
  void interpolateTransforms(double alpha) {
    _interpolationAlpha = alpha;
    final t = Vector3.zero();
    for (final record in _bodies.values) {
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

  // Drains box3d's per-step events and re-emits them as flutter_scene
  // collision events, resolving shape handles to colliders.
  void _drainEvents() {
    if (!_events.hasListener) return;
    final events = _world.drainEvents();
    for (final e in events.contactBegan) {
      final a = _collidersByHandle[e.shapeA];
      final b = _collidersByHandle[e.shapeB];
      if (a == null || b == null) continue;
      _events.add(
        CollisionBegan(
          nodeA: a.node,
          nodeB: b.node,
          colliderA: a,
          colliderB: b,
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
      final a = _collidersByHandle[e.shapeA];
      final b = _collidersByHandle[e.shapeB];
      if (a == null || b == null) continue;
      _events.add(
        CollisionEnded(
          nodeA: a.node,
          nodeB: b.node,
          colliderA: a,
          colliderB: b,
        ),
      );
    }
    for (final e in events.sensorBegan) {
      final sensor = _collidersByHandle[e.sensorShape];
      final visitor = _collidersByHandle[e.visitorShape];
      if (sensor == null || visitor == null) continue;
      _events.add(
        TriggerEntered(
          nodeA: sensor.node,
          nodeB: visitor.node,
          colliderA: sensor,
          colliderB: visitor,
        ),
      );
    }
    for (final e in events.sensorEnded) {
      final sensor = _collidersByHandle[e.sensorShape];
      final visitor = _collidersByHandle[e.visitorShape];
      if (sensor == null || visitor == null) continue;
      _events.add(
        TriggerExited(
          nodeA: sensor.node,
          nodeB: visitor.node,
          colliderA: sensor,
          colliderB: visitor,
        ),
      );
    }
  }

  // --- Scene queries ---------------------------------------------------------
  //
  // box3d's category/mask filter matches flutter_scene's layer/mask
  // semantics. The include* body-type flags are not part of box3d's query
  // filter; TODO(box3d-query-typefilter) apply them by post-filtering hits
  // on the owning body type once bodies expose it here.

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
    final hit = _world.raycast(
      ray.origin,
      ray.direction,
      maxDistance: maxDistance.isFinite ? maxDistance : 1e6,
      mask: layerMask,
    );
    return hit == null ? null : _raycastHit(hit);
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
    final hits = _world.raycastAll(
      ray.origin,
      ray.direction,
      maxDistance: maxDistance.isFinite ? maxDistance : 1e6,
      mask: layerMask,
    );
    return [
      for (final h in hits)
        if (_raycastHit(h) case final resolved?) resolved,
    ];
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
  }) => _overlapHits(_world.overlapSphere(center, radius, mask: layerMask));

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
  }) => _overlapHits(
    _world.overlapBox(center, halfExtents, rotation: rotation, mask: layerMask),
  );

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
    final collider = _collidersByHandle[hit.shape];
    if (collider == null) return null;
    return ShapeCastHit(
      node: collider.node,
      collider: collider,
      worldPoint: hit.point,
      worldNormal: hit.normal,
      distance: hit.distance,
    );
  }

  RaycastHit? _raycastHit(b3.Box3dRayHit hit) {
    final collider = _collidersByHandle[hit.shape];
    if (collider == null) return null;
    return RaycastHit(
      node: collider.node,
      collider: collider,
      worldPoint: hit.point,
      worldNormal: hit.normal,
      distance: hit.distance,
    );
  }

  List<OverlapHit> _overlapHits(List<int> handles) => [
    for (final handle in handles)
      if (_collidersByHandle[handle] case final collider?)
        OverlapHit(node: collider.node, collider: collider),
  ];
}

/// Walks [start] and its ancestors for a [Box3dPhysicsWorld] component.
Box3dPhysicsWorld? findAncestorBox3dWorld(Node start) {
  Node? current = start;
  while (current != null) {
    final world = current.getComponent<Box3dPhysicsWorld>();
    if (world != null) return world;
    current = current.parent;
  }
  return null;
}

class _BodyRecord {
  _BodyRecord(this.body, this.node, this.type)
    : prevTranslation = body.position,
      currTranslation = body.position,
      prevRotation = body.rotation,
      currRotation = body.rotation;

  final b3.Box3dBody body;
  final Node node;
  final BodyType type;
  final Vector3 prevTranslation;
  final Vector3 currTranslation;
  final Quaternion prevRotation;
  final Quaternion currRotation;
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
