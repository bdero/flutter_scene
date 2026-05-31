import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// [Collider] backed by Rapier 3D.
///
/// Stage 3 scaffold: stores the shape, material, and pose. Stage 4
/// cooks the shape into a Rapier collider on mount and forwards
/// runtime mutations through the FFI bindings.
class RapierCollider extends Collider {
  RapierCollider({
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
  set isTrigger(bool value) => _isTrigger = value;

  @override
  Matrix4 get localPose => _localPose;
  @override
  set localPose(Matrix4 value) => _localPose = value;
}
