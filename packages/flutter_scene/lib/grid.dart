/// Tile and grid maps for flutter_scene: the tiling itself, plus picking a
/// cell from the pointer and drawing tiles.
///
/// The tiling — [SquareGrid], [HexGrid], [GridMap], [findGridPath] — lives in
/// `package:scene/grid.dart`, engine agnostic and pure Dart, and this library
/// re-exports it alongside the pieces that need the renderer:
///
///  * [GridPicking] turns a pointer position or a ray into a cell, which is
///    what a click-to-place or click-to-move game is built on.
///  * [GridTileLayer] draws one mesh per occupied cell as a single instanced
///    batch, so a large map is a handful of draw calls.
///  * [GridDebugDraw] outlines cells, regions, and routes while building.
///
/// ```dart
/// final grid = SquareGrid(cellSize: 2.0);
///
/// // A click becomes a tile:
/// final cell = grid.cellAtScreenPoint(
///   position,
///   camera: scene.camera!,
///   viewSize: viewSize,
/// );
///
/// // ...and a route across the map:
/// final path = findGridPath(grid, unitCell, cell!, stepCost: (_, to) =>
///     terrain[to]?.blocked ?? false ? null : 1.0);
/// ```
///
/// Import this only when a build needs a grid; the core
/// `package:flutter_scene/scene.dart` does not carry it.
library;

export 'package:scene/grid.dart';

export 'src/grid/grid_picking.dart' show GridPicking;
export 'src/kit/grid/grid_tiles.dart'
    show GridDebugDraw, GridTileAppearance, GridTileLayer;
