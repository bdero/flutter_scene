import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/basic/basic_world.dart';
import 'package:flutter_scene/src/physics/collider.dart';
import 'package:flutter_scene/src/physics/material.dart';
import 'package:flutter_scene/src/physics/shape.dart';
import 'package:vector_math/vector_math.dart';

/// Pure-Dart [Collider] implementation registered with the ancestor
/// [BasicPhysicsWorld] on mount.
///
/// Carries a [Shape] plus surface properties and a local pose. Used for
/// raycasting, overlap queries, and trigger events. Attaching one
/// without a [BasicKinematicBody] on the same node yields a static
/// collider (the basic backend has no dynamics solver).
/// {@category Physics}
class BasicCollider extends Collider {
  BasicCollider({
    required Shape shape,
    PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
    int collisionLayer = 0xFFFFFFFF,
    int collisionMask = 0xFFFFFFFF,
    bool isTrigger = false,
    Matrix4? localPose,
  }) : _shape = shape,
       _material = material,
       _collisionLayer = collisionLayer,
       _collisionMask = collisionMask,
       _isTrigger = isTrigger,
       _localPose = localPose ?? Matrix4.identity();

  Shape _shape;
  PhysicsMaterial _material;
  int _collisionLayer;
  int _collisionMask;
  bool _isTrigger;
  Matrix4 _localPose;

  BasicPhysicsWorld? _world;

  @override
  Shape get shape => _shape;
  @override
  set shape(Shape value) => _shape = value;

  @override
  PhysicsMaterial get material => _material;
  @override
  set material(PhysicsMaterial value) => _material = value;

  @override
  int get collisionLayer => _collisionLayer;
  @override
  set collisionLayer(int value) => _collisionLayer = value;

  @override
  int get collisionMask => _collisionMask;
  @override
  set collisionMask(int value) => _collisionMask = value;

  @override
  bool get isTrigger => _isTrigger;
  @override
  set isTrigger(bool value) {
    if (_isTrigger == value) return;
    _isTrigger = value;
    // Membership in the world's trigger bookkeeping changes when this
    // flag flips; let the world re-classify by re-registering.
    final world = _world;
    if (world != null) {
      world.unregisterCollider(this);
      world.registerCollider(this);
    }
  }

  @override
  Matrix4 get localPose => _localPose;
  @override
  set localPose(Matrix4 value) => _localPose = value;

  /// Concatenated `node.globalTransform * localPose`. Used by the world
  /// when computing world-space bounding volumes and intersection tests.
  Matrix4 get worldPose => node.globalTransform.multiplied(_localPose);

  @override
  void onMount() {
    final world = findAncestorWorld(node);
    if (world == null) return;
    _world = world;
    world.registerCollider(this);
  }

  @override
  void onUnmount() {
    _world?.unregisterCollider(this);
    _world = null;
  }
}

/// Walks [start] and its ancestors looking for a [BasicPhysicsWorld]
/// component. Returns null when none is found.
BasicPhysicsWorld? findAncestorWorld(Node start) {
  Node? current = start;
  while (current != null) {
    final world = current.getComponent<BasicPhysicsWorld>();
    if (world != null) return world;
    current = current.parent;
  }
  return null;
}
