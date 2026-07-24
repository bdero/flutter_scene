import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:scene/scene.dart' show BoxShape, CapsuleShape, CompoundChild, CompoundShape, ConvexHullShape, CylinderShape, Shape, SphereShape;

/// Vertex attribute arrays produced by a primitive generator.
///
/// A `null` attribute is left to [MeshGeometry.fromArrays] to default or
/// generate. Used internally to build the procedural primitives below.
typedef PrimitiveArrays = ({
  Float32List positions,
  Float32List? normals,
  Float32List? texCoords,
  Float32List? colors,
  List<int> indices,
});

/// An axis-aligned box geometry spanning `-extents/2` to `+extents/2` on
/// each axis, with flat per-face normals.
///
/// Pass `debugColors: true` to give each corner a distinct vertex color
/// (visualized with an unlit material, as in the Cuboid example). It is off
/// by default so a lit material renders the box in its own base color rather
/// than tinted by the debug colors.
/// {@category Geometry}
class CuboidGeometry extends MeshGeometry {
  /// Builds a cuboid sized to [extents].
  ///
  /// When [debugColors] is true each corner carries a distinct vertex color.
  factory CuboidGeometry(Vector3 extents, {bool debugColors = false}) =>
      CuboidGeometry._(
        extents,
        buildCuboidArrays(extents, debugColors: debugColors),
      );

  CuboidGeometry._(this._extents, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        colors: arrays.colors,
        indices: arrays.indices,
      );

  final Vector3 _extents;

  /// The matching physics collision shape, a box of half the cuboid's
  /// extents centered on the local origin.
  Shape get collisionShape => cuboidCollisionShape(_extents);
}

/// A triangular-prism wedge (a ramp), centered on the origin in X and Z
/// with its base on the `y = 0` plane.
///
/// The size is `(width X, height Y, run Z)`. The sloped top face rises
/// linearly from height `0` at the `-Z` edge to height `Y` at the `+Z`
/// edge, so the slope angle is `atan(Y / Z)`. Normals are flat per face.
/// Useful as a ramp the character walks up.
/// {@category Geometry}
class WedgeGeometry extends MeshGeometry {
  /// Builds a wedge sized to [size] = `(width, height, run)`.
  factory WedgeGeometry(Vector3 size) =>
      WedgeGeometry._(size, buildWedgeArrays(size));

  WedgeGeometry._(this._size, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        colors: arrays.colors,
        indices: arrays.indices,
      );

  final Vector3 _size;

  /// The matching physics collision shape, the convex hull of the wedge's
  /// six corners.
  Shape get collisionShape => wedgeCollisionShape(_size);
}

/// A flat rectangular grid in the XZ plane, centered on the origin, with
/// its surface facing `+Y`.
///
/// [width] spans X and [depth] spans Z. [segmentsX] and [segmentsZ] set
/// the number of grid cells along each axis; subdividing is useful when
/// the surface will be deformed or lit by per-vertex data.
/// {@category Geometry}
class PlaneGeometry extends MeshGeometry {
  /// Builds a plane of the given size and subdivision.
  factory PlaneGeometry({
    double width = 1.0,
    double depth = 1.0,
    int segmentsX = 1,
    int segmentsZ = 1,
  }) {
    return PlaneGeometry._(
      buildPlaneArrays(
        width: width,
        depth: depth,
        segmentsX: segmentsX,
        segmentsZ: segmentsZ,
      ),
    );
  }

  PlaneGeometry._(PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );
}

/// A UV sphere centered on the origin.
///
/// [segments] is the number of divisions around the equator and
/// [rings] the number of divisions from pole to pole. Vertex normals
/// point radially outward and texture coordinates wrap longitude in `u`
/// and latitude in `v`.
/// {@category Geometry}
class SphereGeometry extends MeshGeometry {
  /// Builds a sphere of the given [radius] and tessellation.
  factory SphereGeometry({
    double radius = 0.5,
    int segments = 32,
    int rings = 16,
  }) {
    return SphereGeometry._(
      radius,
      buildSphereArrays(radius: radius, segments: segments, rings: rings),
    );
  }

  SphereGeometry._(this._radius, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );

  final double _radius;

  /// The matching physics collision shape, a sphere of the same radius.
  Shape get collisionShape => SphereShape(radius: _radius);
}

/// A cylinder aligned with the Y axis, centered on the origin.
///
/// [bottomRadius] and [topRadius] are the radii at `y = -height/2` and
/// `y = +height/2`. Giving them different values produces a truncated
/// cone, and setting [topRadius] to `0` produces a cone with its apex at
/// the top. [radialSegments] divides the circumference and
/// [heightSegments] divides the side along Y. [bottomCap] and [topCap]
/// add the end discs (a zero-radius end never emits a cap).
/// {@category Geometry}
class CylinderGeometry extends MeshGeometry {
  /// Builds a cylinder (or cone/truncated cone) of the given dimensions.
  factory CylinderGeometry({
    double bottomRadius = 0.5,
    double topRadius = 0.5,
    double height = 1.0,
    int radialSegments = 32,
    int heightSegments = 1,
    bool bottomCap = true,
    bool topCap = true,
  }) {
    return CylinderGeometry._(
      bottomRadius,
      topRadius,
      height,
      radialSegments,
      buildCylinderArrays(
        bottomRadius: bottomRadius,
        topRadius: topRadius,
        height: height,
        radialSegments: radialSegments,
        heightSegments: heightSegments,
        bottomCap: bottomCap,
        topCap: topCap,
      ),
    );
  }

  CylinderGeometry._(
    this._bottomRadius,
    this._topRadius,
    this._height,
    this._radialSegments,
    PrimitiveArrays arrays,
  ) : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );

  final double _bottomRadius;
  final double _topRadius;
  final double _height;
  final int _radialSegments;

  /// The matching physics collision shape. A straight cylinder (equal
  /// radii) maps to a [CylinderShape]; a cone or truncated cone maps to the
  /// convex hull of its two end rings (a zero-radius end collapses to its
  /// apex point), since there is no analytic cone collision primitive.
  Shape get collisionShape => cylinderCollisionShape(
    bottomRadius: _bottomRadius,
    topRadius: _topRadius,
    height: _height,
    radialSegments: _radialSegments,
  );
}

/// A capsule (a cylinder capped by two hemispheres) aligned with the Y
/// axis, centered on the origin.
///
/// [radius] is the capsule radius and [height] is the length of the
/// cylindrical mid-section, excluding the caps, so the total extent along
/// Y is `height + 2 * radius`. This matches the convention of the physics
/// `CapsuleShape`. [radialSegments] divides the circumference and
/// [capRings] divides each hemispherical cap from its equator to its pole.
/// {@category Geometry}
class CapsuleGeometry extends MeshGeometry {
  /// Builds a capsule of the given [radius] and mid-section [height].
  factory CapsuleGeometry({
    double radius = 0.5,
    double height = 1.0,
    int radialSegments = 32,
    int capRings = 8,
  }) {
    return CapsuleGeometry._(
      radius,
      height,
      buildCapsuleArrays(
        radius: radius,
        height: height,
        radialSegments: radialSegments,
        capRings: capRings,
      ),
    );
  }

  CapsuleGeometry._(this._radius, this._height, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );

  final double _radius;
  final double _height;

  /// The matching physics collision shape, a capsule with the same radius
  /// and mid-section half-height.
  Shape get collisionShape =>
      capsuleCollisionShape(radius: _radius, height: _height);
}

/// A torus (ring) lying in the XZ plane, centered on the origin.
///
/// [radius] is the distance from the center to the center of the tube and
/// [tubeRadius] is the radius of the tube itself. [radialSegments] divides
/// the main ring and [tubularSegments] divides the tube's cross-section.
/// {@category Geometry}
class TorusGeometry extends MeshGeometry {
  /// Builds a torus of the given [radius] and [tubeRadius].
  factory TorusGeometry({
    double radius = 0.5,
    double tubeRadius = 0.2,
    int radialSegments = 32,
    int tubularSegments = 16,
  }) {
    return TorusGeometry._(
      radius,
      tubeRadius,
      buildTorusArrays(
        radius: radius,
        tubeRadius: tubeRadius,
        radialSegments: radialSegments,
        tubularSegments: tubularSegments,
      ),
    );
  }

  TorusGeometry._(this._radius, this._tubeRadius, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );

  final double _radius;
  final double _tubeRadius;

  /// The matching physics collision shape. A torus is not convex, so this
  /// is a [CompoundShape] of convex chunks swept around the ring, which
  /// preserves the central hole. See [torusCollisionShape].
  Shape get collisionShape =>
      torusCollisionShape(radius: _radius, tubeRadius: _tubeRadius);
}

/// A flat filled disc in the XZ plane, centered on the origin, facing
/// `+Y`.
///
/// [radius] is the disc radius and [segments] the number of wedges around
/// the rim.
/// {@category Geometry}
class DiscGeometry extends MeshGeometry {
  /// Builds a disc of the given [radius].
  factory DiscGeometry({double radius = 0.5, int segments = 32}) {
    return DiscGeometry._(
      radius,
      buildDiscArrays(radius: radius, segments: segments),
    );
  }

  DiscGeometry._(this._radius, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );

  final double _radius;

  /// The matching physics collision shape. A flat disc has no volume, so
  /// this is a thin [CylinderShape] (a coin). See [discCollisionShape].
  Shape get collisionShape => discCollisionShape(radius: _radius);
}

/// A flat annulus (a disc with a concentric hole) in the XZ plane,
/// centered on the origin, facing `+Y`.
///
/// [innerRadius] is the hole radius and [outerRadius] the rim radius.
/// [segments] is the number of wedges around the ring.
/// {@category Geometry}
class RingGeometry extends MeshGeometry {
  /// Builds an annulus between [innerRadius] and [outerRadius].
  factory RingGeometry({
    double innerRadius = 0.25,
    double outerRadius = 0.5,
    int segments = 32,
  }) {
    return RingGeometry._(
      innerRadius,
      outerRadius,
      buildRingArrays(
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        segments: segments,
      ),
    );
  }

  RingGeometry._(this._innerRadius, this._outerRadius, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );

  final double _innerRadius;
  final double _outerRadius;

  /// The matching physics collision shape. An annulus is not convex, so
  /// this is a [CompoundShape] of thin convex segments around the ring,
  /// which preserves the hole. See [ringCollisionShape].
  Shape get collisionShape =>
      ringCollisionShape(innerRadius: _innerRadius, outerRadius: _outerRadius);
}

/// A geodesic sphere built by subdividing an icosahedron, centered on the
/// origin.
///
/// Unlike [SphereGeometry] (a UV sphere with pinched poles), an icosphere
/// has near-uniform triangle sizes over the whole surface. [subdivisions]
/// controls the tessellation: each step quadruples the triangle count
/// (`0` is the bare 20-face icosahedron). Vertex normals point radially
/// outward.
/// {@category Geometry}
class IcosphereGeometry extends MeshGeometry {
  /// Builds an icosphere of the given [radius] and [subdivisions].
  factory IcosphereGeometry({double radius = 0.5, int subdivisions = 2}) {
    return IcosphereGeometry._(
      radius,
      buildIcosphereArrays(radius: radius, subdivisions: subdivisions),
    );
  }

  IcosphereGeometry._(this._radius, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
      );

  final double _radius;

  /// The matching physics collision shape, a sphere of the same radius.
  Shape get collisionShape => SphereShape(radius: _radius);
}

/// Generates the vertex arrays for a [CuboidGeometry] sized to [extents].
///
/// Each face is emitted as its own four vertices carrying that face's flat
/// outward normal, so the box shades (and receives shadows) with crisp,
/// flat faces. When [debugColors] is true each vertex also carries its
/// corner's distinct debug color; otherwise no vertex colors are emitted.
PrimitiveArrays buildCuboidArrays(Vector3 extents, {bool debugColors = false}) {
  final e = extents * 0.5;
  final corners = <Vector3>[
    Vector3(-e.x, -e.y, -e.z),
    Vector3(e.x, -e.y, -e.z),
    Vector3(e.x, e.y, -e.z),
    Vector3(-e.x, e.y, -e.z),
    Vector3(-e.x, -e.y, e.z),
    Vector3(e.x, -e.y, e.z),
    Vector3(e.x, e.y, e.z),
    Vector3(-e.x, e.y, e.z),
  ];
  const cornerColors = <List<double>>[
    [1, 0, 0, 1],
    [0, 1, 0, 1],
    [0, 0, 1, 1],
    [0, 0, 0, 1],
    [0, 1, 1, 1],
    [1, 0, 1, 1],
    [1, 1, 0, 1],
    [1, 1, 1, 1],
  ];
  // Each face: its four corner indices wound (a, b, c, d) so the outward
  // normal follows the engine's front-face convention, plus that normal.
  const faces = <(List<int>, List<double>)>[
    ([0, 1, 2, 3], [0, 0, -1]), // -Z
    ([1, 5, 6, 2], [1, 0, 0]), //  +X
    ([5, 4, 7, 6], [0, 0, 1]), //  +Z
    ([4, 0, 3, 7], [-1, 0, 0]), // -X
    ([3, 2, 6, 7], [0, 1, 0]), //  +Y
    ([4, 5, 1, 0], [0, -1, 0]), // -Y
  ];
  // Texture coordinates follow the glTF convention (v = 0 at the top of the
  // image), matching how image rows are uploaded, so face UVs put v = 1 on
  // the bottom edge of each face.
  const faceUvs = <List<double>>[
    [0, 1],
    [1, 1],
    [1, 0],
    [0, 0],
  ];

  final positions = Float32List(24 * 3);
  final normals = Float32List(24 * 3);
  final texCoords = Float32List(24 * 2);
  final colors = debugColors ? Float32List(24 * 4) : null;
  final indices = <int>[];
  for (var f = 0; f < faces.length; f++) {
    final (cornerIndices, normal) = faces[f];
    final base = f * 4;
    for (var i = 0; i < 4; i++) {
      final v = base + i;
      final corner = corners[cornerIndices[i]];
      positions[v * 3] = corner.x;
      positions[v * 3 + 1] = corner.y;
      positions[v * 3 + 2] = corner.z;
      normals[v * 3] = normal[0].toDouble();
      normals[v * 3 + 1] = normal[1].toDouble();
      normals[v * 3 + 2] = normal[2].toDouble();
      texCoords[v * 2] = faceUvs[i][0];
      texCoords[v * 2 + 1] = faceUvs[i][1];
      if (colors != null) {
        final color = cornerColors[cornerIndices[i]];
        colors[v * 4] = color[0];
        colors[v * 4 + 1] = color[1];
        colors[v * 4 + 2] = color[2];
        colors[v * 4 + 3] = color[3];
      }
    }
    // Two triangles matching the original winding: (a, b, d) and (d, b, c).
    indices.addAll([base, base + 1, base + 3, base + 3, base + 1, base + 2]);
  }
  return (
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: colors,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [PlaneGeometry].
/// Builds the vertex arrays for a [WedgeGeometry] of `(width, height,
/// run)` [size]. Flat per-face normals; faces are wound to match the
/// engine's front-face convention (as [buildCuboidArrays] does).
PrimitiveArrays buildWedgeArrays(Vector3 size) {
  final hx = size.x / 2;
  final hz = size.z / 2;
  final y = size.y;
  final l0 = Vector3(-hx, 0, -hz); // low edge (y = 0), -Z
  final l1 = Vector3(hx, 0, -hz);
  final b0 = Vector3(-hx, 0, hz); // back-bottom, +Z
  final b1 = Vector3(hx, 0, hz);
  final t0 = Vector3(-hx, y, hz); // back-top, +Z
  final t1 = Vector3(hx, y, hz);
  // Slope faces up and toward the low (-Z) edge.
  final slopeN = Vector3(0, size.z, -size.y).normalized();

  final positions = <double>[];
  final normals = <double>[];
  final texCoords = <double>[];
  final indices = <int>[];

  void addVert(Vector3 p, Vector3 n, double u, double v) {
    positions.addAll([p.x, p.y, p.z]);
    normals.addAll([n.x, n.y, n.z]);
    texCoords.addAll([u, v]);
  }

  void addQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 n) {
    final base = positions.length ~/ 3;
    // v = 0 at the top of the image (the glTF convention; see faceUvs in
    // buildCuboidArrays).
    addVert(a, n, 0, 1);
    addVert(b, n, 1, 1);
    addVert(c, n, 1, 0);
    addVert(d, n, 0, 0);
    indices.addAll([base, base + 1, base + 3, base + 3, base + 1, base + 2]);
  }

  void addTri(Vector3 a, Vector3 b, Vector3 c, Vector3 n) {
    final base = positions.length ~/ 3;
    addVert(a, n, 0, 0);
    addVert(b, n, 1, 0);
    addVert(c, n, 0, 1);
    indices.addAll([base, base + 1, base + 2]);
  }

  addQuad(l0, l1, t1, t0, slopeN); // sloped top
  addQuad(l0, b0, b1, l1, Vector3(0, -1, 0)); // bottom
  addQuad(b0, t0, t1, b1, Vector3(0, 0, 1)); // vertical back
  addTri(l0, t0, b0, Vector3(-1, 0, 0)); // left side
  addTri(l1, b1, t1, Vector3(1, 0, 0)); // right side

  return (
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(texCoords),
    colors: null,
    indices: indices,
  );
}

PrimitiveArrays buildPlaneArrays({
  required double width,
  required double depth,
  required int segmentsX,
  required int segmentsZ,
}) {
  if (segmentsX < 1 || segmentsZ < 1) {
    throw ArgumentError('A plane needs at least one segment on each axis');
  }
  final columns = segmentsX + 1;
  final rows = segmentsZ + 1;
  final vertexCount = columns * rows;
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);
  final texCoords = Float32List(vertexCount * 2);

  for (var r = 0; r < rows; r++) {
    final z = -depth / 2 + depth * r / segmentsZ;
    for (var c = 0; c < columns; c++) {
      final x = -width / 2 + width * c / segmentsX;
      final v = r * columns + c;
      positions[v * 3] = x;
      positions[v * 3 + 1] = 0.0;
      positions[v * 3 + 2] = z;
      normals[v * 3 + 1] = 1.0;
      texCoords[v * 2] = c / segmentsX;
      texCoords[v * 2 + 1] = r / segmentsZ;
    }
  }

  final indices = <int>[];
  for (var r = 0; r < segmentsZ; r++) {
    for (var c = 0; c < segmentsX; c++) {
      final v00 = r * columns + c;
      final v10 = v00 + 1;
      final v01 = v00 + columns;
      final v11 = v01 + 1;
      // Wound so the lit surface faces +Y, toward a camera above.
      indices
        ..addAll([v00, v10, v01])
        ..addAll([v10, v11, v01]);
    }
  }

  return (
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [SphereGeometry].
PrimitiveArrays buildSphereArrays({
  required double radius,
  required int segments,
  required int rings,
}) {
  if (segments < 3) {
    throw ArgumentError('A sphere needs at least three segments');
  }
  if (rings < 2) {
    throw ArgumentError('A sphere needs at least two rings');
  }
  final columns = segments + 1;
  final rowCount = rings + 1;
  final vertexCount = columns * rowCount;
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);
  final texCoords = Float32List(vertexCount * 2);

  for (var r = 0; r < rowCount; r++) {
    final latitude = math.pi * r / rings;
    final sinLat = math.sin(latitude);
    final cosLat = math.cos(latitude);
    for (var s = 0; s < columns; s++) {
      final longitude = 2 * math.pi * s / segments;
      final sinLon = math.sin(longitude);
      final cosLon = math.cos(longitude);
      final nx = sinLat * cosLon;
      final ny = cosLat;
      final nz = sinLat * sinLon;
      final v = r * columns + s;
      positions[v * 3] = radius * nx;
      positions[v * 3 + 1] = radius * ny;
      positions[v * 3 + 2] = radius * nz;
      normals[v * 3] = nx;
      normals[v * 3 + 1] = ny;
      normals[v * 3 + 2] = nz;
      texCoords[v * 2] = s / segments;
      texCoords[v * 2 + 1] = r / rings;
    }
  }

  final indices = <int>[];
  for (var r = 0; r < rings; r++) {
    for (var s = 0; s < segments; s++) {
      final a = r * columns + s;
      final b = a + 1;
      final c = a + columns;
      final d = c + 1;
      // Wound counter-clockwise as seen from outside the sphere.
      indices
        ..addAll([a, c, b])
        ..addAll([b, c, d]);
    }
  }

  return (
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [CylinderGeometry].
///
/// The side is a grid of `radialSegments + 1` columns by
/// `heightSegments + 1` rows whose normals account for the slope when the
/// radii differ (so a cone shades correctly). End caps are triangle fans
/// about a center vertex, emitted only when requested and the matching
/// radius is nonzero. Rows run from the top (`y = +height/2`) down, so the
/// side winding matches [buildSphereArrays].
PrimitiveArrays buildCylinderArrays({
  required double bottomRadius,
  required double topRadius,
  required double height,
  required int radialSegments,
  required int heightSegments,
  required bool bottomCap,
  required bool topCap,
}) {
  if (radialSegments < 3) {
    throw ArgumentError('A cylinder needs at least three radial segments');
  }
  if (heightSegments < 1) {
    throw ArgumentError('A cylinder needs at least one height segment');
  }
  if (bottomRadius < 0 || topRadius < 0) {
    throw ArgumentError('Cylinder radii cannot be negative');
  }
  if (bottomRadius == 0 && topRadius == 0) {
    throw ArgumentError(
      'A cylinder needs a nonzero radius on at least one end',
    );
  }

  final positions = <double>[];
  final normals = <double>[];
  final texCoords = <double>[];
  final indices = <int>[];

  void addVert(Vector3 p, Vector3 n, double u, double v) {
    positions.addAll([p.x, p.y, p.z]);
    normals.addAll([n.x, n.y, n.z]);
    texCoords.addAll([u, v]);
  }

  // Side surface. The outward normal tilts by the wall slope: in the
  // (radial, y) plane the wall runs from (bottomRadius, -h/2) to
  // (topRadius, +h/2), so its outward normal is (height, bottomRadius -
  // topRadius) before normalizing.
  final slopeY = bottomRadius - topRadius;
  final columns = radialSegments + 1;
  for (var r = 0; r <= heightSegments; r++) {
    final t = r / heightSegments; // 0 at the top row, 1 at the bottom
    final y = height / 2 - height * t;
    final radius = topRadius + (bottomRadius - topRadius) * t;
    for (var s = 0; s <= radialSegments; s++) {
      final theta = 2 * math.pi * s / radialSegments;
      final cos = math.cos(theta);
      final sin = math.sin(theta);
      final normal = Vector3(height * cos, slopeY, height * sin).normalized();
      addVert(
        Vector3(radius * cos, y, radius * sin),
        normal,
        s / radialSegments,
        t,
      );
    }
  }
  for (var r = 0; r < heightSegments; r++) {
    // A zero-radius end collapses its whole row to a point, so the band
    // next to it is a triangle fan, not quads: the triangle that would use
    // two coincident apex vertices is degenerate and is skipped.
    final topApex = r == 0 && topRadius == 0;
    final bottomApex = r + 1 == heightSegments && bottomRadius == 0;
    for (var s = 0; s < radialSegments; s++) {
      final a = r * columns + s;
      final b = a + 1;
      final c = a + columns;
      final d = c + 1;
      if (!topApex) indices.addAll([a, c, b]);
      if (!bottomApex) indices.addAll([b, c, d]);
    }
  }

  // End cap as a triangle fan. [flip] selects the winding so the cap's
  // front face points away along the cap's outward normal (0, ny, 0).
  void addCap(double y, double radius, double ny, {required bool flip}) {
    if (radius <= 0) return;
    final center = positions.length ~/ 3;
    addVert(Vector3(0, y, 0), Vector3(0, ny, 0), 0.5, 0.5);
    final rimBase = positions.length ~/ 3;
    for (var s = 0; s <= radialSegments; s++) {
      final theta = 2 * math.pi * s / radialSegments;
      final cos = math.cos(theta);
      final sin = math.sin(theta);
      addVert(
        Vector3(radius * cos, y, radius * sin),
        Vector3(0, ny, 0),
        0.5 + 0.5 * cos,
        0.5 + 0.5 * sin,
      );
    }
    for (var s = 0; s < radialSegments; s++) {
      final r0 = rimBase + s;
      final r1 = rimBase + s + 1;
      indices.addAll(flip ? [center, r1, r0] : [center, r0, r1]);
    }
  }

  if (bottomCap) addCap(-height / 2, bottomRadius, -1, flip: true);
  if (topCap) addCap(height / 2, topRadius, 1, flip: false);

  return (
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(texCoords),
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [CapsuleGeometry].
///
/// Built as latitude rings from the top pole down to the bottom pole: the
/// two hemispheres share their equator rings with the cylindrical
/// mid-section, whose seam carries horizontal normals. Rows run top to
/// bottom so the winding matches [buildSphereArrays].
PrimitiveArrays buildCapsuleArrays({
  required double radius,
  required double height,
  required int radialSegments,
  required int capRings,
}) {
  if (radialSegments < 3) {
    throw ArgumentError('A capsule needs at least three radial segments');
  }
  if (capRings < 1) {
    throw ArgumentError('A capsule needs at least one cap ring');
  }
  if (radius <= 0) {
    throw ArgumentError('A capsule needs a positive radius');
  }

  final halfH = height / 2;
  final rings = <({double posY, double posR, double normY, double normR})>[];
  // Top hemisphere: phi 0 (pole) to pi/2 (equator at y = +height/2).
  for (var r = 0; r <= capRings; r++) {
    final phi = (math.pi / 2) * (r / capRings);
    rings.add((
      posY: halfH + radius * math.cos(phi),
      posR: radius * math.sin(phi),
      normY: math.cos(phi),
      normR: math.sin(phi),
    ));
  }
  // Bottom hemisphere: phi pi/2 (equator at y = -height/2) to pi (pole).
  for (var r = 0; r <= capRings; r++) {
    final phi = (math.pi / 2) + (math.pi / 2) * (r / capRings);
    rings.add((
      posY: -halfH + radius * math.cos(phi),
      posR: radius * math.sin(phi),
      normY: math.cos(phi),
      normR: math.sin(phi),
    ));
  }

  final columns = radialSegments + 1;
  final rowCount = rings.length;
  final positions = <double>[];
  final normals = <double>[];
  final texCoords = <double>[];
  for (var r = 0; r < rowCount; r++) {
    final ring = rings[r];
    for (var s = 0; s <= radialSegments; s++) {
      final theta = 2 * math.pi * s / radialSegments;
      final cos = math.cos(theta);
      final sin = math.sin(theta);
      positions.addAll([ring.posR * cos, ring.posY, ring.posR * sin]);
      normals.addAll([ring.normR * cos, ring.normY, ring.normR * sin]);
      texCoords.addAll([s / radialSegments, r / (rowCount - 1)]);
    }
  }
  final indices = <int>[];
  for (var r = 0; r < rowCount - 1; r++) {
    for (var s = 0; s < radialSegments; s++) {
      final a = r * columns + s;
      final b = a + 1;
      final c = a + columns;
      final d = c + 1;
      indices
        ..addAll([a, c, b])
        ..addAll([b, c, d]);
    }
  }

  return (
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(texCoords),
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [TorusGeometry] lying in the XZ
/// plane.
PrimitiveArrays buildTorusArrays({
  required double radius,
  required double tubeRadius,
  required int radialSegments,
  required int tubularSegments,
}) {
  if (radialSegments < 3) {
    throw ArgumentError('A torus needs at least three radial segments');
  }
  if (tubularSegments < 3) {
    throw ArgumentError('A torus needs at least three tubular segments');
  }
  if (radius <= 0 || tubeRadius <= 0) {
    throw ArgumentError('A torus needs positive radii');
  }

  final columns = tubularSegments + 1;
  final positions = <double>[];
  final normals = <double>[];
  final texCoords = <double>[];
  for (var i = 0; i <= radialSegments; i++) {
    final u = 2 * math.pi * i / radialSegments;
    final cosU = math.cos(u);
    final sinU = math.sin(u);
    for (var j = 0; j <= tubularSegments; j++) {
      final v = 2 * math.pi * j / tubularSegments;
      final cosV = math.cos(v);
      final sinV = math.sin(v);
      final ringRadius = radius + tubeRadius * cosV;
      positions.addAll([
        ringRadius * cosU,
        tubeRadius * sinV,
        ringRadius * sinU,
      ]);
      normals.addAll([cosV * cosU, sinV, cosV * sinU]);
      texCoords.addAll([j / tubularSegments, i / radialSegments]);
    }
  }
  final indices = <int>[];
  for (var i = 0; i < radialSegments; i++) {
    for (var j = 0; j < tubularSegments; j++) {
      final a = i * columns + j;
      final b = a + 1;
      final c = a + columns;
      final d = c + 1;
      indices
        ..addAll([a, c, b])
        ..addAll([b, c, d]);
    }
  }

  return (
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(texCoords),
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [DiscGeometry], a filled disc in the
/// XZ plane facing +Y.
PrimitiveArrays buildDiscArrays({
  required double radius,
  required int segments,
}) {
  if (segments < 3) {
    throw ArgumentError('A disc needs at least three segments');
  }
  if (radius <= 0) {
    throw ArgumentError('A disc needs a positive radius');
  }

  final positions = <double>[0, 0, 0];
  final normals = <double>[0, 1, 0];
  final texCoords = <double>[0.5, 0.5];
  for (var s = 0; s <= segments; s++) {
    final theta = 2 * math.pi * s / segments;
    final cos = math.cos(theta);
    final sin = math.sin(theta);
    positions.addAll([radius * cos, 0, radius * sin]);
    normals.addAll([0, 1, 0]);
    texCoords.addAll([0.5 + 0.5 * cos, 0.5 + 0.5 * sin]);
  }
  final indices = <int>[];
  for (var s = 0; s < segments; s++) {
    // Wound so the lit surface faces +Y (front face opposite +Y normal).
    indices.addAll([0, 1 + s, 1 + s + 1]);
  }

  return (
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(texCoords),
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for a [RingGeometry], a flat annulus in the
/// XZ plane facing +Y.
PrimitiveArrays buildRingArrays({
  required double innerRadius,
  required double outerRadius,
  required int segments,
}) {
  if (segments < 3) {
    throw ArgumentError('A ring needs at least three segments');
  }
  if (innerRadius < 0 || outerRadius <= 0) {
    throw ArgumentError('A ring needs a positive outer radius');
  }
  if (innerRadius >= outerRadius) {
    throw ArgumentError('A ring needs innerRadius < outerRadius');
  }

  final positions = <double>[];
  final normals = <double>[];
  final texCoords = <double>[];
  // Outer rim first (indices 0..segments), then inner rim.
  for (var s = 0; s <= segments; s++) {
    final theta = 2 * math.pi * s / segments;
    positions.addAll([
      outerRadius * math.cos(theta),
      0,
      outerRadius * math.sin(theta),
    ]);
    normals.addAll([0, 1, 0]);
    texCoords.addAll([s / segments, 1]);
  }
  final innerBase = segments + 1;
  for (var s = 0; s <= segments; s++) {
    final theta = 2 * math.pi * s / segments;
    positions.addAll([
      innerRadius * math.cos(theta),
      0,
      innerRadius * math.sin(theta),
    ]);
    normals.addAll([0, 1, 0]);
    texCoords.addAll([s / segments, 0]);
  }
  final indices = <int>[];
  for (var s = 0; s < segments; s++) {
    final o0 = s;
    final o1 = s + 1;
    final i0 = innerBase + s;
    final i1 = innerBase + s + 1;
    // Wound so the lit surface faces +Y.
    indices
      ..addAll([o0, o1, i1])
      ..addAll([o0, i1, i0]);
  }

  return (
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(texCoords),
    colors: null,
    indices: indices,
  );
}

/// Generates the vertex arrays for an [IcosphereGeometry] by subdividing
/// an icosahedron [subdivisions] times and projecting onto the sphere.
PrimitiveArrays buildIcosphereArrays({
  required double radius,
  required int subdivisions,
}) {
  if (subdivisions < 0) {
    throw ArgumentError('Icosphere subdivisions cannot be negative');
  }
  if (radius <= 0) {
    throw ArgumentError('An icosphere needs a positive radius');
  }

  final t = (1 + math.sqrt(5)) / 2;
  final verts = <Vector3>[
    Vector3(-1, t, 0),
    Vector3(1, t, 0),
    Vector3(-1, -t, 0),
    Vector3(1, -t, 0),
    Vector3(0, -1, t),
    Vector3(0, 1, t),
    Vector3(0, -1, -t),
    Vector3(0, 1, -t),
    Vector3(t, 0, -1),
    Vector3(t, 0, 1),
    Vector3(-t, 0, -1),
    Vector3(-t, 0, 1),
  ];
  // Faces wound so the outward normal opposes the right-hand normal (the
  // engine's front-face convention), i.e. clockwise seen from outside.
  var faces = <List<int>>[
    [0, 5, 11],
    [0, 1, 5],
    [0, 7, 1],
    [0, 10, 7],
    [0, 11, 10],
    [1, 9, 5],
    [5, 4, 11],
    [11, 2, 10],
    [10, 6, 7],
    [7, 8, 1],
    [3, 4, 9],
    [3, 2, 4],
    [3, 6, 2],
    [3, 8, 6],
    [3, 9, 8],
    [4, 5, 9],
    [2, 11, 4],
    [6, 10, 2],
    [8, 7, 6],
    [9, 1, 8],
  ];

  // Midpoint cache: each subdivided edge contributes one shared vertex.
  // The key is the edge's endpoint pair (low, high) so an edge shared by
  // two faces yields a single welded midpoint.
  final midpointCache = <({int low, int high}), int>{};
  int midpoint(int a, int b) {
    final key = (low: math.min(a, b), high: math.max(a, b));
    final cached = midpointCache[key];
    if (cached != null) return cached;
    final index = verts.length;
    verts.add((verts[a] + verts[b]) * 0.5);
    midpointCache[key] = index;
    return index;
  }

  for (var i = 0; i < subdivisions; i++) {
    final next = <List<int>>[];
    for (final f in faces) {
      final a = f[0];
      final b = f[1];
      final c = f[2];
      final ab = midpoint(a, b);
      final bc = midpoint(b, c);
      final ca = midpoint(c, a);
      next
        ..add([a, ab, ca])
        ..add([b, bc, ab])
        ..add([c, ca, bc])
        ..add([ab, bc, ca]);
    }
    faces = next;
  }

  final positions = Float32List(verts.length * 3);
  final normals = Float32List(verts.length * 3);
  final texCoords = Float32List(verts.length * 2);
  for (var i = 0; i < verts.length; i++) {
    final n = verts[i].normalized();
    positions[i * 3] = radius * n.x;
    positions[i * 3 + 1] = radius * n.y;
    positions[i * 3 + 2] = radius * n.z;
    normals[i * 3] = n.x;
    normals[i * 3 + 1] = n.y;
    normals[i * 3 + 2] = n.z;
    // TODO(icosphere-uv): spherical mapping leaves a seam where longitude
    // wraps and distorts near the poles; emit per-face UVs to remove it.
    texCoords[i * 2] = 0.5 + math.atan2(n.z, n.x) / (2 * math.pi);
    texCoords[i * 2 + 1] = 0.5 - math.asin(n.y) / math.pi;
  }
  final indices = <int>[];
  for (final f in faces) {
    indices.addAll(f);
  }

  return (
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: null,
    indices: indices,
  );
}

/// The collision [Shape] for a [CuboidGeometry] of full [extents]: a box of
/// half those extents, since [BoxShape] is specified by half-extents.
Shape cuboidCollisionShape(Vector3 extents) =>
    BoxShape(halfExtents: extents * 0.5);

/// The collision [Shape] for a [WedgeGeometry] of `(width, height, run)`
/// [size]: the convex hull of its six corners.
Shape wedgeCollisionShape(Vector3 size) {
  final hx = size.x / 2;
  final hz = size.z / 2;
  final y = size.y;
  return ConvexHullShape(
    points: Float32List.fromList(<double>[
      -hx, 0, -hz, // low edge, -Z
      hx, 0, -hz,
      -hx, 0, hz, // back-bottom, +Z
      hx, 0, hz,
      -hx, y, hz, // back-top, +Z
      hx, y, hz,
    ]),
  );
}

/// The collision [Shape] for a [CapsuleGeometry]: a capsule whose
/// [CapsuleShape.halfHeight] is half the cylindrical mid-section [height]
/// (excluding the caps), matching the geometry's height convention.
Shape capsuleCollisionShape({required double radius, required double height}) =>
    CapsuleShape(radius: radius, halfHeight: height / 2);

/// The collision [Shape] for a [CylinderGeometry]. Equal radii map to a
/// [CylinderShape]; a cone or truncated cone maps to the convex hull of its
/// two end rings sampled with [radialSegments] points (a zero-radius end
/// collapses to its apex point), since there is no analytic cone shape.
Shape cylinderCollisionShape({
  required double bottomRadius,
  required double topRadius,
  required double height,
  required int radialSegments,
}) {
  if (bottomRadius == topRadius) {
    return CylinderShape(radius: bottomRadius, halfHeight: height / 2);
  }
  final points = <double>[];
  void ring(double radius, double y) {
    if (radius <= 0) {
      points.addAll([0, y, 0]);
      return;
    }
    for (var s = 0; s < radialSegments; s++) {
      final theta = 2 * math.pi * s / radialSegments;
      points.addAll([radius * math.cos(theta), y, radius * math.sin(theta)]);
    }
  }

  ring(bottomRadius, -height / 2);
  ring(topRadius, height / 2);
  return ConvexHullShape(points: Float32List.fromList(points));
}

// A flat shape (disc, ring) has no real thickness, so its collision hull is
// extruded to this fraction of its radius along Y, both to give a convex
// hull a valid (non-degenerate) volume and so a dropped disc behaves like a
// thin coin rather than an infinitely thin sheet.
const double _kFlatCollisionHalfThickness = 0.05;

/// The collision [Shape] for a [TorusGeometry]: a [CompoundShape] of
/// [segments] convex chunks swept around the ring, each the convex hull of
/// two adjacent tube cross-sections sampled with [tubularSegments] points.
/// The chunks leave the central hole open, which a single convex hull would
/// fill. The collision tessellation is intentionally coarser than a render
/// mesh.
Shape torusCollisionShape({
  required double radius,
  required double tubeRadius,
  int segments = 16,
  int tubularSegments = 8,
}) {
  final children = <CompoundChild>[];
  for (var i = 0; i < segments; i++) {
    final points = <double>[];
    for (final u in [
      2 * math.pi * i / segments,
      2 * math.pi * (i + 1) / segments,
    ]) {
      final cosU = math.cos(u);
      final sinU = math.sin(u);
      for (var j = 0; j < tubularSegments; j++) {
        final v = 2 * math.pi * j / tubularSegments;
        final ringRadius = radius + tubeRadius * math.cos(v);
        points.addAll([
          ringRadius * cosU,
          tubeRadius * math.sin(v),
          ringRadius * sinU,
        ]);
      }
    }
    children.add(
      CompoundChild(
        shape: ConvexHullShape(points: Float32List.fromList(points)),
        localPose: Matrix4.identity(),
      ),
    );
  }
  return CompoundShape(children: children);
}

/// The collision [Shape] for a [DiscGeometry]: a thin [CylinderShape] (a
/// coin), since a flat disc has no volume. The thickness is a small
/// fraction of the [radius].
Shape discCollisionShape({required double radius}) => CylinderShape(
  radius: radius,
  halfHeight: radius * _kFlatCollisionHalfThickness,
);

/// The collision [Shape] for a [RingGeometry]: a [CompoundShape] of
/// [segments] thin convex segments around the annulus, leaving the hole
/// open. Each segment is extruded to a small thickness so it forms a valid
/// (non-degenerate) 3D hull.
Shape ringCollisionShape({
  required double innerRadius,
  required double outerRadius,
  int segments = 16,
}) {
  final halfThickness = outerRadius * _kFlatCollisionHalfThickness;
  final children = <CompoundChild>[];
  for (var i = 0; i < segments; i++) {
    final points = <double>[];
    for (final a in [
      2 * math.pi * i / segments,
      2 * math.pi * (i + 1) / segments,
    ]) {
      final cosA = math.cos(a);
      final sinA = math.sin(a);
      for (final r in [innerRadius, outerRadius]) {
        points
          ..addAll([r * cosA, halfThickness, r * sinA])
          ..addAll([r * cosA, -halfThickness, r * sinA]);
      }
    }
    children.add(
      CompoundChild(
        shape: ConvexHullShape(points: Float32List.fromList(points)),
        localPose: Matrix4.identity(),
      ),
    );
  }
  return CompoundShape(children: children);
}
