/// Exact integer predicates on the XZ plane, shared by hole merging and
/// triangulation.
///
/// Contour vertices are voxel coordinates, so every one of these is exact.
/// That is not a detail: a triangulator that disagrees with itself about
/// whether a point is left of a line by a rounding error produces overlapping
/// or missing triangles, and the failure shows up much later as an agent
/// walking through a wall.
library;

/// Twice the signed area of the triangle a-b-c, positive when it turns
/// clockwise in the engine's left-handed XZ plane.
int area2(int ax, int az, int bx, int bz, int cx, int cz) =>
    (bx - ax) * (cz - az) - (cx - ax) * (bz - az);

/// Whether c is strictly to the left of the directed line a to b.
bool left(int ax, int az, int bx, int bz, int cx, int cz) =>
    area2(ax, az, bx, bz, cx, cz) < 0;

/// Whether c is to the left of, or on, the directed line a to b.
bool leftOn(int ax, int az, int bx, int bz, int cx, int cz) =>
    area2(ax, az, bx, bz, cx, cz) <= 0;

bool _collinear(int ax, int az, int bx, int bz, int cx, int cz) =>
    area2(ax, az, bx, bz, cx, cz) == 0;

/// Whether the open segments a-b and c-d cross, sharing no endpoint.
bool intersectProper(
  int ax,
  int az,
  int bx,
  int bz,
  int cx,
  int cz,
  int dx,
  int dz,
) {
  if (_collinear(ax, az, bx, bz, cx, cz) ||
      _collinear(ax, az, bx, bz, dx, dz) ||
      _collinear(cx, cz, dx, dz, ax, az) ||
      _collinear(cx, cz, dx, dz, bx, bz)) {
    return false;
  }
  return (left(ax, az, bx, bz, cx, cz) != left(ax, az, bx, bz, dx, dz)) &&
      (left(cx, cz, dx, dz, ax, az) != left(cx, cz, dx, dz, bx, bz));
}

/// Whether c lies on the closed segment a-b, given the three are collinear.
bool between(int ax, int az, int bx, int bz, int cx, int cz) {
  if (!_collinear(ax, az, bx, bz, cx, cz)) return false;
  // Compare along whichever axis the segment actually extends in, so a
  // vertical segment is not judged by its constant coordinate.
  if (ax != bx) {
    return (ax <= cx && cx <= bx) || (ax >= cx && cx >= bx);
  }
  return (az <= cz && cz <= bz) || (az >= cz && cz >= bz);
}

/// Whether the closed segments a-b and c-d meet at all, touching included.
bool intersects(
  int ax,
  int az,
  int bx,
  int bz,
  int cx,
  int cz,
  int dx,
  int dz,
) {
  if (intersectProper(ax, az, bx, bz, cx, cz, dx, dz)) return true;
  return between(ax, az, bx, bz, cx, cz) ||
      between(ax, az, bx, bz, dx, dz) ||
      between(cx, cz, dx, dz, ax, az) ||
      between(cx, cz, dx, dz, bx, bz);
}

/// Whether the ray from the polygon vertex (previous, current, next) toward
/// the point contains that point, which is the local test for "could this be a
/// diagonal".
///
/// Split on whether the vertex is convex or reflex, because at a reflex vertex
/// the interior is the *outside* of the wedge rather than the inside of it.
bool inCone(
  int previousX,
  int previousZ,
  int currentX,
  int currentZ,
  int nextX,
  int nextZ,
  int pointX,
  int pointZ,
) {
  if (leftOn(previousX, previousZ, currentX, currentZ, nextX, nextZ)) {
    return left(currentX, currentZ, pointX, pointZ, previousX, previousZ) &&
        left(pointX, pointZ, currentX, currentZ, nextX, nextZ);
  }
  return !(leftOn(currentX, currentZ, pointX, pointZ, nextX, nextZ) &&
      leftOn(pointX, pointZ, currentX, currentZ, previousX, previousZ));
}
