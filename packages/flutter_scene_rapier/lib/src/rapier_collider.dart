import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/rapier_rigid_body.dart';
import 'package:flutter_scene_rapier/src/rapier_world.dart';
import 'package:vector_math/vector_math.dart';

/// [Collider] backed by Rapier 3D.
///
/// Cooks its [shape] into a Rapier collider on mount and attaches it
/// to the sibling [RapierRigidBody] on the same node. The collider's
/// pose, friction, restitution, density, and trigger flag are passed
/// through to the native side.
///
/// Stage 4 commit F supports [SphereShape] only. The remaining
/// primitive shapes (box, capsule, cylinder) and the heavy shapes
/// (convex hull, trimesh, height field, compound) land in subsequent
/// commits.
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

  RapierWorld? _world;
  int? _handle;

  /// The native collider handle once mounted, or null when the
  /// collider has no ancestor world or no sibling body.
  int? get nativeHandle => _handle;

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

  @override
  void onMount() {
    final world = findAncestorRapierWorld(node);
    if (world == null) return;
    final body = node.getComponent<RapierRigidBody>();
    final bodyHandle = body?.nativeHandle;
    if (body == null || bodyHandle == null) {
      throw StateError(
        'RapierCollider requires a sibling RapierRigidBody on the same '
        'node. Attach a RapierRigidBody first.',
      );
    }
    _world = world;
    final shape = _shape;
    if (shape is SphereShape) {
      _handle = world.createSphereCollider(
        bodyHandle: bodyHandle,
        radius: shape.radius,
        material: _material,
        isTrigger: _isTrigger,
        localPose: _localPose,
      );
    } else {
      throw UnimplementedError(
        'RapierCollider currently supports SphereShape only. Other shapes '
        'land in subsequent Stage 4 commits.',
      );
    }
  }

  @override
  void onUnmount() {
    final world = _world;
    final handle = _handle;
    if (world != null && handle != null) {
      world.destroyCollider(handle);
    }
    _world = null;
    _handle = null;
  }
}
