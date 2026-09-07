/// Drawing a baked nav mesh, so it can be looked at.
///
/// A nav mesh is the one piece of a level that is invisible by construction:
/// it is derived from the geometry, sits exactly on it, and is wrong in ways
/// that only show up as an agent walking through a wall or refusing to cross
/// a doorway. Every question about a bake -- did that ledge come out
/// walkable, did the water carve, did the tiles meet at the seam -- is
/// answered by seeing it.
///
/// The draw is scene geometry, not a screen-space overlay: a world's nav mesh
/// is tens of thousands of triangles, and projecting those on the CPU every
/// frame would cost more than the scene it is drawn over. Built once per
/// bake, it costs a draw call.
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/line_segments_geometry.dart';
import 'package:flutter_scene/src/geometry/mesh_data.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart'
    show AlphaMode;
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:scene/navigation.dart';
import 'package:vector_math/vector_math.dart';

/// The colours a nav mesh draws in, by area.
///
/// Linear RGBA, matching the engine's colour convention. Alpha is what makes
/// the mesh readable over the level it covers: opaque, it hides the thing it
/// is describing.
/// {@category Navigation}
class NavDebugPalette {
  const NavDebugPalette({
    this.walkable = const Color4(0.16, 0.55, 0.95, 0.45),
    this.slow = const Color4(0.20, 0.72, 0.62, 0.45),
    this.door = const Color4(0.95, 0.66, 0.16, 0.55),
    this.other = const Color4(0.65, 0.40, 0.85, 0.45),
    this.outline = const Color4(0.06, 0.14, 0.24, 0.9),
  });

  /// [NavArea.walkable].
  final Color4 walkable;

  /// [NavArea.slow]: water, undergrowth, rubble.
  final Color4 slow;

  /// [NavArea.door]: a door, ladder, or jump-down.
  final Color4 door;

  /// Any other area value, which is a project's own.
  final Color4 other;

  /// The polygon edges.
  final Color4 outline;

  /// The colour for [area].
  Color4 colorFor(int area) => switch (area) {
    NavArea.walkable => walkable,
    NavArea.slow => slow,
    NavArea.door => door,
    _ => other,
  };
}

/// A linear RGBA colour, as a const-constructible quadruple.
///
/// [Vector4] cannot be const, and a palette that has to be built at runtime
/// cannot be a default argument.
/// {@category Navigation}
class Color4 {
  const Color4(this.r, this.g, this.b, this.a);

  final double r;
  final double g;
  final double b;
  final double a;

  Vector4 toVector4() => Vector4(r, g, b, a);
}

/// A nav mesh's polygons as a drawable triangle soup: positions, per-vertex
/// colours, and the bounds they span.
///
/// Pure and GPU-free, so it can be built on a worker isolate alongside the
/// bake and uploaded on the render isolate.
/// {@category Navigation}
class NavDebugGeometry {
  NavDebugGeometry({
    required this.positions,
    required this.colors,
    required this.outline,
    required this.bounds,
  });

  /// Triangle-list positions, three floats per vertex.
  final Float32List positions;

  /// Per-vertex linear RGBA, four floats per vertex.
  final Float32List colors;

  /// Polygon edges as segment endpoints, six floats per segment.
  final Float32List outline;

  /// The AABB the positions span, so the upload skips a second scan.
  final Aabb3 bounds;

  int get triangleCount => positions.length ~/ 9;

  bool get isEmpty => positions.isEmpty;
}

/// Builds the drawable form of [mesh].
///
/// [lift] raises everything off the floor: a nav mesh sits exactly on the
/// ground it was baked from, and drawn in place it z-fights every pixel.
///
/// Nav polygons are convex, so each fans from its first corner. The fill is
/// unindexed because neighbouring polygons share vertices but not areas, and
/// an index buffer would force one colour on both.
/// {@category Navigation}
NavDebugGeometry buildNavDebugGeometry(
  NavMesh mesh, {
  NavDebugPalette palette = const NavDebugPalette(),
  double lift = 0.05,
  Vector4? tint,
}) {
  // Count first so every array is allocated once at its final size: a world's
  // mesh is hundreds of thousands of floats, and growing them is the whole
  // cost of this function.
  var triangles = 0;
  var edges = 0;
  for (var poly = 0; poly < mesh.polygonCount; poly++) {
    final corners = mesh.vertexCountOf(poly);
    if (corners < 3) continue;
    triangles += corners - 2;
    edges += corners;
  }

  final positions = Float32List(triangles * 9);
  final colors = Float32List(triangles * 12);
  final outline = Float32List(edges * 6);
  final vertices = mesh.vertices;

  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  var p = 0;
  var c = 0;
  var e = 0;

  for (var poly = 0; poly < mesh.polygonCount; poly++) {
    final corners = mesh.vertexCountOf(poly);
    if (corners < 3) continue;
    final base = palette.colorFor(mesh.areas[poly]);
    final r = tint == null ? base.r : base.r * tint.r;
    final g = tint == null ? base.g : base.g * tint.g;
    final b = tint == null ? base.b : base.b * tint.b;
    final a = tint == null ? base.a : base.a * tint.a;

    final first = mesh.vertexOf(poly, 0) * 3;
    final fx = vertices[first];
    final fy = vertices[first + 1] + lift;
    final fz = vertices[first + 2];

    for (var corner = 1; corner < corners - 1; corner++) {
      final second = mesh.vertexOf(poly, corner) * 3;
      final third = mesh.vertexOf(poly, corner + 1) * 3;
      positions[p++] = fx;
      positions[p++] = fy;
      positions[p++] = fz;
      positions[p++] = vertices[second];
      positions[p++] = vertices[second + 1] + lift;
      positions[p++] = vertices[second + 2];
      positions[p++] = vertices[third];
      positions[p++] = vertices[third + 1] + lift;
      positions[p++] = vertices[third + 2];
      for (var v = 0; v < 3; v++) {
        colors[c++] = r;
        colors[c++] = g;
        colors[c++] = b;
        colors[c++] = a;
      }
    }

    for (var corner = 0; corner < corners; corner++) {
      final from = mesh.vertexOf(poly, corner) * 3;
      final to = mesh.vertexOf(poly, (corner + 1) % corners) * 3;
      outline[e++] = vertices[from];
      outline[e++] = vertices[from + 1] + lift;
      outline[e++] = vertices[from + 2];
      outline[e++] = vertices[to];
      outline[e++] = vertices[to + 1] + lift;
      outline[e++] = vertices[to + 2];
    }
  }

  for (var i = 0; i < p; i += 3) {
    final x = positions[i];
    final y = positions[i + 1];
    final z = positions[i + 2];
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
  final bounds = p == 0
      ? Aabb3()
      : Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));

  return NavDebugGeometry(
    positions: positions,
    colors: colors,
    outline: outline,
    bounds: bounds,
  );
}

/// A node drawing [geometry]: a translucent fill and, when [outlineWidth] is
/// above zero, the polygon edges over it.
///
/// The node is excluded from raycasting and casts no shadows: it describes
/// the level rather than being part of it, and a debug draw that shows up in
/// a pick or a shadow map is a bug in every scene it appears in.
/// {@category Navigation}
Node navDebugNode(
  NavDebugGeometry geometry, {
  String name = 'Nav mesh',
  NavDebugPalette palette = const NavDebugPalette(),
  double outlineWidth = 0.03,
}) {
  final node = Node(name: name)
    ..raycastable = false
    ..castsShadows = false;
  if (geometry.isEmpty) return node;

  final fill = UnlitMaterial()..alphaMode = AlphaMode.blend;
  node.mesh = Mesh(
    MeshGeometry.fromArrays(
      positions: geometry.positions,
      colors: geometry.colors,
      bounds: geometry.bounds,
      retainCpuData: false,
    ),
    fill,
  );

  if (outlineWidth > 0 && geometry.outline.isNotEmpty) {
    final edges = Node(name: '$name edges')
      ..raycastable = false
      ..castsShadows = false
      ..mesh = Mesh(
        LineSegmentsGeometry(
          LineSegmentData(positions: geometry.outline),
          width: outlineWidth,
        ),
        UnlitMaterial()
          ..alphaMode = AlphaMode.blend
          ..baseColorFactor = palette.outline.toVector4()
          ..vertexColorWeight = 0,
      );
    node.add(edges);
  }
  return node;
}

/// A node drawing [mesh]. Convenience over [buildNavDebugGeometry] and
/// [navDebugNode] for a caller with no reason to do the two separately.
/// {@category Navigation}
Node navMeshDebugNode(
  NavMesh mesh, {
  String name = 'Nav mesh',
  NavDebugPalette palette = const NavDebugPalette(),
  double lift = 0.05,
  double outlineWidth = 0.03,
}) => navDebugNode(
  buildNavDebugGeometry(mesh, palette: palette, lift: lift),
  name: name,
  palette: palette,
  outlineWidth: outlineWidth,
);

/// A node drawing every tile in [tiles], one child per tile.
///
/// With [tintTiles] each tile takes a hue of its own, which is how a seam
/// that failed to link is spotted: the mesh looks continuous, and the tints
/// show where the boundary actually is.
/// {@category Navigation}
Node navTileSetDebugNode(
  NavTileSet tiles, {
  String name = 'Nav tiles',
  NavDebugPalette palette = const NavDebugPalette(),
  double lift = 0.05,
  double outlineWidth = 0.03,
  bool tintTiles = false,
}) {
  final root = Node(name: name)
    ..raycastable = false
    ..castsShadows = false;
  for (final key in tiles.tiles) {
    final mesh = tiles.tile(key);
    if (mesh == null) continue;
    root.add(
      navDebugNode(
        buildNavDebugGeometry(
          mesh,
          palette: palette,
          lift: lift,
          tint: tintTiles ? _tileTint(key) : null,
        ),
        name: '$name ${key.x},${key.z}',
        palette: palette,
        outlineWidth: outlineWidth,
      ),
    );
  }
  return root;
}

/// A stable per-tile tint. Checkerboarding alone would put the same two
/// colours on tiles that touch diagonally, so this walks a short cycle in
/// both axes instead.
Vector4 _tileTint(NavTileKey key) {
  const shades = [1.0, 0.72, 0.86, 0.58];
  final index = (key.x * 3 + key.z * 5) % shades.length;
  final shade = shades[index < 0 ? index + shades.length : index];
  return Vector4(shade, 1.0, 2.0 - shade, 1.0);
}
