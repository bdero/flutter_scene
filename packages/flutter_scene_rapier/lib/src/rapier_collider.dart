import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/rapier_rigid_body.dart';
import 'package:flutter_scene_rapier/src/rapier_world.dart';
import 'package:vector_math/vector_math.dart';

/// [Collider] backed by Rapier 3D.
///
/// Cooks its [shape] into one or more Rapier colliders on mount and
/// attaches them to the sibling [RapierRigidBody] on the same node.
/// Material, pose, layer, mask, and trigger flag pass through to the
/// native side.
///
/// All shape variants from the abstract API are supported:
/// SphereShape, BoxShape, CapsuleShape, CylinderShape (Rapier
/// primitives), ConvexHullShape, TriMeshShape, HeightFieldShape (cooked
/// via Rapier's builders), and CompoundShape (each child is attached
/// as its own Rapier collider on the same body, so a Dart compound
/// produces multiple native handles).
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
  // One handle per Rapier collider this component owns. For primitive
  // and heavy-mesh shapes this has length 1; for CompoundShape it has
  // one entry per leaf primitive.
  List<int> _handles = const [];

  /// The first native handle this collider owns, or null when not
  /// mounted. For compound shapes use [nativeHandles] to enumerate all.
  int? get nativeHandle => _handles.isEmpty ? null : _handles.first;

  /// Every Rapier collider handle this component owns. Always
  /// non-empty between mount and unmount on a successful build;
  /// returns an empty list when the collider could not be cooked
  /// (degenerate convex hull, malformed trimesh) or before mount.
  List<int> get nativeHandles => List.unmodifiable(_handles);

  @override
  Shape get shape => _shape;
  @override
  set shape(Shape value) {
    _shape = value;
    _rebuild();
  }

  @override
  PhysicsMaterial get material => _material;
  @override
  set material(PhysicsMaterial value) {
    _material = value;
    final w = _world;
    if (w == null) return;
    for (final h in _handles) {
      w.setColliderMaterial(h, value);
    }
  }

  @override
  int get collisionLayer => _collisionLayer;
  @override
  set collisionLayer(int value) {
    _collisionLayer = value;
    _pushCollisionGroups();
  }

  @override
  int get collisionMask => _collisionMask;
  @override
  set collisionMask(int value) {
    _collisionMask = value;
    _pushCollisionGroups();
  }

  @override
  bool get isTrigger => _isTrigger;
  @override
  set isTrigger(bool value) {
    _isTrigger = value;
    final w = _world;
    if (w == null) return;
    for (final h in _handles) {
      w.setColliderSensor(h, value);
    }
  }

  @override
  Matrix4 get localPose => _localPose;
  @override
  set localPose(Matrix4 value) {
    _localPose = value;
    final w = _world;
    if (w == null || _handles.isEmpty) return;
    // For a compound, the localPose is the compound's offset; child
    // poses are pre-composed at mount time. Re-cooking the whole
    // collider keeps the children consistent.
    if (_shape is CompoundShape) {
      _rebuild();
      return;
    }
    w.setColliderLocalPose(_handles.first, value);
  }

  void _pushCollisionGroups() {
    final w = _world;
    if (w == null) return;
    for (final h in _handles) {
      w.setColliderCollisionGroups(h, _collisionLayer, _collisionMask);
    }
  }

  void _rebuild() {
    final w = _world;
    if (w == null) return;
    for (final h in _handles) {
      w.destroyCollider(h);
    }
    _handles = const [];
    onMount();
  }

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
    _handles = _cookShape(_shape, _localPose, world, bodyHandle);

    if (_collisionLayer != 0xFFFFFFFF || _collisionMask != 0xFFFFFFFF) {
      for (final h in _handles) {
        world.setColliderCollisionGroups(h, _collisionLayer, _collisionMask);
      }
    }
  }

  List<int> _cookShape(
    Shape shape,
    Matrix4 pose,
    RapierWorld world,
    int bodyHandle,
  ) {
    switch (shape) {
      case SphereShape():
        return [
          world.createSphereCollider(
            bodyHandle: bodyHandle,
            radius: shape.radius,
            material: _material,
            isTrigger: _isTrigger,
            localPose: pose,
          ),
        ];
      case BoxShape():
        return [
          world.createBoxCollider(
            bodyHandle: bodyHandle,
            halfExtents: shape.halfExtents,
            material: _material,
            isTrigger: _isTrigger,
            localPose: pose,
          ),
        ];
      case CapsuleShape():
        return [
          world.createCapsuleCollider(
            bodyHandle: bodyHandle,
            halfHeight: shape.halfHeight,
            radius: shape.radius,
            material: _material,
            isTrigger: _isTrigger,
            localPose: pose,
          ),
        ];
      case CylinderShape():
        return [
          world.createCylinderCollider(
            bodyHandle: bodyHandle,
            halfHeight: shape.halfHeight,
            radius: shape.radius,
            material: _material,
            isTrigger: _isTrigger,
            localPose: pose,
          ),
        ];
      case ConvexHullShape():
        final h = world.createConvexHullCollider(
          bodyHandle: bodyHandle,
          points: shape.points,
          material: _material,
          isTrigger: _isTrigger,
          localPose: pose,
        );
        return h == null ? const [] : [h];
      case TriMeshShape():
        final h = world.createTriMeshCollider(
          bodyHandle: bodyHandle,
          vertices: shape.vertices,
          indices: shape.indices,
          material: _material,
          isTrigger: _isTrigger,
          localPose: pose,
        );
        return h == null ? const [] : [h];
      case HeightFieldShape():
        return [
          world.createHeightFieldCollider(
            bodyHandle: bodyHandle,
            width: shape.width,
            depth: shape.depth,
            heights: shape.heights,
            scale: shape.scale,
            material: _material,
            isTrigger: _isTrigger,
            localPose: pose,
          ),
        ];
      case CompoundShape():
        final result = <int>[];
        for (final child in shape.children) {
          final childPose = pose.multiplied(child.localPose);
          result.addAll(_cookShape(child.shape, childPose, world, bodyHandle));
        }
        return result;
    }
  }

  @override
  void onUnmount() {
    final world = _world;
    if (world != null) {
      for (final h in _handles) {
        world.destroyCollider(h);
      }
    }
    _world = null;
    _handles = const [];
  }
}
