import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/collider.dart';
import 'package:flutter_scene/src/physics/events.dart';
import 'package:flutter_scene/src/physics/queries.dart';
import 'package:scene/scene.dart' as sim;
import 'package:vector_math/vector_math.dart';

/// Adapts a [Node]'s world transform to the simulation's pose seam.
///
/// Scale is not simulated; written poses compose with unit scale and the
/// node's parent chain absorbs the difference through the global setter.
final class NodePoseTarget implements sim.PoseTarget {
  NodePoseTarget(this.node);

  final Node node;

  @override
  Vector3 get worldTranslation => node.globalTransform.getTranslation();

  @override
  Quaternion get worldRotation =>
      Quaternion.fromRotation(node.globalTransform.getRotation());

  @override
  void setWorldPose(Vector3 translation, Quaternion rotation) {
    node.globalTransform = Matrix4.compose(
      translation,
      rotation,
      Vector3(1, 1, 1),
    );
  }
}

/// The simulation world for a subtree of the scene graph.
///
/// Wraps any [sim.PhysicsSimulation] backend, `BasicSimulation` for
/// queries and triggers, or a solver backend package. Attach to a node,
/// typically the scene root; descendant [RigidBody], [Collider], and
/// joint components register with the nearest ancestor world on mount.
///
/// A scene may contain more than one world; they are independent
/// simulations. The scene's per-frame driver steps the world on a fixed
/// timestep and interpolates dynamic-body transforms for rendering.
/// {@category Physics}
class PhysicsWorld extends Component {
  PhysicsWorld(this.simulation);

  /// The backend this world drives.
  final sim.PhysicsSimulation simulation;

  final Map<int, Collider> _collidersByHandle = {};
  StreamController<CollisionEvent>? _events;
  StreamSubscription<sim.SimCollisionEvent>? _simEvents;
  double _interpolationAlpha = 0;

  /// The most recent interpolation fraction between physics steps, for
  /// components smoothing their own rendering the way dynamic bodies do.
  double get interpolationAlpha => _interpolationAlpha;

  /// Identifier of the wrapped backend, suitable for logging.
  String get backendName => simulation.backendName;

  /// World-space acceleration applied to every dynamic body each step.
  Vector3 get gravity => simulation.gravity;
  set gravity(Vector3 value) => simulation.gravity = value;

  /// Length of one physics step, in seconds.
  double get fixedTimestep => simulation.fixedTimestep;
  set fixedTimestep(double value) => simulation.fixedTimestep = value;

  /// Maximum fixed steps consumed per frame before time is dropped.
  int get maxSubsteps => simulation.maxSubsteps;
  set maxSubsteps(int value) => simulation.maxSubsteps = value;

  /// Collision lifecycle events for every body in this world.
  Stream<CollisionEvent> get collisions {
    _events ??= StreamController<CollisionEvent>.broadcast();
    _simEvents ??= simulation.collisions.listen(_mapEvent);
    return _events!.stream;
  }

  void _mapEvent(sim.SimCollisionEvent event) {
    final a = _collidersByHandle[event.colliderHandleA];
    final b = _collidersByHandle[event.colliderHandleB];
    // A collider torn down between the step and delivery drops the event.
    if (a == null || b == null) return;
    final mapped = switch (event) {
      sim.SimCollisionBegan(:final contacts) => CollisionBegan(
        nodeA: a.node,
        nodeB: b.node,
        colliderA: a,
        colliderB: b,
        contacts: contacts,
      ),
      sim.SimCollisionEnded() => CollisionEnded(
        nodeA: a.node,
        nodeB: b.node,
        colliderA: a,
        colliderB: b,
      ),
      sim.SimTriggerEntered() => TriggerEntered(
        nodeA: a.node,
        nodeB: b.node,
        colliderA: a,
        colliderB: b,
      ),
      sim.SimTriggerExited() => TriggerExited(
        nodeA: a.node,
        nodeB: b.node,
        colliderA: a,
        colliderB: b,
      ),
    };
    _events?.add(mapped);
  }

  @internal
  void rememberCollider(int handle, Collider collider) =>
      _collidersByHandle[handle] = collider;

  @internal
  void forgetCollider(int handle) => _collidersByHandle.remove(handle);

  RaycastHit? _wrapRay(sim.SimRaycastHit? hit) {
    if (hit == null) return null;
    final collider = _collidersByHandle[hit.colliderHandle];
    if (collider == null) return null;
    return RaycastHit(
      node: collider.node,
      collider: collider,
      worldPoint: hit.worldPoint,
      worldNormal: hit.worldNormal,
      distance: hit.distance,
    );
  }

  RaycastHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => _wrapRay(
    simulation.raycast(
      ray,
      maxDistance: maxDistance,
      layerMask: layerMask,
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    ),
  );

  List<RaycastHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => [
    for (final hit in simulation.raycastAll(
      ray,
      maxDistance: maxDistance,
      layerMask: layerMask,
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    ))
      if (_wrapRay(hit) case final wrapped?) wrapped,
  ];

  List<OverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => [
    for (final hit in simulation.overlapSphere(
      center,
      radius,
      layerMask: layerMask,
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    ))
      if (_collidersByHandle[hit.colliderHandle] case final collider?)
        OverlapHit(node: collider.node, collider: collider),
  ];

  List<OverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => [
    for (final hit in simulation.overlapBox(
      center,
      halfExtents,
      rotation,
      layerMask: layerMask,
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    ))
      if (_collidersByHandle[hit.colliderHandle] case final collider?)
        OverlapHit(node: collider.node, collider: collider),
  ];

  ShapeCastHit? shapeCast(
    sim.Shape shape,
    Matrix4 from,
    Vector3 direction,
    double distance, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    final hit = simulation.shapeCast(
      shape,
      from,
      direction,
      distance,
      layerMask: layerMask,
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    );
    if (hit == null) return null;
    final collider = _collidersByHandle[hit.colliderHandle];
    if (collider == null) return null;
    return ShapeCastHit(
      node: collider.node,
      collider: collider,
      worldPoint: hit.worldPoint,
      worldNormal: hit.worldNormal,
      distance: hit.distance,
    );
  }

  /// Advances the simulation by exactly [fixedDt] seconds. Driver hook;
  /// user code should not call this directly.
  @internal
  void step(double fixedDt) => simulation.step(fixedDt);

  /// Interpolates dynamic-body node transforms between physics steps.
  /// Driver hook; user code should not call this directly.
  @internal
  void interpolateTransforms(double alpha) {
    _interpolationAlpha = alpha;
    simulation.interpolatePoses(alpha);
  }

  @override
  void onUnmount() {
    _simEvents?.cancel();
    _events?.close();
    _collidersByHandle.clear();
    simulation.dispose();
  }
}

/// The nearest [PhysicsWorld] on [start] or its ancestors, or null.
/// {@category Physics}
PhysicsWorld? findAncestorWorld(Node start) {
  for (Node? current = start; current != null; current = current.parent) {
    final world = current.getComponent<PhysicsWorld>();
    if (world != null) return world;
  }
  return null;
}
