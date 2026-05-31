import 'dart:async';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// [PhysicsWorld] backed by Rapier 3D.
///
/// Stage 3 scaffold: instances construct, the substepping driver can
/// drive [step] and [interpolateTransforms] without error, and the
/// abstract API surface compiles. Scene queries throw
/// [UnimplementedError] until Stage 5 wires them through to Rapier's
/// query pipeline. Body and collider integration land in Stage 4.
class RapierWorld extends PhysicsWorld {
  RapierWorld({Vector3? gravity}) {
    if (gravity != null) this.gravity = gravity;
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
  }

  @override
  void step(double fixedDt) {
    // Stage 4 forwards to Rapier's PhysicsPipeline::step. The scaffold
    // accepts the call so the scene-level driver runs cleanly.
  }

  @override
  void interpolateTransforms(double alpha) {
    // Stage 4 interpolates dynamic-body transforms between substeps.
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
