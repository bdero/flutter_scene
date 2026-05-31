// Intersection math for the pure-Dart physics backend.
//
// Ray vs sphere/box/capsule are exact. Ray vs convex hull, trimesh,
// height field, and cylinder fall back to a world-space AABB
// approximation, which is conservative but sufficient for picking and
// area queries against small collider counts.
//
// TODO(exact-cylinder): ray-vs-cylinder currently uses the AABB; the
// cylindrical-side + cap-disc intersection is straightforward to
// derive from the capsule code.
// TODO(exact-mesh): ray-vs-convex-hull and ray-vs-trimesh use the
// AABB; an exact implementation needs a per-collider BVH (or the
// brute-force triangle loop for trimesh) for correctness.
// TODO(exact-heightfield): ray-vs-heightfield can rasterize the cell
// the ray enters and intersect against the two triangles per cell.
// TODO(spatial-index): scene-wide queries iterate every collider; a
// BVH over the cached AABBs would make raycast/overlap scale beyond
// the small-collider-count regime.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/physics/shape.dart';
import 'package:vector_math/vector_math.dart';

/// Internal hit record. The owning world wraps this in a [RaycastHit].
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
Aabb3 shapeWorldAabb(Shape shape, Matrix4 worldXform) {
  final local = _shapeLocalAabb(shape);
  return _transformAabb(local, worldXform);
}

/// Whether the closed ball at [center] of [radius] overlaps the AABB
/// [box].
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
bool sphereOverlapsSphere(
  Vector3 center,
  double radius,
  Vector3 otherCenter,
  double otherRadius,
) {
  final sum = radius + otherRadius;
  return (center - otherCenter).length2 <= sum * sum;
}

/// Whether two world-space shapes overlap. Sphere-sphere and
/// sphere-OBB pairs use exact tests; every other pair falls back to a
/// conservative AABB-vs-AABB test (no false negatives, occasional
/// false positives at corners). Suitable for the trigger pair
/// detector in [BasicPhysicsWorld].
bool shapesOverlap(Shape a, Matrix4 ax, Shape b, Matrix4 bx) {
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

/// Closest hit of [ray] against [shape] under [worldXform], or null.
///
/// [maxDistance] is in world units along the normalized ray direction.
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
    case CylinderShape() ||
        ConvexHullShape() ||
        TriMeshShape() ||
        HeightFieldShape():
      return _rayAabb(ray, shapeWorldAabb(shape, worldXform), maxDistance);
  }
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
        final childWorld = _transformAabb(
          _shapeLocalAabb(c.shape),
          c.localPose,
        );
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
