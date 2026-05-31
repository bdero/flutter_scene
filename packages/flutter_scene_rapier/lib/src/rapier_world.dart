import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
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

  // Reusable 4-float scratch buffer for translation (uses 3) and
  // rotation (uses 4) reads from the native side. Allocated once,
  // freed in onUnmount.
  late final Pointer<Float> _readBuffer = calloc<Float>(4);

  /// The underlying native world pointer. Exposed for follow-on commits
  /// that wire body and collider lifecycle through their own FFI calls.
  Pointer<native.NativeWorld> get nativeHandle => _handle;

  /// Inserts a rigid body into the native world and returns its packed
  /// handle. Called from [RapierRigidBody.onMount].
  int createBody({
    required BodyType type,
    required Vector3 position,
    required Quaternion rotation,
    required double additionalMass,
  }) {
    return native.bodyCreate(
      _handle,
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
  }

  /// Removes a rigid body previously inserted by [createBody].
  void destroyBody(int handle) {
    native.bodyDestroy(_handle, handle);
  }

  /// Reads the body's current world translation. Returns a fresh
  /// [Vector3]; the underlying scratch buffer is reused on each call,
  /// so do not hold a reference to it.
  Vector3 readBodyTranslation(int handle) {
    native.bodyTranslation(_handle, handle, _readBuffer);
    return Vector3(_readBuffer[0], _readBuffer[1], _readBuffer[2]);
  }

  /// Reads the body's current world rotation as a unit quaternion.
  Quaternion readBodyRotation(int handle) {
    native.bodyRotation(_handle, handle, _readBuffer);
    return Quaternion(
      _readBuffer[0],
      _readBuffer[1],
      _readBuffer[2],
      _readBuffer[3],
    );
  }

  static int _bodyKindByte(BodyType type) {
    switch (type) {
      case BodyType.fixed:
        return native.bodyKindFixed;
      case BodyType.kinematic:
        return native.bodyKindKinematic;
      case BodyType.dynamic_:
        return native.bodyKindDynamic;
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
    _finalizer.detach(this);
    native.worldDestroy(_handle);
    calloc.free(_readBuffer);
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
