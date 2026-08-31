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
import 'package:flutter_scene/src/components/instanced_mesh_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/triangle_bvh.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/instanced_mesh.dart';
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// A render-geometry intersection from [raycastNode] (or `Scene.raycast`).
/// {@category Picking and input}
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
    this.instanceIndex = -1,
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

  /// The index of the hit instance within an `InstancedMeshComponent`, or
  /// -1 when the hit came from a plain mesh.
  final int instanceIndex;
}

/// Casts [ray] (direction need not be normalized) through [root]'s subtree
/// and returns the nearest hit, or null.
///
/// Only visible nodes participate unless [includeInvisible] is set, and a
/// primitive with `MeshPrimitive.visible` false is likewise skipped unless
/// [includeInvisible] is set. Nodes must intersect [layerMask] (against
/// [Node.layers]), have [Node.raycastable] set, and pass [where] when
/// provided. Skinned meshes are tested at rest pose. Geometry with
/// caller-managed vertex buffers (`setVertices`) or non-triangle topology is
/// skipped.
///
/// `InstancedMeshComponent` participates too: each instance is tested in its
/// own space, and the hit reports which one through
/// [SceneRaycastHit.instanceIndex].
///
/// Dense meshes are tested through a cached per-geometry [TriangleBvh]
/// instead of triangle by triangle, and the search distance shrinks to the
/// best hit found so far, so a nearer mesh prunes the ones behind it.
/// {@category Picking and input}
SceneRaycastHit? raycastNode(
  Node root,
  Ray ray, {
  double maxDistance = double.infinity,
  int layerMask = 0xFFFFFFFF,
  bool Function(Node node)? where,
  bool includeInvisible = false,
}) {
  SceneRaycastHit? nearest;
  final limit = _Limit(maxDistance);
  _walk(root, ray, limit, layerMask, where, includeInvisible, true, true, (
    hit,
  ) {
    if (nearest == null || hit.distance < nearest!.distance) {
      nearest = hit;
      // Nothing farther than this can win, so every remaining box test,
      // bounds early-out, and triangle test gets to reject against it.
      limit.value = hit.distance;
    }
  });
  return nearest;
}

/// Casts [ray] through [root]'s subtree and returns every hit, sorted
/// nearest-first. Parameters as in [raycastNode].
/// {@category Picking and input}
List<SceneRaycastHit> raycastNodeAll(
  Node root,
  Ray ray, {
  double maxDistance = double.infinity,
  int layerMask = 0xFFFFFFFF,
  bool Function(Node node)? where,
  bool includeInvisible = false,
}) {
  final hits = <SceneRaycastHit>[];
  // No distance pruning: every hit along the whole ray is wanted.
  final limit = _Limit(maxDistance);
  _walk(root, ray, limit, layerMask, where, includeInvisible, true, false, (
    hit,
  ) {
    hits.add(hit);
  });
  hits.sort((a, b) => a.distance.compareTo(b.distance));
  return hits;
}

/// The search distance shared by one query, so a nearest-hit walk can shrink
/// it as it goes. A collect-everything walk leaves it at the caller's
/// `maxDistance`.
class _Limit {
  _Limit(this.value);

  double value;
}

void _walk(
  Node node,
  Ray ray,
  _Limit limit,
  int layerMask,
  bool Function(Node)? where,
  bool includeInvisible,
  bool parentVisible,
  bool nearestOnly,
  void Function(SceneRaycastHit) emit,
) {
  final visible = parentVisible && node.visible;
  if (!visible && !includeInvisible) return;

  if ((visible || includeInvisible) &&
      node.raycastable &&
      (node.layers & layerMask) != 0 &&
      (where == null || where(node))) {
    for (final component in node.getComponents<MeshComponent>()) {
      _testNodeMesh(
        node,
        component.mesh.primitives,
        ray,
        limit,
        includeInvisible,
        nearestOnly,
        emit,
      );
    }
    for (final component in node.getComponents<InstancedMeshComponent>()) {
      _testInstancedMesh(
        node,
        component.instancedMesh,
        ray,
        limit,
        nearestOnly,
        emit,
      );
    }
  }
  for (final child in node.children) {
    _walk(
      child,
      ray,
      limit,
      layerMask,
      where,
      includeInvisible,
      visible,
      nearestOnly,
      emit,
    );
  }
}

/// Brings [ray] into the space of [worldTransform] by mapping a point pair,
/// so the direction picks up the transform's full linear part (including
/// non-uniform scale).
///
/// The local direction is intentionally NOT re-normalized: parameter t along
/// the local ray then equals world-space distance along the normalized world
/// direction. Returns null when the transform is singular.
Ray? _toLocalRay(Matrix4 worldTransform, Vector3 origin, Vector3 direction) {
  final toLocal = Matrix4.zero();
  if (toLocal.copyInverse(worldTransform) == 0.0) return null;
  final localOrigin = toLocal.transform3(origin.clone());
  final localTip = toLocal.transform3(origin + direction);
  return Ray.originDirection(localOrigin, localTip - localOrigin);
}

void _testNodeMesh(
  Node node,
  List<MeshPrimitive> primitives,
  Ray ray,
  _Limit limit,
  bool includeInvisible,
  bool nearestOnly,
  void Function(SceneRaycastHit) emit,
) {
  final worldTransform = node.globalTransform;
  final worldDirection = ray.direction.normalized();
  final localRay = _toLocalRay(worldTransform, ray.origin, worldDirection);
  if (localRay == null) return;

  for (var p = 0; p < primitives.length; p++) {
    final primitive = primitives[p];
    if (!primitive.visible && !includeInvisible) continue;
    _testGeometry(
      node: node,
      geometry: primitive.geometry,
      primitiveIndex: p,
      instanceIndex: -1,
      localRay: localRay,
      worldTransform: worldTransform,
      worldOrigin: ray.origin,
      worldDirection: worldDirection,
      limit: limit,
      nearestOnly: nearestOnly,
      emit: emit,
    );
  }
}

void _testInstancedMesh(
  Node node,
  InstancedMesh mesh,
  Ray ray,
  _Limit limit,
  bool nearestOnly,
  void Function(SceneRaycastHit) emit,
) {
  final instances = mesh.instances;
  if (instances.isEmpty) return;
  final nodeTransform = node.globalTransform;
  final worldDirection = ray.direction.normalized();

  // One node-local early-out over the whole batch before any per-instance
  // inverse is taken: the aggregate bounds already cover every instance.
  final aggregate = mesh.aggregateBounds;
  if (aggregate != null) {
    final nodeRay = _toLocalRay(nodeTransform, ray.origin, worldDirection);
    if (nodeRay == null) return;
    if (!_rayIntersectsAabb(nodeRay, aggregate, limit.value)) return;
  }

  final instanceWorld = Matrix4.zero();
  for (var i = 0; i < instances.length; i++) {
    instanceWorld.setFrom(nodeTransform);
    instanceWorld.multiply(instances[i]);
    final localRay = _toLocalRay(instanceWorld, ray.origin, worldDirection);
    if (localRay == null) continue;
    _testGeometry(
      node: node,
      geometry: mesh.geometry,
      primitiveIndex: 0,
      instanceIndex: i,
      localRay: localRay,
      worldTransform: instanceWorld,
      worldOrigin: ray.origin,
      worldDirection: worldDirection,
      limit: limit,
      nearestOnly: nearestOnly,
      emit: emit,
    );
  }
}

void _testGeometry({
  required Node node,
  required Geometry geometry,
  required int primitiveIndex,
  required int instanceIndex,
  required Ray localRay,
  required Matrix4 worldTransform,
  required Vector3 worldOrigin,
  required Vector3 worldDirection,
  required _Limit limit,
  required bool nearestOnly,
  required void Function(SceneRaycastHit) emit,
}) {
  if (geometry.primitiveType != gpu.PrimitiveType.triangle) return;

  // Node-local bounds early-out, before the accelerator is even looked up.
  final bounds = geometry.localBounds;
  if (bounds != null && !_rayIntersectsAabb(localRay, bounds, limit.value)) {
    return;
  }

  final accel = _accelFor(geometry);
  if (accel == null) return;

  // The world transform is constant across every hit on this geometry, so
  // build the normal matrix once instead of per hit.
  Matrix4? normalMatrix;

  void onHit(_TriangleHit hit) {
    // hit.t is in world units because the local direction is the transformed
    // (unnormalized) world unit direction.
    final matrix = normalMatrix ??= _inverseTranspose(worldTransform);
    final worldNormal = _applyLinear(matrix, hit.nx, hit.ny, hit.nz)
      ..normalize();
    if (worldNormal.dot(worldDirection) > 0) worldNormal.negate();
    emit(
      SceneRaycastHit(
        node: node,
        distance: hit.t,
        worldPoint: worldOrigin + worldDirection * hit.t,
        worldNormal: worldNormal,
        uv: accel.uvAt(hit.slot, hit.u, hit.v),
        barycentrics: Vector3(1.0 - hit.u - hit.v, hit.u, hit.v),
        triangleIndex: accel.triangleIndexAt(hit.slot),
        primitiveIndex: primitiveIndex,
        instanceIndex: instanceIndex,
      ),
    );
  }

  final origin = localRay.origin;
  final direction = localRay.direction;
  final bvh = accel.bvh;
  if (bvh == null) {
    _intersectSlotRange(
      accel,
      0,
      accel.triangleCount,
      origin.x,
      origin.y,
      origin.z,
      direction.x,
      direction.y,
      direction.z,
      limit.value,
      nearestOnly,
      onHit,
    );
    return;
  }
  bvh.raycast(
    origin.x,
    origin.y,
    origin.z,
    direction.x,
    direction.y,
    direction.z,
    limit.value,
    (firstSlot, endSlot, rangeLimit) => _intersectSlotRange(
      accel,
      firstSlot,
      endSlot,
      origin.x,
      origin.y,
      origin.z,
      direction.x,
      direction.y,
      direction.z,
      rangeLimit,
      nearestOnly,
      onHit,
    ),
  );
}

/// One local-space triangle intersection, as scalars so the hot loop never
/// allocates. [slot] indexes the accelerator's hierarchy order.
typedef _TriangleHit = ({
  double t,
  double u,
  double v,
  int slot,
  double nx,
  double ny,
  double nz,
});

/// Moller-Trumbore over the contiguous triangle slots `[firstSlot, endSlot)`,
/// both faces, returning the (possibly reduced) search limit.
///
/// Entirely scalar over the accelerator's typed arrays: no `Vector3`
/// temporaries, no closure per triangle, and one array read per component.
/// Only an accepted hit allocates, through [emit].
double _intersectSlotRange(
  _MeshAccel accel,
  int firstSlot,
  int endSlot,
  double ox,
  double oy,
  double oz,
  double dx,
  double dy,
  double dz,
  double limit,
  bool nearestOnly,
  void Function(_TriangleHit) emit,
) {
  final positions = accel.positions;
  final triVerts = accel.triVerts;
  var best = limit;

  for (var slot = firstSlot; slot < endSlot; slot++) {
    final ia = triVerts[slot * 3] * 3;
    final ib = triVerts[slot * 3 + 1] * 3;
    final ic = triVerts[slot * 3 + 2] * 3;

    final ax = positions[ia], ay = positions[ia + 1], az = positions[ia + 2];
    final e1x = positions[ib] - ax;
    final e1y = positions[ib + 1] - ay;
    final e1z = positions[ib + 2] - az;
    final e2x = positions[ic] - ax;
    final e2y = positions[ic + 1] - ay;
    final e2z = positions[ic + 2] - az;

    // p = direction x e2
    final px = dy * e2z - dz * e2y;
    final py = dz * e2x - dx * e2z;
    final pz = dx * e2y - dy * e2x;
    final det = e1x * px + e1y * py + e1z * pz;
    if (det.abs() < 1e-12) continue;
    final invDet = 1.0 / det;

    final tx = ox - ax, ty = oy - ay, tz = oz - az;
    final u = (tx * px + ty * py + tz * pz) * invDet;
    if (u < 0.0 || u > 1.0) continue;

    // q = t x e1
    final qx = ty * e1z - tz * e1y;
    final qy = tz * e1x - tx * e1z;
    final qz = tx * e1y - ty * e1x;
    final v = (dx * qx + dy * qy + dz * qz) * invDet;
    if (v < 0.0 || u + v > 1.0) continue;

    final rayT = (e2x * qx + e2y * qy + e2z * qz) * invDet;
    if (rayT <= 0.0 || rayT > best) continue;

    emit((
      t: rayT,
      u: u,
      v: v,
      slot: slot,
      nx: e1y * e2z - e1z * e2y,
      ny: e1z * e2x - e1x * e2z,
      nz: e1x * e2y - e1y * e2x,
    ));
    if (nearestOnly) best = rayT;
  }
  return best;
}

// Byte offsets within the engine vertex layout (see importer/constants.dart):
// position is the first three floats and tex_coords floats 6..7 in both the
// unskinned and skinned layouts.
const int _positionOffset = 0;
const int _texCoordOffset = 6 * 4;

/// The raycaster's per-geometry view of a mesh: positions and triangle
/// indices normalized into flat typed arrays, plus the hierarchy that orders
/// them.
///
/// Cached on the [Geometry] and rebuilt only when its CPU data is replaced.
/// Normalizing costs one pass and pays for itself immediately: the hot loop
/// then reads `Float32List`/`Uint32List` with no per-vertex branch on the
/// vertex layout and no per-index branch on the index width, and a
/// de-interleaved position stream is a third the footprint of the packed
/// vertex it came from, so it walks a third of the cache lines.
class _MeshAccel {
  _MeshAccel({
    required this.version,
    required this.positions,
    required this.triVerts,
    required this.triOrder,
    required this.texCoords,
    required this.bvh,
  });

  final int version;
  final Float32List positions;
  final Uint32List triVerts;

  /// Maps a hierarchy slot back to its index in the source index stream, or
  /// null when the two coincide (no hierarchy was built).
  final Uint32List? triOrder;
  final Float32List? texCoords;
  final TriangleBvh? bvh;

  int get triangleCount => triVerts.length ~/ 3;

  int triangleIndexAt(int slot) => triOrder?[slot] ?? slot;

  /// The interpolated texture coordinate at barycentrics ([u], [v]) of the
  /// triangle in [slot], or null when the mesh carries no UV data.
  Vector2? uvAt(int slot, double u, double v) {
    final uvs = texCoords;
    if (uvs == null) return null;
    final w = 1.0 - u - v;
    final ia = triVerts[slot * 3] * 2;
    final ib = triVerts[slot * 3 + 1] * 2;
    final ic = triVerts[slot * 3 + 2] * 2;
    return Vector2(
      uvs[ia] * w + uvs[ib] * u + uvs[ic] * v,
      uvs[ia + 1] * w + uvs[ib + 1] * u + uvs[ic + 1] * v,
    );
  }
}

/// Returns [geometry]'s cached raycast accelerator, building it on first use
/// and rebuilding it whenever the geometry's CPU data has been replaced.
///
/// Null when the geometry is not raycastable: caller-managed vertex buffers,
/// an unexpected interleaved stride, or no vertices at all.
_MeshAccel? _accelFor(Geometry geometry) {
  final version = geometry.cpuDataVersion;
  final cached = geometry.raycastAccelerator;
  if (cached is _MeshAccel && cached.version == version) return cached;

  final data = geometry.cpuMeshData;
  final vertexCount = data.vertexCount;
  if (vertexCount == 0) return null;

  // De-interleaved geometry exposes structure-of-arrays attributes;
  // interleaved geometry exposes a single packed buffer. Either is
  // raycastable; a custom interleaved layout (unexpected stride) is not.
  Float32List positions;
  Float32List? texCoords;
  final soaPositions = data.positions;
  if (soaPositions != null) {
    // Already in the layout the hot loop wants; share it rather than copy.
    positions = soaPositions;
    texCoords = data.texCoords;
  } else {
    final vertices = data.vertices;
    if (vertices == null) return null;
    final stride = vertices.lengthInBytes ~/ vertexCount;
    if (stride != kUnskinnedPerVertexSize && stride != kSkinnedPerVertexSize) {
      return null; // custom layout; not raycastable
    }
    positions = Float32List(vertexCount * 3);
    final uvs = Float32List(vertexCount * 2);
    for (var v = 0; v < vertexCount; v++) {
      final base = v * stride;
      positions[v * 3] = vertices.getFloat32(base + _positionOffset, _le);
      positions[v * 3 + 1] = vertices.getFloat32(
        base + _positionOffset + 4,
        _le,
      );
      positions[v * 3 + 2] = vertices.getFloat32(
        base + _positionOffset + 8,
        _le,
      );
      uvs[v * 2] = vertices.getFloat32(base + _texCoordOffset, _le);
      uvs[v * 2 + 1] = vertices.getFloat32(base + _texCoordOffset + 4, _le);
    }
    texCoords = uvs;
  }

  final triVerts = _triangleIndices(
    data.indices,
    data.indexType,
    data.indexCount,
    vertexCount,
  );
  if (triVerts.isEmpty) return null;

  // A hierarchy costs a build pass and roughly n/3 nodes of memory, which is
  // only worth it once the brute-force sweep is long enough to dominate.
  final bvh = triVerts.length ~/ 3 >= TriangleBvh.minTriangles
      ? TriangleBvh.build(positions, triVerts)
      : null;

  final accel = _MeshAccel(
    version: version,
    positions: positions,
    triVerts: bvh?.triVerts ?? triVerts,
    triOrder: bvh?.triOrder,
    texCoords: texCoords,
    bvh: bvh,
  );
  geometry.raycastAccelerator = accel;
  return accel;
}

const Endian _le = Endian.little;

/// Widens an index buffer (or synthesizes the identity order for non-indexed
/// geometry) into three vertex indices per whole triangle.
Uint32List _triangleIndices(
  ByteData? indices,
  gpu.IndexType indexType,
  int indexCount,
  int vertexCount,
) {
  if (indices == null) {
    final triangles = vertexCount ~/ 3;
    final out = Uint32List(triangles * 3);
    for (var i = 0; i < out.length; i++) {
      out[i] = i;
    }
    return out;
  }
  final triangles = indexCount ~/ 3;
  final out = Uint32List(triangles * 3);
  if (indexType == gpu.IndexType.int16) {
    for (var i = 0; i < out.length; i++) {
      out[i] = indices.getUint16(i * 2, _le);
    }
  } else {
    for (var i = 0; i < out.length; i++) {
      out[i] = indices.getUint32(i * 4, _le);
    }
  }
  return out;
}

/// One local-space triangle intersection from [intersectPackedTriangles].
typedef PackedTriangleHit = ({
  double t,
  Vector3 barycentrics,
  int triangleIndex,
  Vector2 uv,
  Vector3 localNormal,
});

/// Intersects [localRay] with the triangles of an engine-layout interleaved
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
  final positions = Float32List(vertexCount * 3);
  final texCoords = Float32List(vertexCount * 2);
  for (var v = 0; v < vertexCount; v++) {
    final base = v * stride;
    positions[v * 3] = vertices.getFloat32(base + _positionOffset, _le);
    positions[v * 3 + 1] = vertices.getFloat32(base + _positionOffset + 4, _le);
    positions[v * 3 + 2] = vertices.getFloat32(base + _positionOffset + 8, _le);
    texCoords[v * 2] = vertices.getFloat32(base + _texCoordOffset, _le);
    texCoords[v * 2 + 1] = vertices.getFloat32(base + _texCoordOffset + 4, _le);
  }
  _intersectAll(
    positions: positions,
    texCoords: texCoords,
    indices: indices,
    indexType: indexType,
    indexCount: indexCount,
    vertexCount: vertexCount,
    localRay: localRay,
    maxDistance: maxDistance,
    emit: emit,
  );
}

/// Structure-of-arrays variant: position (3 floats/vertex) and optional
/// texture coordinates (2 floats/vertex) come from separate lists. Exposed
/// for testing.
@visibleForTesting
void intersectSoATriangles({
  required Float32List positions,
  Float32List? texCoords,
  required ByteData? indices,
  required gpu.IndexType indexType,
  required int indexCount,
  required int vertexCount,
  required Ray localRay,
  required double maxDistance,
  required void Function(PackedTriangleHit) emit,
}) {
  _intersectAll(
    positions: positions,
    texCoords: texCoords,
    indices: indices,
    indexType: indexType,
    indexCount: indexCount,
    vertexCount: vertexCount,
    localRay: localRay,
    maxDistance: maxDistance,
    emit: emit,
  );
}

/// The brute-force, hierarchy-free form of the intersector, over the same
/// scalar core the scene path uses. Reports every hit along the ray.
void _intersectAll({
  required Float32List positions,
  required Float32List? texCoords,
  required ByteData? indices,
  required gpu.IndexType indexType,
  required int indexCount,
  required int vertexCount,
  required Ray localRay,
  required double maxDistance,
  required void Function(PackedTriangleHit) emit,
}) {
  final accel = _MeshAccel(
    version: -1,
    positions: positions,
    triVerts: _triangleIndices(indices, indexType, indexCount, vertexCount),
    triOrder: null,
    texCoords: texCoords,
    bvh: null,
  );
  final origin = localRay.origin;
  final direction = localRay.direction;
  _intersectSlotRange(
    accel,
    0,
    accel.triangleCount,
    origin.x,
    origin.y,
    origin.z,
    direction.x,
    direction.y,
    direction.z,
    maxDistance,
    false,
    (hit) => emit((
      t: hit.t,
      barycentrics: Vector3(1.0 - hit.u - hit.v, hit.u, hit.v),
      triangleIndex: hit.slot,
      // The engine's fixed vertex layouts always carry tex_coords; uv is zero
      // only for a custom layout that omits them.
      uv: accel.uvAt(hit.slot, hit.u, hit.v) ?? Vector2.zero(),
      localNormal: Vector3(hit.nx, hit.ny, hit.nz)..normalize(),
    )),
  );
}

/// The inverse transpose of [transform], the correct normal transform under
/// non-uniform scale.
Matrix4 _inverseTranspose(Matrix4 transform) => Matrix4.copy(transform)
  ..invert()
  ..transpose();

/// Applies the linear part of [m] to the vector ([x], [y], [z]).
Vector3 _applyLinear(Matrix4 m, double x, double y, double z) => Vector3(
  m.entry(0, 0) * x + m.entry(0, 1) * y + m.entry(0, 2) * z,
  m.entry(1, 0) * x + m.entry(1, 1) * y + m.entry(1, 2) * z,
  m.entry(2, 0) * x + m.entry(2, 1) * y + m.entry(2, 2) * z,
);

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
