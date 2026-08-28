import 'package:scene/grid.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/instanced_mesh_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/instanced_mesh.dart';
import 'package:flutter_scene/src/kit/debug/debug_draw.dart';
import 'package:flutter_scene/src/material/material.dart';

/// Draws one mesh once per occupied cell of a grid, as a single instanced
/// draw call.
///
/// A tile map is thousands of copies of a handful of meshes, which is exactly
/// what instancing is for: a field of ten thousand tiles costs one draw call
/// per tile *kind*, not ten thousand draws. This component owns that batch and
/// keeps it in step with the cells you [set] and [remove].
///
/// One layer draws one mesh. A map with grass, water, and rock is three
/// layers, each a node of its own, which is also how their materials stay
/// separate.
///
/// ```dart
/// final grass = GridTileLayer(
///   grid: grid,
///   geometry: CuboidGeometry(Vector3(2, 0.2, 2)),
///   material: grassMaterial,
/// );
/// scene.add(Node()..addComponent(grass));
///
/// for (final cell in grid.cellsWithin(GridCoord.origin, 20)) {
///   grass.set(cell);
/// }
/// ```
///
/// Per-cell variation that does not need a different mesh — a tint, a height,
/// a rotation — goes through [set]'s arguments rather than through a second
/// layer, since it costs nothing extra in the batch.
/// {@category Gameplay kit}
class GridTileLayer extends Component {
  /// Creates a layer drawing [geometry] shaded by [material] on [grid].
  ///
  /// [cullTiles] tests each tile against the view separately. Leave it off for
  /// a small map, where one test against the whole batch is cheaper; turn it
  /// on for a large one, where most tiles are off screen at any moment.
  GridTileLayer({
    required this.grid,
    required Geometry geometry,
    required Material material,
    bool cullTiles = true,
  }) : _mesh = InstancedMesh(
         geometry: geometry,
         material: material,
         cullInstances: cullTiles,
       );

  /// The grid this layer places tiles on.
  Grid grid;

  final InstancedMesh _mesh;

  // Cell to instance index. The instance list is dense and stays that way:
  // removing a tile moves the last instance into the hole, so the batch never
  // accumulates gaps, and this map is repaired for the one tile that moved.
  final Map<GridCoord, int> _indexOf = <GridCoord, int>{};
  final List<GridCoord> _cellAt = <GridCoord>[];

  // What each tile was placed with, kept because the instance batch stores
  // only the composed matrix. Without it [rebuild] could not put a tile back
  // the way it was, and a layer could not be written to a document.
  final Map<GridCoord, GridTileAppearance> _look =
      <GridCoord, GridTileAppearance>{};

  InstancedMeshComponent? _drawer;

  /// The instanced mesh behind this layer, for material changes and for
  /// anything the layer does not wrap.
  InstancedMesh get mesh => _mesh;

  /// How many tiles are placed.
  int get length => _cellAt.length;

  /// Whether the layer has no tiles.
  bool get isEmpty => _cellAt.isEmpty;

  /// The cells that have a tile.
  Iterable<GridCoord> get cells => _indexOf.keys;

  /// Whether [cell] has a tile in this layer.
  bool contains(GridCoord cell) => _indexOf.containsKey(cell);

  /// Places (or updates) a tile on [cell].
  ///
  /// [height] lifts the tile above the grid plane, [yaw] turns it about its
  /// own centre, [scale] resizes it, and [color] tints it. Calling [set] again
  /// on an occupied cell replaces the tile there rather than stacking a second
  /// one on it.
  void set(
    GridCoord cell, {
    double height = 0.0,
    double yaw = 0.0,
    Vector3? scale,
    Vector4? color,
  }) {
    final center = grid.center(cell);
    final transform = Matrix4.compose(
      Vector3(center.x, center.y + height, center.z),
      Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yaw),
      scale ?? Vector3(1.0, 1.0, 1.0),
    );

    _look[cell] = GridTileAppearance(
      height: height,
      yaw: yaw,
      scale: scale?.clone(),
      color: color?.clone(),
    );

    final existing = _indexOf[cell];
    if (existing != null) {
      _mesh.setInstanceTransform(existing, transform);
      if (color != null) _mesh.setInstanceColor(existing, color);
      return;
    }
    _indexOf[cell] = _mesh.addInstance(transform, color: color);
    _cellAt.add(cell);
  }

  /// Places a tile on every cell of [region].
  void fill(GridRect region, {double height = 0.0, Vector4? color}) {
    for (final cell in region.cells) {
      set(cell, height: height, color: color);
    }
  }

  /// Places a tile on every cell [source] holds a value for, asking [build]
  /// for that tile's appearance.
  ///
  /// This is the bridge from game state to what is drawn: keep the truth in a
  /// [GridMap] and re-run this when it changes.
  void fillFrom<T>(
    GridMap<T> source, {
    GridTileAppearance Function(GridCoord cell, T value)? build,
  }) {
    source.forEach((cell, value) {
      final look = build?.call(cell, value) ?? const GridTileAppearance();
      set(
        cell,
        height: look.height,
        yaw: look.yaw,
        scale: look.scale,
        color: look.color,
      );
    });
  }

  /// Removes the tile on [cell]. Returns whether there was one.
  bool remove(GridCoord cell) {
    final index = _indexOf.remove(cell);
    if (index == null) return false;
    _look.remove(cell);

    // Swap-remove keeps the instance list dense, so the batch never carries
    // holes. Only the tile that moved needs its index repaired.
    final lastIndex = _cellAt.length - 1;
    if (index != lastIndex) {
      final moved = _cellAt[lastIndex];
      _cellAt[index] = moved;
      _indexOf[moved] = index;
    }
    _cellAt.removeLast();
    _mesh.removeInstanceAt(index);
    return true;
  }

  /// Removes every tile.
  void clear() {
    _indexOf.clear();
    _cellAt.clear();
    _look.clear();
    _mesh.clearInstances();
  }

  /// Re-places every tile at its cell's current world position.
  ///
  /// Call after changing [grid] (a different cell size, a moved origin) so the
  /// tiles follow it.
  void rebuild() {
    for (var i = 0; i < _cellAt.length; i++) {
      final cell = _cellAt[i];
      final center = grid.center(cell);
      final look = _look[cell] ?? const GridTileAppearance();
      _mesh.setInstanceTransform(
        i,
        Matrix4.compose(
          Vector3(center.x, center.y + look.height, center.z),
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), look.yaw),
          look.scale ?? Vector3(1.0, 1.0, 1.0),
        ),
      );
    }
  }

  /// How the tile on [cell] was placed, or null when the cell is empty.
  GridTileAppearance? appearanceOf(GridCoord cell) => _look[cell];

  /// Every tile with the appearance it was placed with, in no particular
  /// order. This is what a layer serializes.
  Iterable<({GridCoord cell, GridTileAppearance look})> get tiles =>
      _cellAt.map(
        (cell) => (cell: cell, look: _look[cell] ?? const GridTileAppearance()),
      );

  @override
  void onAttach() {
    _drawer = InstancedMeshComponent(_mesh);
    node.addComponent(_drawer!);
  }

  @override
  void onDetach() {
    final drawer = _drawer;
    if (drawer != null) {
      node.removeComponent(drawer);
      _drawer = null;
    }
  }
}

/// How one tile looks, for [GridTileLayer.fillFrom].
class GridTileAppearance {
  /// Describes a tile.
  const GridTileAppearance({
    this.height = 0.0,
    this.yaw = 0.0,
    this.scale,
    this.color,
  });

  /// Lift above the grid plane, in world units.
  final double height;

  /// Rotation about the tile's own vertical axis, in radians.
  final double yaw;

  /// Per-tile scale, or null for none.
  final Vector3? scale;

  /// Per-tile tint, or null for the material's own colour.
  final Vector4? color;
}

/// Drawing a grid's own geometry, for laying out a level and for debugging.
/// {@category Gameplay kit}
extension GridDebugDraw on Grid {
  /// Outlines [cell] on the grid plane.
  ///
  /// Immediate mode, like the rest of [DebugDraw]: call it every frame for as
  /// long as the outline should be visible.
  void debugDrawCell(GridCoord cell, {Vector4? color}) {
    final points = corners(cell);
    for (var i = 0; i < points.length; i++) {
      DebugDraw.line(points[i], points[(i + 1) % points.length], color: color);
    }
  }

  /// Outlines every cell of [region].
  ///
  /// Draws one line loop per cell, so a large region is a lot of lines; keep
  /// it to the part of the map in view.
  void debugDrawRegion(GridRect region, {Vector4? color}) {
    for (final cell in region.cells) {
      debugDrawCell(cell, color: color);
    }
  }

  /// Draws a route as a line through the centres of its cells, lifted
  /// [height] above the plane so it reads over the tiles.
  void debugDrawPath(
    List<GridCoord> cells, {
    Vector4? color,
    double height = 0.05,
  }) {
    final lift = Vector3(0.0, height, 0.0);
    for (var i = 1; i < cells.length; i++) {
      DebugDraw.line(
        center(cells[i - 1]) + lift,
        center(cells[i]) + lift,
        color: color,
      );
    }
  }
}
