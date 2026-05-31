import 'dart:async';
import 'dart:ffi';

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

  /// The underlying native world pointer. Exposed for follow-on commits
  /// that wire body and collider lifecycle through their own FFI calls.
  Pointer<native.NativeWorld> get nativeHandle => _handle;

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
  }

  @override
  void step(double fixedDt) {
    final g = gravity;
    native.worldSetGravity(_handle, g.x, g.y, g.z);
    native.worldStep(_handle, fixedDt);
  }

  @override
  void interpolateTransforms(double alpha) {
    // Stage 4 commit F writes interpolated transforms back to nodes.
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
