import 'dart:typed_data';

import 'package:box3d/box3d.dart' as b3;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'box3d_physics_world.dart';
import 'box3d_rigid_body.dart';

/// [Collider] backed by box3d.
///
/// Cooks its [shape] into one or more box3d shapes on mount and attaches
/// them to the sibling [Box3dRigidBody]. Material, collision layer/mask,
/// and the trigger flag pass through. Contact and sensor events are enabled
/// on every shape so the world's collision stream sees them.
///
/// [localPose] is baked into the shape geometry: a non-identity pose turns a
/// box into an equivalent convex hull and transforms hull/mesh points.
/// TODO(box3d-collider-localpose): a non-identity pose on a cylinder or
/// height field throws, since box3d cannot offset those through the current
/// package surface. TODO(box3d-combine-rules): PhysicsMaterial combine rules
/// are not represented by box3d.
class Box3dCollider extends Collider {
  Box3dCollider({
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

  Box3dPhysicsWorld? _world;
  List<b3.Box3dShape> _shapes = const [];

  /// Every box3d shape this component owns (one per leaf primitive; a
  /// compound produces several). Empty before mount or when the shape could
  /// not be cooked.
  List<b3.Box3dShape> get nativeShapes => List.unmodifiable(_shapes);

  @override
  void onMount() {
    final world = findAncestorBox3dWorld(node);
    if (world == null) return;
    final body = node.getComponent<Box3dRigidBody>()?.nativeBody;
    if (body == null) {
      throw StateError(
        'Box3dCollider requires a sibling Box3dRigidBody on the same node. '
        'Attach a Box3dRigidBody first.',
      );
    }
    _world = world;
    _shapes = _cook(_shape, _localPose, body);
    for (final shape in _shapes) {
      shape.setCollisionFilter(category: _collisionLayer, mask: _collisionMask);
      shape.contactEventsEnabled = true;
      shape.sensorEventsEnabled = true;
      world.rememberCollider(shape.handle, this);
    }
  }

  @override
  void onUnmount() {
    final world = _world;
    if (world != null) {
      for (final shape in _shapes) {
        world.forgetCollider(shape.handle);
        shape.destroy();
      }
    }
    _world = null;
    _shapes = const [];
  }

  void _rebuild() {
    if (_world == null) return;
    onUnmount();
    onMount();
  }

  b3.Box3dMaterial get _b3Material => b3.Box3dMaterial(
    friction: _material.friction,
    restitution: _material.restitution,
    density: _material.density,
  );

  List<b3.Box3dShape> _cook(Shape shape, Matrix4 pose, b3.Box3dBody body) {
    switch (shape) {
      case SphereShape():
        return [
          body.addSphere(
            shape.radius,
            center: pose.getTranslation(),
            material: _b3Material,
            isSensor: _isTrigger,
          ),
        ];
      case BoxShape():
        if (pose.isIdentity()) {
          return [
            body.addBox(
              shape.halfExtents,
              material: _b3Material,
              isSensor: _isTrigger,
            ),
          ];
        }
        // An offset/rotated box is expressed as the convex hull of its eight
        // transformed corners.
        final hull = body.addConvexHull(
          _boxCorners(shape.halfExtents, pose),
          material: _b3Material,
          isSensor: _isTrigger,
        );
        return hull == null ? const [] : [hull];
      case CapsuleShape():
        final a = pose.transformed3(Vector3(0, -shape.halfHeight, 0));
        final b = pose.transformed3(Vector3(0, shape.halfHeight, 0));
        return [
          body.addCapsule(
            shape.radius,
            pointA: a,
            pointB: b,
            material: _b3Material,
            isSensor: _isTrigger,
          ),
        ];
      case CylinderShape():
        if (!pose.isIdentity()) {
          throw UnsupportedError(
            'Box3dCollider does not support a non-identity localPose on a '
            'CylinderShape yet.',
          );
        }
        return [
          body.addCylinder(
            shape.halfHeight,
            shape.radius,
            material: _b3Material,
            isSensor: _isTrigger,
          ),
        ];
      case ConvexHullShape():
        final hull = body.addConvexHull(
          _transformPoints(shape.points, pose),
          material: _b3Material,
          isSensor: _isTrigger,
        );
        return hull == null ? const [] : [hull];
      case TriMeshShape():
        final mesh = body.addTriMesh(
          _transformPoints(shape.vertices, pose),
          shape.indices,
          material: _b3Material,
          isSensor: _isTrigger,
        );
        return mesh == null ? const [] : [mesh];
      case HeightFieldShape():
        if (!pose.isIdentity()) {
          throw UnsupportedError(
            'Box3dCollider does not support a non-identity localPose on a '
            'HeightFieldShape yet.',
          );
        }
        final field = body.addHeightField(
          countX: shape.width,
          countZ: shape.depth,
          heights: shape.heights,
          scale: shape.scale,
          material: _b3Material,
          isSensor: _isTrigger,
        );
        return field == null ? const [] : [field];
      case CompoundShape():
        return [
          for (final child in shape.children)
            ..._cook(child.shape, pose.multiplied(child.localPose), body),
        ];
    }
  }

  // The eight corners of a box (half extents [h]) transformed by [pose],
  // packed as xyz triplets.
  static Float32List _boxCorners(Vector3 h, Matrix4 pose) {
    final out = Float32List(24);
    var i = 0;
    for (final sx in const [-1.0, 1.0]) {
      for (final sy in const [-1.0, 1.0]) {
        for (final sz in const [-1.0, 1.0]) {
          final v = pose.transformed3(Vector3(sx * h.x, sy * h.y, sz * h.z));
          out[i++] = v.x;
          out[i++] = v.y;
          out[i++] = v.z;
        }
      }
    }
    return out;
  }

  // Copies [src] (packed xyz) transformed by [pose].
  static Float32List _transformPoints(Float32List src, Matrix4 pose) {
    if (pose.isIdentity()) return src;
    final out = Float32List(src.length);
    for (var i = 0; i < src.length; i += 3) {
      final v = pose.transformed3(Vector3(src[i], src[i + 1], src[i + 2]));
      out[i] = v.x;
      out[i + 1] = v.y;
      out[i + 2] = v.z;
    }
    return out;
  }

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
    for (final shape in _shapes) {
      shape.setMaterial(_b3Material);
    }
  }

  @override
  int get collisionLayer => _collisionLayer;
  @override
  set collisionLayer(int value) {
    _collisionLayer = value;
    _pushFilter();
  }

  @override
  int get collisionMask => _collisionMask;
  @override
  set collisionMask(int value) {
    _collisionMask = value;
    _pushFilter();
  }

  void _pushFilter() {
    for (final shape in _shapes) {
      shape.setCollisionFilter(category: _collisionLayer, mask: _collisionMask);
    }
  }

  @override
  bool get isTrigger => _isTrigger;
  @override
  set isTrigger(bool value) {
    if (_isTrigger == value) return;
    _isTrigger = value;
    // box3d fixes the sensor flag at shape creation, so re-cook.
    _rebuild();
  }

  @override
  Matrix4 get localPose => _localPose;
  @override
  set localPose(Matrix4 value) {
    _localPose = value;
    _rebuild();
  }
}
