// Intersection math for the pure-Dart physics backend.
//
// Ray vs sphere, box, capsule, cylinder, height field, and triangle mesh are
// exact. Ray vs convex hull is the one remaining world-space AABB
// approximation: conservative (it never misses) but loose at the corners.
//
// A triangle mesh is tested through a [MeshBvh] cooked once per shape
// instance and cached by identity, and a height field walks only the grid
// cells the ray actually crosses, so neither cost scales with the collider's
// full triangle count. Local-space bounds are cached per shape as well,
// which matters most for the mesh and height field shapes whose local AABB
// otherwise costs a full scan of their sample data on every query.
//
// TODO(exact-hull): ray-vs-convex-hull still uses the AABB. Exact needs the
// hull's face planes, which means running a hull construction over the
// [ConvexHullShape.points] cloud (the points are not guaranteed to already
// be hull vertices, let alone ordered into faces); the ray test itself is
// then a half-space clip. Cook it alongside [triMeshBvh] when that lands.

import 'dart:math' as math;
import 'dart:typed_data';

import 'mesh_bvh.dart';
import 'shape.dart';
import 'package:vector_math/vector_math.dart';

/// Internal hit record. The owning world wraps this in a [RaycastHit].
/// {@category Physics}
class RayShapeHit {
  final double distance;
  final Vector3 worldPoint;
  final Vector3 worldNormal;

  RayShapeHit(this.distance, this.worldPoint, this.worldNormal);
}

/// World-space AABB enclosing [shape] under [worldXform].
///
/// Assumes [worldXform] is a rigid transform (rotation plus
/// translation, no scale). Scale is not supported by the basic backend.
/// {@category Physics}
Aabb3 shapeWorldAabb(Shape shape, Matrix4 worldXform) =>
    _transformAabb(shapeLocalAabb(shape), worldXform);

/// Local-space AABB enclosing [shape], cached per shape instance.
///
/// Shapes are immutable, so the box is computed once and reused. That is the
/// difference between a scene query costing a full scan of every mesh
/// collider's vertex array and costing a matrix multiply, since the broad
/// phase asks for this box on every collider it considers.
/// {@category Physics}
Aabb3 shapeLocalAabb(Shape shape) {
  final cached = _localAabbCache[shape];
  if (cached != null) return cached;
  final computed = _shapeLocalAabb(shape);
  _localAabbCache[shape] = computed;
  return computed;
}

// Keyed by shape identity and holding nothing the shape does not already
// keep alive, so a discarded shape takes its cooked data with it.
final Expando<Aabb3> _localAabbCache = Expando<Aabb3>('shapeLocalAabb');
final Expando<MeshBvh> _triMeshBvhCache = Expando<MeshBvh>('triMeshBvh');

/// The triangle hierarchy for [shape], cooked on first use and cached by
/// shape identity for the lifetime of the shape.
/// {@category Physics}
MeshBvh triMeshBvh(TriMeshShape shape) =>
    _triMeshBvhCache[shape] ??= MeshBvh.build(shape.vertices, shape.indices);

/// Whether the closed ball at [center] of [radius] overlaps the AABB
/// [box].
/// {@category Physics}
bool sphereOverlapsAabb(Vector3 center, double radius, Aabb3 box) {
  final cx = _clamp(center.x, box.min.x, box.max.x);
  final cy = _clamp(center.y, box.min.y, box.max.y);
  final cz = _clamp(center.z, box.min.z, box.max.z);
  final dx = center.x - cx;
  final dy = center.y - cy;
  final dz = center.z - cz;
  return dx * dx + dy * dy + dz * dz <= radius * radius;
}

/// Whether the closed ball at [center] of [radius] overlaps a sphere of
/// [otherRadius] centered at [otherCenter].
/// {@category Physics}
bool sphereOverlapsSphere(
  Vector3 center,
  double radius,
  Vector3 otherCenter,
  double otherRadius,
) {
  final sum = radius + otherRadius;
  return (center - otherCenter).length2 <= sum * sum;
}

/// Whether two world-space shapes overlap. Sphere-sphere, sphere-OBB, and
/// OBB-OBB pairs use exact tests; every other pair falls back to a
/// conservative AABB-vs-AABB test (no false negatives, occasional
/// false positives at corners). Suitable for the trigger pair
/// detector in [BasicPhysicsWorld].
/// {@category Physics}
bool shapesOverlap(Shape a, Matrix4 ax, Shape b, Matrix4 bx) {
  // Box vs Box: the separating-axis test, exact for two oriented boxes.
  if (a is BoxShape && b is BoxShape) {
    return obbOverlapsObb(ax, a.halfExtents, bx, b.halfExtents);
  }
  // Sphere vs Sphere.
  if (a is SphereShape && b is SphereShape) {
    return sphereOverlapsSphere(
      ax.getTranslation(),
      a.radius,
      bx.getTranslation(),
      b.radius,
    );
  }
  // Sphere vs Box (either order).
  if (a is SphereShape && b is BoxShape) {
    return _sphereOverlapsObb(ax.getTranslation(), a.radius, b, bx);
  }
  if (a is BoxShape && b is SphereShape) {
    return _sphereOverlapsObb(bx.getTranslation(), b.radius, a, ax);
  }
  // Fall back to AABB-vs-AABB for everything else.
  final aabbA = shapeWorldAabb(a, ax);
  final aabbB = shapeWorldAabb(b, bx);
  return aabbA.min.x <= aabbB.max.x &&
      aabbA.max.x >= aabbB.min.x &&
      aabbA.min.y <= aabbB.max.y &&
      aabbA.max.y >= aabbB.min.y &&
      aabbA.min.z <= aabbB.max.z &&
      aabbA.max.z >= aabbB.min.z;
}

bool _sphereOverlapsObb(
  Vector3 worldCenter,
  double radius,
  BoxShape box,
  Matrix4 boxWorld,
) {
  // Transform the sphere center into the box's local frame, then run
  // a sphere-vs-AABB test on the box's local extents.
  final inv = Matrix4.inverted(boxWorld);
  final localCenter = inv.transformed3(worldCenter);
  final aabb = Aabb3.minMax(-box.halfExtents, box.halfExtents.clone());
  return sphereOverlapsAabb(localCenter, radius, aabb);
}

/// Whether an oriented box under [aXform] with [aHalf] half-extents overlaps
/// one under [bXform] with [bHalf].
///
/// The Gottschalk separating-axis test: the two boxes are disjoint exactly
/// when some axis separates them, and for a pair of boxes it suffices to try
/// the six face normals and the nine pairwise edge cross products. Exact, and
/// it exits on the first separating axis it finds, which for a typical
/// non-overlapping pair is one of the first three.
/// {@category Physics}
bool obbOverlapsObb(
  Matrix4 aXform,
  Vector3 aHalf,
  Matrix4 bXform,
  Vector3 bHalf,
) {
  // R[i][j] is the cosine between A's axis i and B's axis j; t is the centre
  // offset expressed in A's frame.
  final r = Float64List(9);
  final absR = Float64List(9);
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      final v =
          aXform.entry(0, i) * bXform.entry(0, j) +
          aXform.entry(1, i) * bXform.entry(1, j) +
          aXform.entry(2, i) * bXform.entry(2, j);
      r[i * 3 + j] = v;
      // The epsilon keeps the cross-product axes usable when two axes are
      // near parallel and their cross product degenerates toward zero.
      absR[i * 3 + j] = v.abs() + 1e-9;
    }
  }
  final d = bXform.getTranslation()..sub(aXform.getTranslation());
  final t = Vector3(
    d.x * aXform.entry(0, 0) +
        d.y * aXform.entry(1, 0) +
        d.z * aXform.entry(2, 0),
    d.x * aXform.entry(0, 1) +
        d.y * aXform.entry(1, 1) +
        d.z * aXform.entry(2, 1),
    d.x * aXform.entry(0, 2) +
        d.y * aXform.entry(1, 2) +
        d.z * aXform.entry(2, 2),
  );

  // A's three face normals.
  for (var i = 0; i < 3; i++) {
    final ra = aHalf[i];
    final rb =
        bHalf.x * absR[i * 3] +
        bHalf.y * absR[i * 3 + 1] +
        bHalf.z * absR[i * 3 + 2];
    if (t[i].abs() > ra + rb) return false;
  }
  // B's three face normals.
  for (var j = 0; j < 3; j++) {
    final ra =
        aHalf.x * absR[j] + aHalf.y * absR[3 + j] + aHalf.z * absR[6 + j];
    final rb = bHalf[j];
    final tj = t.x * r[j] + t.y * r[3 + j] + t.z * r[6 + j];
    if (tj.abs() > ra + rb) return false;
  }
  // The nine edge-pair cross products.
  for (var i = 0; i < 3; i++) {
    final i1 = (i + 1) % 3, i2 = (i + 2) % 3;
    for (var j = 0; j < 3; j++) {
      final j1 = (j + 1) % 3, j2 = (j + 2) % 3;
      final ra = aHalf[i1] * absR[i2 * 3 + j] + aHalf[i2] * absR[i1 * 3 + j];
      final rb = bHalf[j1] * absR[i * 3 + j2] + bHalf[j2] * absR[i * 3 + j1];
      final tv = (t[i2] * r[i1 * 3 + j] - t[i1] * r[i2 * 3 + j]).abs();
      if (tv > ra + rb) return false;
    }
  }
  return true;
}

/// Whether the oriented box (`center`, [halfExtents], [probeXform]) overlaps
/// [shape] under [shapeXform].
///
/// Exact for sphere, box, and compound colliders. Everything else falls back
/// to the probe box against the collider's world AABB, which is still a
/// separating-axis test against the real oriented probe rather than against
/// the axis-aligned box that encloses it, so a rotated probe no longer picks
/// up the corners it never actually reached.
/// {@category Physics}
bool obbOverlapsShape(
  Matrix4 probeXform,
  Vector3 halfExtents,
  Shape shape,
  Matrix4 shapeXform,
) {
  switch (shape) {
    case SphereShape(:final radius):
      return _sphereOverlapsObb(
        shapeXform.getTranslation(),
        radius,
        BoxShape(halfExtents: halfExtents),
        probeXform,
      );
    case BoxShape():
      return obbOverlapsObb(
        probeXform,
        halfExtents,
        shapeXform,
        shape.halfExtents,
      );
    case CompoundShape(:final children):
      for (final child in children) {
        if (obbOverlapsShape(
          probeXform,
          halfExtents,
          child.shape,
          shapeXform.multiplied(child.localPose),
        )) {
          return true;
        }
      }
      return false;
    default:
      final box = shapeWorldAabb(shape, shapeXform);
      final center = (box.min + box.max)..scale(0.5);
      final extents = (box.max - box.min)..scale(0.5);
      return obbOverlapsObb(
        probeXform,
        halfExtents,
        Matrix4.translation(center),
        extents,
      );
  }
}

/// Closest hit of [ray] against [shape] under [worldXform], or null.
///
/// [maxDistance] is in world units along the normalized ray direction.
/// {@category Physics}
RayShapeHit? rayHitsShape(
  Ray ray,
  Shape shape,
  Matrix4 worldXform,
  double maxDistance,
) {
  switch (shape) {
    case SphereShape():
      return _raySphere(ray, shape, worldXform, maxDistance);
    case BoxShape():
      return _rayBox(ray, shape, worldXform, maxDistance);
    case CapsuleShape():
      return _rayCapsule(ray, shape, worldXform, maxDistance);
    case CompoundShape(:final children):
      RayShapeHit? best;
      for (final child in children) {
        final childWorld = worldXform.multiplied(child.localPose);
        final hit = rayHitsShape(ray, child.shape, childWorld, maxDistance);
        if (hit != null && (best == null || hit.distance < best.distance)) {
          best = hit;
        }
      }
      return best;
    case CylinderShape():
      return _rayCylinder(ray, shape, worldXform, maxDistance);
    case TriMeshShape():
      return _rayTriMesh(ray, shape, worldXform, maxDistance);
    case HeightFieldShape():
      return _rayHeightField(ray, shape, worldXform, maxDistance);
    case ConvexHullShape():
      // See TODO(exact-hull) at the top of the file.
      return _rayAabb(ray, shapeWorldAabb(shape, worldXform), maxDistance);
  }
}

// Cylinder = the side surface (axis Y, radius r, half height h) plus the two
// cap discs at y = +-h. The side is the same quadratic as the capsule's
// cylindrical section; only the caps differ, being flat rather than
// hemispherical.
RayShapeHit? _rayCylinder(
  Ray ray,
  CylinderShape shape,
  Matrix4 worldXform,
  double maxDistance,
) {
  final inv = Matrix4.inverted(worldXform);
  final worldDir = ray.direction.normalized();
  final lo = inv.transformed3(ray.origin);
  final ld = _transformDir(inv, worldDir);
  final r = shape.radius;
  final h = shape.halfHeight;

  var bestT = double.infinity;
  var bestNormal = Vector3.zero();

  void consider(double t, Vector3 localNormal) {
    if (t < 0 || t > maxDistance || t >= bestT) return;
    bestT = t;
    bestNormal = localNormal;
  }

  // Side: (lo.x + t*ld.x)^2 + (lo.z + t*ld.z)^2 = r^2, accepted only where
  // the hit's local y falls inside the caps.
  final a = ld.x * ld.x + ld.z * ld.z;
  if (a > 1e-12) {
    final b = 2 * (lo.x * ld.x + lo.z * ld.z);
    final c = lo.x * lo.x + lo.z * lo.z - r * r;
    final disc = b * b - 4 * a * c;
    if (disc >= 0) {
      final sq = math.sqrt(disc);
      final inv2a = 1.0 / (2 * a);
      for (final t in [(-b - sq) * inv2a, (-b + sq) * inv2a]) {
        if (t < 0) continue;
        final y = lo.y + ld.y * t;
        if (y < -h || y > h) continue;
        consider(t, Vector3(lo.x + ld.x * t, 0, lo.z + ld.z * t)..normalize());
        break;
      }
    }
  }

  // Caps: the y = +-h planes, clipped to the disc of radius r. A ray running
  // parallel to them can only reach the side, already handled above.
  if (ld.y.abs() > 1e-12) {
    final invDy = 1.0 / ld.y;
    for (final cy in [-h, h]) {
      final t = (cy - lo.y) * invDy;
      if (t < 0) continue;
      final hx = lo.x + ld.x * t;
      final hz = lo.z + ld.z * t;
      if (hx * hx + hz * hz > r * r) continue;
      consider(t, Vector3(0, cy < 0 ? -1.0 : 1.0, 0));
    }
  }

  if (bestT == double.infinity) return null;
  return RayShapeHit(
    bestT,
    ray.origin + worldDir.scaled(bestT),
    _transformDir(worldXform, bestNormal).normalized(),
  );
}

// Exact against the collider's triangles, through the hierarchy cached on
// the shape. The local ray direction stays unit length because the backend's
// transforms are rigid, so the returned parameter is already a world
// distance.
RayShapeHit? _rayTriMesh(
  Ray ray,
  TriMeshShape shape,
  Matrix4 worldXform,
  double maxDistance,
) {
  final inv = Matrix4.inverted(worldXform);
  final worldDir = ray.direction.normalized();
  final lo = inv.transformed3(ray.origin);
  final ld = _transformDir(inv, worldDir);
  final hit = triMeshBvh(
    shape,
  ).raycast(lo.x, lo.y, lo.z, ld.x, ld.y, ld.z, maxDistance);
  if (hit == null) return null;
  final localNormal = Vector3(hit.nx, hit.ny, hit.nz);
  if (localNormal.dot(ld) > 0) localNormal.negate();
  return RayShapeHit(
    hit.t,
    ray.origin + worldDir.scaled(hit.t),
    _transformDir(worldXform, localNormal).normalized(),
  );
}

// Walks the grid cells the ray's XZ projection actually crosses, nearest
// first, and tests the two triangles of each. Because the walk is ordered,
// the first hit is the nearest one and the traversal stops there, so cost
// scales with the length of the ray over the field rather than with the
// field's sample count.
RayShapeHit? _rayHeightField(
  Ray ray,
  HeightFieldShape shape,
  Matrix4 worldXform,
  double maxDistance,
) {
  final width = shape.width;
  final depth = shape.depth;
  if (width < 2 || depth < 2) return null;

  final inv = Matrix4.inverted(worldXform);
  final worldDir = ray.direction.normalized();
  final lo = inv.transformed3(ray.origin);
  final ld = _transformDir(inv, worldDir);

  // Grid space: one unit per sample, sample (i, j) at grid position (i, j).
  // The field is centered on the local origin, hence the half-extent shift.
  final sx = shape.scale.x, sy = shape.scale.y, sz = shape.scale.z;
  if (sx == 0 || sz == 0) return null;
  final gx = lo.x / sx + (width - 1) * 0.5;
  final gz = lo.z / sz + (depth - 1) * 0.5;
  final dgx = ld.x / sx;
  final dgz = ld.z / sz;

  // Clip the ray to the field's footprint so the walk starts on the grid.
  var tEnter = 0.0;
  var tExit = maxDistance;
  if (!_clipSlab(gx, dgx, 0.0, (width - 1).toDouble(), (t0, t1) {
        if (t0 > tEnter) tEnter = t0;
        if (t1 < tExit) tExit = t1;
      }) ||
      !_clipSlab(gz, dgz, 0.0, (depth - 1).toDouble(), (t0, t1) {
        if (t0 > tEnter) tEnter = t0;
        if (t1 < tExit) tExit = t1;
      }) ||
      tEnter > tExit) {
    return null;
  }

  final heights = shape.heights;
  double heightAt(int i, int j) => heights[j * width + i] * sy;

  var cellX = (gx + dgx * tEnter).floor();
  var cellZ = (gz + dgz * tEnter).floor();
  if (cellX < 0) cellX = 0;
  if (cellZ < 0) cellZ = 0;
  if (cellX > width - 2) cellX = width - 2;
  if (cellZ > depth - 2) cellZ = depth - 2;

  final stepX = dgx > 0 ? 1 : (dgx < 0 ? -1 : 0);
  final stepZ = dgz > 0 ? 1 : (dgz < 0 ? -1 : 0);
  // Distance to the next cell boundary on each axis, and the distance
  // between successive boundaries.
  final tDeltaX = stepX == 0 ? double.infinity : (1.0 / dgx).abs();
  final tDeltaZ = stepZ == 0 ? double.infinity : (1.0 / dgz).abs();
  var tMaxX = stepX == 0
      ? double.infinity
      : ((stepX > 0 ? cellX + 1 : cellX) - (gx + dgx * tEnter)) / dgx + tEnter;
  var tMaxZ = stepZ == 0
      ? double.infinity
      : ((stepZ > 0 ? cellZ + 1 : cellZ) - (gz + dgz * tEnter)) / dgz + tEnter;

  final halfX = (width - 1) * 0.5;
  final halfZ = (depth - 1) * 0.5;

  while (true) {
    // The two triangles of this cell, in local space.
    final x0 = (cellX - halfX) * sx, x1 = (cellX + 1 - halfX) * sx;
    final z0 = (cellZ - halfZ) * sz, z1 = (cellZ + 1 - halfZ) * sz;
    final y00 = heightAt(cellX, cellZ);
    final y10 = heightAt(cellX + 1, cellZ);
    final y01 = heightAt(cellX, cellZ + 1);
    final y11 = heightAt(cellX + 1, cellZ + 1);

    var bestT = double.infinity;
    var bestNx = 0.0, bestNy = 0.0, bestNz = 0.0;
    void tri(
      double ax,
      double ay,
      double az,
      double bx,
      double by,
      double bz,
      double cx,
      double cy,
      double cz,
    ) {
      final hit = _rayTriangle(
        lo.x,
        lo.y,
        lo.z,
        ld.x,
        ld.y,
        ld.z,
        ax,
        ay,
        az,
        bx,
        by,
        bz,
        cx,
        cy,
        cz,
        bestT < maxDistance ? bestT : maxDistance,
      );
      if (hit == null) return;
      bestT = hit.t;
      bestNx = hit.nx;
      bestNy = hit.ny;
      bestNz = hit.nz;
    }

    tri(x0, y00, z0, x1, y10, z0, x1, y11, z1);
    tri(x0, y00, z0, x1, y11, z1, x0, y01, z1);

    if (bestT < double.infinity) {
      // A heightfield is a function of (x, z), so its surface normal always
      // has a positive local Y component; orient it that way rather than
      // toward the ray, which keeps a hit from below reporting the same face.
      final normal = Vector3(bestNx, bestNy, bestNz);
      if (normal.y < 0) normal.negate();
      return RayShapeHit(
        bestT,
        ray.origin + worldDir.scaled(bestT),
        _transformDir(worldXform, normal).normalized(),
      );
    }

    // Step to the next cell along whichever axis its boundary comes first.
    if (tMaxX < tMaxZ) {
      if (tMaxX > tExit) return null;
      cellX += stepX;
      if (cellX < 0 || cellX > width - 2) return null;
      tMaxX += tDeltaX;
    } else {
      if (tMaxZ > tExit) return null;
      cellZ += stepZ;
      if (cellZ < 0 || cellZ > depth - 2) return null;
      tMaxZ += tDeltaZ;
    }
  }
}

/// Clips a ray parameter range against one slab, reporting the entry and
/// exit distances through [accept]. Returns false when the ray runs parallel
/// to the slab and outside it.
bool _clipSlab(
  double origin,
  double direction,
  double lo,
  double hi,
  void Function(double enter, double exit) accept,
) {
  if (direction.abs() < 1e-12) return origin >= lo && origin <= hi;
  final inv = 1.0 / direction;
  var t0 = (lo - origin) * inv;
  var t1 = (hi - origin) * inv;
  if (t0 > t1) {
    final swap = t0;
    t0 = t1;
    t1 = swap;
  }
  accept(t0, t1);
  return true;
}

/// Moller-Trumbore against one triangle, scalar and allocation free. Returns
/// the hit distance and the unnormalized geometric normal, or null.
({double t, double nx, double ny, double nz})? _rayTriangle(
  double ox,
  double oy,
  double oz,
  double dx,
  double dy,
  double dz,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  double cx,
  double cy,
  double cz,
  double maxDistance,
) {
  final e1x = bx - ax, e1y = by - ay, e1z = bz - az;
  final e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
  final px = dy * e2z - dz * e2y;
  final py = dz * e2x - dx * e2z;
  final pz = dx * e2y - dy * e2x;
  final det = e1x * px + e1y * py + e1z * pz;
  if (det.abs() < 1e-12) return null;
  final invDet = 1.0 / det;
  final tx = ox - ax, ty = oy - ay, tz = oz - az;
  final u = (tx * px + ty * py + tz * pz) * invDet;
  if (u < 0.0 || u > 1.0) return null;
  final qx = ty * e1z - tz * e1y;
  final qy = tz * e1x - tx * e1z;
  final qz = tx * e1y - ty * e1x;
  final v = (dx * qx + dy * qy + dz * qz) * invDet;
  if (v < 0.0 || u + v > 1.0) return null;
  final t = (e2x * qx + e2y * qy + e2z * qz) * invDet;
  if (t < 0.0 || t > maxDistance) return null;
  return (
    t: t,
    nx: e1y * e2z - e1z * e2y,
    ny: e1z * e2x - e1x * e2z,
    nz: e1x * e2y - e1y * e2x,
  );
}

// Sphere is at the translation of [worldXform], scale ignored.
RayShapeHit? _raySphere(
  Ray ray,
  SphereShape shape,
  Matrix4 worldXform,
  double maxDistance,
) {
  final center = worldXform.getTranslation();
  final dir = ray.direction.normalized();
  final oc = ray.origin - center;
  final b = 2 * oc.dot(dir);
  final c = oc.dot(oc) - shape.radius * shape.radius;
  final disc = b * b - 4 * c;
  if (disc < 0) return null;
  final sqrtDisc = math.sqrt(disc);
  final t1 = (-b - sqrtDisc) * 0.5;
  final t2 = (-b + sqrtDisc) * 0.5;
  final t = t1 >= 0 ? t1 : (t2 >= 0 ? t2 : -1.0);
  if (t < 0 || t > maxDistance) return null;
  final hitPoint = ray.origin + dir.scaled(t);
  final normal = (hitPoint - center).normalized();
  return RayShapeHit(t, hitPoint, normal);
}

// Slab method on the box in its local space; the ray is brought into
// box-local space via the inverse transform.
RayShapeHit? _rayBox(
  Ray ray,
  BoxShape shape,
  Matrix4 worldXform,
  double maxDistance,
) {
  final inv = Matrix4.inverted(worldXform);
  final worldDir = ray.direction.normalized();
  final localOrigin = inv.transformed3(ray.origin);
  final localDir = _transformDir(inv, worldDir);

  final he = shape.halfExtents;
  var tmin = -double.infinity;
  var tmax = double.infinity;
  var hitAxis = -1;
  var hitSign = 1.0;

  for (var axis = 0; axis < 3; axis++) {
    final o = localOrigin[axis];
    final d = localDir[axis];
    final hi = he[axis];
    if (d.abs() < 1e-9) {
      if (o < -hi || o > hi) return null;
      continue;
    }
    var t1 = (-hi - o) / d;
    var t2 = (hi - o) / d;
    var nearSign = -1.0;
    if (t1 > t2) {
      final tmp = t1;
      t1 = t2;
      t2 = tmp;
      nearSign = 1.0;
    }
    if (t1 > tmin) {
      tmin = t1;
      hitAxis = axis;
      hitSign = nearSign;
    }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax || tmax < 0) return null;
  }

  final t = tmin >= 0 ? tmin : tmax;
  if (t < 0 || t > maxDistance) return null;

  final hitPoint = ray.origin + worldDir.scaled(t);
  final localNormal = Vector3.zero();
  if (hitAxis >= 0) localNormal[hitAxis] = hitSign;
  final worldNormal = _transformDir(worldXform, localNormal).normalized();
  return RayShapeHit(t, hitPoint, worldNormal);
}

// Capsule = central cylinder (axis Y, radius r, half height h) plus
// two hemispheres at (0, +-h, 0).
RayShapeHit? _rayCapsule(
  Ray ray,
  CapsuleShape shape,
  Matrix4 worldXform,
  double maxDistance,
) {
  final inv = Matrix4.inverted(worldXform);
  final worldDir = ray.direction.normalized();
  final lo = inv.transformed3(ray.origin);
  final ld = _transformDir(inv, worldDir);
  final r = shape.radius;
  final h = shape.halfHeight;

  RayShapeHit? best;

  void considerLocalHit(double t, Vector3 localHit, Vector3 localNormal) {
    if (t < 0 || t > maxDistance) return;
    if (best != null && t >= best!.distance) return;
    final worldPoint = ray.origin + worldDir.scaled(t);
    final worldNormal = _transformDir(worldXform, localNormal).normalized();
    best = RayShapeHit(t, worldPoint, worldNormal);
  }

  // Cylindrical side: (lo.x + t*ld.x)^2 + (lo.z + t*ld.z)^2 = r^2,
  // valid only where the hit's local y is within [-h, h].
  final a = ld.x * ld.x + ld.z * ld.z;
  if (a > 1e-9) {
    final b = 2 * (lo.x * ld.x + lo.z * ld.z);
    final c = lo.x * lo.x + lo.z * lo.z - r * r;
    final disc = b * b - 4 * a * c;
    if (disc >= 0) {
      final sq = math.sqrt(disc);
      for (final t in [(-b - sq) / (2 * a), (-b + sq) / (2 * a)]) {
        if (t < 0) continue;
        final hit = lo + ld.scaled(t);
        if (hit.y < -h || hit.y > h) continue;
        final normal = Vector3(hit.x, 0, hit.z).normalized();
        considerLocalHit(t, hit, normal);
        break;
      }
    }
  }

  // End hemispheres at +-h.
  for (final cy in [-h, h]) {
    final lc = Vector3(0, cy, 0);
    final oc = lo - lc;
    final b = 2 * oc.dot(ld);
    final c = oc.dot(oc) - r * r;
    final disc = b * b - 4 * c;
    if (disc < 0) continue;
    final sq = math.sqrt(disc);
    final t = (-b - sq) * 0.5;
    if (t < 0) continue;
    final hit = lo + ld.scaled(t);
    // Only the protruding hemisphere counts; the rest is inside the
    // cylindrical section, already covered above.
    if (cy == h && hit.y < h) continue;
    if (cy == -h && hit.y > -h) continue;
    final normal = (hit - lc).normalized();
    considerLocalHit(t, hit, normal);
  }

  return best;
}

// AABB slab in world space, used for the AABB-approximation shapes.
RayShapeHit? _rayAabb(Ray ray, Aabb3 box, double maxDistance) {
  final dir = ray.direction.normalized();
  var tmin = -double.infinity;
  var tmax = double.infinity;
  var hitAxis = -1;
  var hitSign = 1.0;

  for (var axis = 0; axis < 3; axis++) {
    final o = ray.origin[axis];
    final d = dir[axis];
    final lo = box.min[axis];
    final hi = box.max[axis];
    if (d.abs() < 1e-9) {
      if (o < lo || o > hi) return null;
      continue;
    }
    var t1 = (lo - o) / d;
    var t2 = (hi - o) / d;
    var nearSign = -1.0;
    if (t1 > t2) {
      final tmp = t1;
      t1 = t2;
      t2 = tmp;
      nearSign = 1.0;
    }
    if (t1 > tmin) {
      tmin = t1;
      hitAxis = axis;
      hitSign = nearSign;
    }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax || tmax < 0) return null;
  }

  final t = tmin >= 0 ? tmin : tmax;
  if (t < 0 || t > maxDistance) return null;
  final hitPoint = ray.origin + dir.scaled(t);
  final normal = Vector3.zero();
  if (hitAxis >= 0) normal[hitAxis] = hitSign;
  return RayShapeHit(t, hitPoint, normal);
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

Aabb3 _shapeLocalAabb(Shape shape) {
  switch (shape) {
    case SphereShape(:final radius):
      return Aabb3.minMax(
        Vector3(-radius, -radius, -radius),
        Vector3(radius, radius, radius),
      );
    case BoxShape(:final halfExtents):
      return Aabb3.minMax(-halfExtents, halfExtents.clone());
    case CapsuleShape(:final radius, :final halfHeight):
      return Aabb3.minMax(
        Vector3(-radius, -halfHeight - radius, -radius),
        Vector3(radius, halfHeight + radius, radius),
      );
    case CylinderShape(:final radius, :final halfHeight):
      return Aabb3.minMax(
        Vector3(-radius, -halfHeight, -radius),
        Vector3(radius, halfHeight, radius),
      );
    case ConvexHullShape(:final points):
      return _aabbOfPoints(points);
    case TriMeshShape(:final vertices):
      return _aabbOfPoints(vertices);
    case HeightFieldShape(
      :final width,
      :final depth,
      :final heights,
      :final scale,
    ):
      var minH = double.infinity;
      var maxH = -double.infinity;
      for (final h in heights) {
        if (h < minH) minH = h;
        if (h > maxH) maxH = h;
      }
      final hx = (width - 1) * scale.x * 0.5;
      final hz = (depth - 1) * scale.z * 0.5;
      return Aabb3.minMax(
        Vector3(-hx, minH * scale.y, -hz),
        Vector3(hx, maxH * scale.y, hz),
      );
    case CompoundShape(:final children):
      if (children.isEmpty) {
        return Aabb3.minMax(Vector3.zero(), Vector3.zero());
      }
      Aabb3? acc;
      for (final c in children) {
        final childWorld = _transformAabb(shapeLocalAabb(c.shape), c.localPose);
        if (acc == null) {
          acc = childWorld;
        } else {
          acc.hull(childWorld);
        }
      }
      return acc!;
  }
}

Aabb3 _aabbOfPoints(Float32List points) {
  if (points.isEmpty) {
    return Aabb3.minMax(Vector3.zero(), Vector3.zero());
  }
  var minX = points[0];
  var minY = points[1];
  var minZ = points[2];
  var maxX = minX;
  var maxY = minY;
  var maxZ = minZ;
  for (var i = 3; i + 2 < points.length; i += 3) {
    final x = points[i];
    final y = points[i + 1];
    final z = points[i + 2];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;
  }
  return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
}

Aabb3 _transformAabb(Aabb3 local, Matrix4 m) {
  final lmin = local.min;
  final lmax = local.max;
  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  var maxZ = -double.infinity;
  for (var i = 0; i < 8; i++) {
    final c = Vector3(
      (i & 1) == 0 ? lmin.x : lmax.x,
      (i & 2) == 0 ? lmin.y : lmax.y,
      (i & 4) == 0 ? lmin.z : lmax.z,
    );
    m.transform3(c);
    if (c.x < minX) minX = c.x;
    if (c.x > maxX) maxX = c.x;
    if (c.y < minY) minY = c.y;
    if (c.y > maxY) maxY = c.y;
    if (c.z < minZ) minZ = c.z;
    if (c.z > maxZ) maxZ = c.z;
  }
  return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
}

// Applies the 3x3 linear part of [m] to [v] (translation skipped).
Vector3 _transformDir(Matrix4 m, Vector3 v) {
  return Vector3(
    m.entry(0, 0) * v.x + m.entry(0, 1) * v.y + m.entry(0, 2) * v.z,
    m.entry(1, 0) * v.x + m.entry(1, 1) * v.y + m.entry(1, 2) * v.z,
    m.entry(2, 0) * v.x + m.entry(2, 1) * v.y + m.entry(2, 2) * v.z,
  );
}

/// Raycast against an axis-aligned box, the conservative fallback used by
/// sphere casts against inflated collider bounds.
/// {@category Physics}
RayShapeHit? aabbRaycast(Ray ray, Aabb3 box, double maxDistance) {
  final dir = ray.direction.normalized();
  var tmin = -double.infinity;
  var tmax = double.infinity;
  var hitAxis = -1;
  var hitSign = 1.0;
  for (var axis = 0; axis < 3; axis++) {
    final o = ray.origin[axis];
    final d = dir[axis];
    final lo = box.min[axis];
    final hi = box.max[axis];
    if (d.abs() < 1e-9) {
      if (o < lo || o > hi) return null;
      continue;
    }
    var t1 = (lo - o) / d;
    var t2 = (hi - o) / d;
    var nearSign = -1.0;
    if (t1 > t2) {
      final tmp = t1;
      t1 = t2;
      t2 = tmp;
      nearSign = 1.0;
    }
    if (t1 > tmin) {
      tmin = t1;
      hitAxis = axis;
      hitSign = nearSign;
    }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax || tmax < 0) return null;
  }
  final t = tmin >= 0 ? tmin : tmax;
  if (t < 0 || t > maxDistance) return null;
  final hitPoint = ray.origin + dir.scaled(t);
  final normal = Vector3.zero();
  if (hitAxis >= 0) normal[hitAxis] = hitSign;
  return RayShapeHit(t, hitPoint, normal);
}
