import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// Flags marking what an area of the nav mesh is, carried from the source
/// triangles through the bake and out into the polygons.
///
/// [nonWalkable] is the absence of a surface; everything else is a surface
/// the agent may cross, and a query weights them through a cost. The named
/// values are conventions, not a closed set: any value in `1..63` is yours.
abstract final class NavArea {
  /// Not walkable at all. The voxelizer assigns this to anything too steep,
  /// and the filters to anything without headroom.
  static const int nonWalkable = 0;

  /// Ordinary ground.
  static const int walkable = 63;

  /// Water, undergrowth, rubble: crossable, but a path should prefer not to.
  static const int slow = 32;

  /// A door, ladder, or jump-down: crossable, and worth marking so an agent
  /// can play the right animation when it gets there.
  static const int door = 16;

  /// The highest value an area may take. Areas are packed into six bits
  /// alongside the span heights.
  static const int max = 63;
}

/// Triangles for a nav mesh bake, in world space.
///
/// This is deliberately a flat triangle soup rather than a scene graph: the
/// baker runs in pure Dart, in an editor or on a server, and should not need
/// to know what a renderer's mesh or a physics engine's collider looks like.
/// The callers that do know convert into this.
class NavGeometry {
  NavGeometry({required this.vertices, required this.indices, Uint8List? areas})
    : areas = areas ?? Uint8List(indices.length ~/ 3),
      assert(vertices.length % 3 == 0),
      assert(indices.length % 3 == 0),
      assert(areas == null || areas.length == indices.length ~/ 3);

  /// Vertex positions, three doubles per vertex, in world space.
  final Float32List vertices;

  /// Triangle indices into [vertices], three per triangle.
  final Uint32List indices;

  /// Per-triangle [NavArea]. Zero means "decide from the slope", which is what
  /// most geometry wants; a non-zero value overrides that, so a caller can
  /// paint water or a door onto specific triangles.
  final Uint8List areas;

  int get triangleCount => indices.length ~/ 3;

  /// The axis-aligned bounds of every vertex, or null when there are none.
  (Vector3, Vector3)? get bounds {
    if (vertices.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (var i = 0; i < vertices.length; i += 3) {
      final x = vertices[i], y = vertices[i + 1], z = vertices[i + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return (Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }
}

/// Accumulates world-space triangles from several sources into one
/// [NavGeometry].
///
/// The engine-side helpers that walk a scene graph, and the physics-side ones
/// that walk colliders, both funnel through this, so a bake can mix a
/// rendered floor, a collider-only ramp, and a hand-authored blocker without
/// any of them knowing about the others.
class NavGeometryBuilder {
  final List<double> _vertices = [];
  final List<int> _indices = [];
  final List<int> _areas = [];

  int get triangleCount => _areas.length;

  /// Appends a mesh, transforming it into world space by [transform].
  ///
  /// [positions] is three doubles per vertex and [triangleIndices] three ints
  /// per triangle. [area] overrides the slope test for every triangle added
  /// here; leave it at [NavArea.nonWalkable] to let the slope decide.
  void addMesh({
    required List<double> positions,
    required List<int> triangleIndices,
    Matrix4? transform,
    int area = NavArea.nonWalkable,
  }) {
    assert(positions.length % 3 == 0);
    assert(triangleIndices.length % 3 == 0);
    assert(area >= 0 && area <= NavArea.max);
    final base = _vertices.length ~/ 3;
    if (transform == null) {
      _vertices.addAll(positions);
    } else {
      final m = transform.storage;
      for (var i = 0; i < positions.length; i += 3) {
        final x = positions[i], y = positions[i + 1], z = positions[i + 2];
        _vertices
          ..add(m[0] * x + m[4] * y + m[8] * z + m[12])
          ..add(m[1] * x + m[5] * y + m[9] * z + m[13])
          ..add(m[2] * x + m[6] * y + m[10] * z + m[14]);
      }
    }
    for (final index in triangleIndices) {
      _indices.add(base + index);
    }
    for (var i = 0; i < triangleIndices.length ~/ 3; i++) {
      _areas.add(area);
    }
  }

  /// Appends an axis-aligned box, the quickest way to block a doorway or mark
  /// a region by hand without authoring a mesh.
  void addBox(Vector3 min, Vector3 max, {int area = NavArea.nonWalkable}) {
    addMesh(
      positions: [
        min.x, min.y, min.z, max.x, min.y, min.z, //
        max.x, min.y, max.z, min.x, min.y, max.z, //
        min.x, max.y, min.z, max.x, max.y, min.z, //
        max.x, max.y, max.z, min.x, max.y, max.z,
      ],
      triangleIndices: const [
        0, 2, 1, 0, 3, 2, // bottom
        4, 5, 6, 4, 6, 7, // top
        0, 1, 5, 0, 5, 4, // -Z
        1, 2, 6, 1, 6, 5, // +X
        2, 3, 7, 2, 7, 6, // +Z
        3, 0, 4, 3, 4, 7, // -X
      ],
      area: area,
    );
  }

  NavGeometry build() => NavGeometry(
    vertices: Float32List.fromList(_vertices),
    indices: Uint32List.fromList(_indices),
    areas: Uint8List.fromList(_areas),
  );
}
