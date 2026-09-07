/// Tile and grid maps: cell coordinates, world placement, per-cell storage,
/// and pathfinding, for square and hexagonal tilings.
///
/// A [Grid] is the map between integer cell addresses and world positions, and
/// the rest of the library is written against it rather than against a
/// particular tiling. Swapping [SquareGrid] for [HexGrid] changes how a game
/// looks and feels without changing the code that places buildings, measures
/// range, or finds routes.
///
/// Cells lie on the world's XZ plane with Y up, matching the engine, and cell
/// `(0, 0)` is centred on the grid's origin.
///
/// * [GridCoord] and [GridRect] address cells and blocks of cells.
/// * [SquareGrid] and [HexGrid] place them in the world.
/// * [GridMap] stores what is on each one.
/// * [findGridPath] routes between them over a cost function you supply.
///
/// This is the tiling itself, not the drawing of it: `package:flutter_scene`
/// adds picking a cell from a click and rendering tiles.
///
/// There is no isometric grid, because isometric is a camera rather than a
/// tiling: use a [SquareGrid] with an isometric camera.
///
/// Pure Dart, optional; import it only when a build needs a grid.
library;

export 'src/grid/grid.dart' show Grid;
export 'src/grid/grid_coord.dart' show GridCoord, GridRect;
export 'src/grid/grid_map.dart' show GridMap;
export 'src/grid/grid_path.dart' show GridPath, findGridPath;
export 'src/grid/hex_grid.dart' show HexGrid, HexOrientation;
export 'src/grid/square_grid.dart' show SquareGrid;
