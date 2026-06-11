/// Scene raycasting against render geometry.
///
/// Tests the actual rendered meshes (no colliders or physics setup), with
/// hit attributes interpolated from the vertex data, so a hit carries the
/// surface UV at the intersection. Used directly for picking and selection,
/// and by the widget-surface input layer to map pointer rays onto widget
/// textures.
///
/// Distinct from the physics queries (`PhysicsWorld.raycast`), which test
/// collision shapes: this answers "what visible surface did the ray touch",
/// physics answers "what does the collision world say".
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// A render-geometry intersection from [raycastNode] (or `Scene.raycast`).
class SceneRaycastHit {
  /// Creates a hit record.
  SceneRaycastHit({
    required this.node,
    required this.distance,
    required this.worldPoint,
    required this.worldNormal,
    required this.uv,
    required this.barycentrics,
    required this.triangleIndex,
    required this.primitiveIndex,
  });

  /// The node whose mesh was hit.
  final Node node;

  /// Distance from the ray origin to [worldPoint], measured along the
  /// normalized ray direction.
  final double distance;

  /// The intersection point, world space.
  final Vector3 worldPoint;

  /// The geometric (triangle face) normal at the hit, world space, unit
  /// length, oriented to face the ray origin.
  final Vector3 worldNormal;

  /// The interpolated texture coordinate at the hit, or null when the mesh
  /// carries no UV data (never a silent zero).
  final Vector2? uv;

  /// Barycentric weights of the hit inside its triangle, ordered to match
  /// the triangle's vertex order.
  final Vector3 barycentrics;

  /// The index of the hit triangle within its primitive's index/vertex
  /// stream.
  final int triangleIndex;

  /// The index of the hit [MeshPrimitive] within the node's mesh.
  final int primitiveIndex;
}

/// Casts [ray] (direction need not be normalized) through [root]'s subtree
/// and returns the nearest hit, or null.
///
/// Only visible nodes participate unless [includeInvisible] is set. Nodes
/// must intersect [layerMask] (against [Node.layers]), have
/// [Node.raycastable] set, and pass [where] when provided. Skinned meshes
/// are tested at rest pose. Geometry with caller-managed vertex buffers
/// (`setVertices`) or non-triangle topology is skipped.
// TODO(raycast): test InstancedMesh components (one local-space test per
// instance transform).
// TODO(raycast): a per-mesh triangle BVH for dense meshes; today each
// candidate mesh is tested per triangle after the node-bounds early-out.
SceneRaycastHit? raycastNode(
  Node root,
  Ray ray, {
  double maxDistance = double.infinity,
  int layerMask = 0xFFFFFFFF,
  bool Function(Node node)? where,
  bool includeInvisible = false,
}) {
  SceneRaycastHit? nearest;
  _walk(root, ray, maxDistance, layerMask, where, includeInvisible, true, (
    hit,
  ) {
    if (nearest == null || hit.distance < nearest!.distance) nearest = hit;
  });
  return nearest;
}

/// Casts [ray] through [root]'s subtree and returns every hit, sorted
/// nearest-first. Parameters as in [raycastNode].
List<SceneRaycastHit> raycastNodeAll(
  Node root,
  Ray ray, {
  double maxDistance = double.infinity,
  int layerMask = 0xFFFFFFFF,
  bool Function(Node node)? where,
  bool includeInvisible = false,
}) {
  final hits = <SceneRaycastHit>[];
  _walk(root, ray, maxDistance, layerMask, where, includeInvisible, true, (
    hit,
  ) {
    hits.add(hit);
  });
  hits.sort((a, b) => a.distance.compareTo(b.distance));
  return hits;
}

void _walk(
  Node node,
  Ray ray,
  double maxDistance,
  int layerMask,
  bool Function(Node)? where,
  bool includeInvisible,
  bool parentVisible,
  void Function(SceneRaycastHit) emit,
) {
  final visible = parentVisible && node.visible;
  if (!visible && !includeInvisible) return;

  if ((visible || includeInvisible) &&
      node.raycastable &&
      (node.layers & layerMask) != 0 &&
      (where == null || where(node))) {
    for (final component in node.getComponents<MeshComponent>()) {
      _testNodeMesh(node, component.mesh.primitives, ray, maxDistance, emit);
    }
  }
  for (final child in node.children) {
    _walk(
      child,
      ray,
      maxDistance,
      layerMask,
      where,
      includeInvisible,
      visible,
      emit,
    );
  }
}

void _testNodeMesh(
  Node node,
  List<MeshPrimitive> primitives,
  Ray ray,
  double maxDistance,
  void Function(SceneRaycastHit) emit,
) {
  final worldTransform = node.globalTransform;
  final toLocal = Matrix4.zero();
  if (toLocal.copyInverse(worldTransform) == 0.0) return;

  // Transform the ray into node-local space by mapping a point pair, so the
  // direction picks up the transform's full linear part (including
  // non-uniform scale). The local direction is intentionally NOT
  // re-normalized: parameter t along the local ray then equals world-space
  // distance along the normalized world direction.
  final worldDirection = ray.direction.normalized();
  final localOrigin = toLocal.transform3(ray.origin.clone());
  final localTip = toLocal.transform3(ray.origin + worldDirection);
  final localRay = Ray.originDirection(localOrigin, localTip - localOrigin);

  for (var p = 0; p < primitives.length; p++) {
    final geometry = primitives[p].geometry;
    if (geometry.primitiveType != gpu.PrimitiveType.triangle) continue;
    final data = geometry.cpuMeshData;
    final vertices = data.vertices;
    if (vertices == null || data.vertexCount == 0) continue;

    final stride = vertices.lengthInBytes ~/ data.vertexCount;
    if (stride != kUnskinnedPerVertexSize && stride != kSkinnedPerVertexSize) {
      continue; // custom layout; not raycastable
    }

    // Node-local bounds early-out.
    final bounds = geometry.localBounds;
    if (bounds != null && !_rayIntersectsAabb(localRay, bounds, maxDistance)) {
      continue;
    }

    _testTriangles(
      node: node,
      primitiveIndex: p,
      vertices: vertices,
      stride: stride,
      indices: data.indices,
      indexType: data.indexType,
      indexCount: data.indexCount,
      vertexCount: data.vertexCount,
      localRay: localRay,
      worldTransform: worldTransform,
      worldOrigin: ray.origin,
      worldDirection: worldDirection,
      maxDistance: maxDistance,
      emit: emit,
    );
  }
}

// Byte offsets within the engine vertex layout (see importer/constants.dart):
// position is the first three floats and tex_coords floats 6..7 in both the
// unskinned and skinned layouts.
const int _positionOffset = 0;
const int _texCoordOffset = 6 * 4;

/// One local-space triangle intersection from [intersectPackedTriangles].
typedef PackedTriangleHit = ({
  double t,
  Vector3 barycentrics,
  int triangleIndex,
  Vector2 uv,
  Vector3 localNormal,
});

/// Intersects [localRay] with the triangles of an engine-layout packed
/// vertex buffer (and optional index buffer), emitting one record per hit
/// (both faces). Pure math over the packed bytes; exposed for testing.
@visibleForTesting
void intersectPackedTriangles({
  required ByteData vertices,
  required int stride,
  required ByteData? indices,
  required gpu.IndexType indexType,
  required int indexCount,
  required int vertexCount,
  required Ray localRay,
  required double maxDistance,
  required void Function(PackedTriangleHit) emit,
}) {
  final count = indices != null ? indexCount : vertexCount;
  int vertexIndex(int i) {
    if (indices == null) return i;
    return indexType == gpu.IndexType.int16
        ? indices.getUint16(i * 2, Endian.little)
        : indices.getUint32(i * 4, Endian.little);
  }

  Vector3 position(int v) => Vector3(
    vertices.getFloat32(v * stride + _positionOffset, Endian.little),
    vertices.getFloat32(v * stride + _positionOffset + 4, Endian.little),
    vertices.getFloat32(v * stride + _positionOffset + 8, Endian.little),
  );

  final origin = localRay.origin;
  final direction = localRay.direction;

  for (var t = 0; t * 3 + 2 < count; t++) {
    final i0 = vertexIndex(t * 3);
    final i1 = vertexIndex(t * 3 + 1);
    final i2 = vertexIndex(t * 3 + 2);
    final a = position(i0);
    final b = position(i1);
    final c = position(i2);

    // Moller-Trumbore, both faces.
    final edge1 = b - a;
    final edge2 = c - a;
    final pvec = direction.cross(edge2);
    final det = edge1.dot(pvec);
    if (det.abs() < 1e-12) continue;
    final invDet = 1.0 / det;
    final tvec = origin - a;
    final u = tvec.dot(pvec) * invDet;
    if (u < 0.0 || u > 1.0) continue;
    final qvec = tvec.cross(edge1);
    final v = direction.dot(qvec) * invDet;
    if (v < 0.0 || u + v > 1.0) continue;
    final rayT = edge2.dot(qvec) * invDet;
    if (rayT <= 0.0 || rayT > maxDistance) continue;

    // The engine's fixed vertex layouts always carry tex_coords, so uv is
    // non-null for every standard-layout hit (the hit field stays nullable
    // for future custom layouts).
    final w = 1.0 - u - v;
    Vector2 texCoord(int vtx) => Vector2(
      vertices.getFloat32(vtx * stride + _texCoordOffset, Endian.little),
      vertices.getFloat32(vtx * stride + _texCoordOffset + 4, Endian.little),
    );

    emit((
      t: rayT,
      barycentrics: Vector3(w, u, v),
      triangleIndex: t,
      uv: texCoord(i0) * w + texCoord(i1) * u + texCoord(i2) * v,
      localNormal: edge1.cross(edge2)..normalize(),
    ));
  }
}

void _testTriangles({
  required Node node,
  required int primitiveIndex,
  required ByteData vertices,
  required int stride,
  required ByteData? indices,
  required gpu.IndexType indexType,
  required int indexCount,
  required int vertexCount,
  required Ray localRay,
  required Matrix4 worldTransform,
  required Vector3 worldOrigin,
  required Vector3 worldDirection,
  required double maxDistance,
  required void Function(SceneRaycastHit) emit,
}) {
  intersectPackedTriangles(
    vertices: vertices,
    stride: stride,
    indices: indices,
    indexType: indexType,
    indexCount: indexCount,
    vertexCount: vertexCount,
    localRay: localRay,
    maxDistance: maxDistance,
    emit: (hit) {
      // hit.t is in world units because the local direction is the
      // transformed (unnormalized) world unit direction.
      final worldPoint = worldOrigin + worldDirection * hit.t;
      final worldNormal = _transformNormal(worldTransform, hit.localNormal);
      if (worldNormal.dot(worldDirection) > 0) worldNormal.negate();
      emit(
        SceneRaycastHit(
          node: node,
          distance: hit.t,
          worldPoint: worldPoint,
          worldNormal: worldNormal,
          uv: hit.uv,
          barycentrics: hit.barycentrics,
          triangleIndex: hit.triangleIndex,
          primitiveIndex: primitiveIndex,
        ),
      );
    },
  );
}

/// Applies the linear part of [transform]'s inverse transpose to [normal],
/// the correct normal transform under non-uniform scale.
Vector3 _transformNormal(Matrix4 transform, Vector3 normal) {
  final inverseTranspose = Matrix4.copy(transform)
    ..invert()
    ..transpose();
  return Vector3(
    inverseTranspose.entry(0, 0) * normal.x +
        inverseTranspose.entry(0, 1) * normal.y +
        inverseTranspose.entry(0, 2) * normal.z,
    inverseTranspose.entry(1, 0) * normal.x +
        inverseTranspose.entry(1, 1) * normal.y +
        inverseTranspose.entry(1, 2) * normal.z,
    inverseTranspose.entry(2, 0) * normal.x +
        inverseTranspose.entry(2, 1) * normal.y +
        inverseTranspose.entry(2, 2) * normal.z,
  )..normalize();
}

bool _rayIntersectsAabb(Ray ray, Aabb3 aabb, double maxDistance) {
  var tMin = 0.0;
  var tMax = maxDistance;
  for (var axis = 0; axis < 3; axis++) {
    final originAxis = ray.origin[axis];
    final directionAxis = ray.direction[axis];
    final minAxis = aabb.min[axis];
    final maxAxis = aabb.max[axis];
    if (directionAxis.abs() < 1e-12) {
      if (originAxis < minAxis || originAxis > maxAxis) return false;
      continue;
    }
    var t1 = (minAxis - originAxis) / directionAxis;
    var t2 = (maxAxis - originAxis) / directionAxis;
    if (t1 > t2) {
      final swap = t1;
      t1 = t2;
      t2 = swap;
    }
    if (t1 > tMin) tMin = t1;
    if (t2 < tMax) tMax = t2;
    if (tMin > tMax) return false;
  }
  return true;
}
