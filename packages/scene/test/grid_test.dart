// Covers the grid library: square and hex tilings round-trip between cells and
// world positions, measure distance the way their topology demands, and A*
// routes over a caller-supplied cost function.

import 'dart:math' as math;

import 'package:scene/grid.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('GridCoord', () {
    test('is a value', () {
      expect(const GridCoord(2, -3), const GridCoord(2, -3));
      expect(const GridCoord(2, -3).hashCode, const GridCoord(2, -3).hashCode);
      expect(
        <GridCoord, int>{const GridCoord(1, 1): 7}[const GridCoord(1, 1)],
        7,
      );
    });

    test('does arithmetic', () {
      expect(
        const GridCoord(1, 2) + const GridCoord(3, 4),
        const GridCoord(4, 6),
      );
      expect(
        const GridCoord(5, 5) - const GridCoord(1, 2),
        const GridCoord(4, 3),
      );
      expect(const GridCoord(2, -1) * 3, const GridCoord(6, -3));
      expect(-const GridCoord(2, -1), const GridCoord(-2, 1));
    });

    test('the three cube coordinates sum to zero', () {
      const cell = GridCoord(3, -5);
      expect(cell.x + cell.y + cell.z, 0);
    });
  });

  group('GridRect', () {
    test('measures and iterates', () {
      final rect = GridRect.sized(const GridCoord(-1, -1), 3, 2);
      expect(rect.width, 3);
      expect(rect.height, 2);
      expect(rect.length, 6);
      expect(rect.cells.length, 6);
      expect(rect.contains(const GridCoord(1, 0)), isTrue);
      expect(rect.contains(const GridCoord(2, 0)), isFalse);
    });

    test('bounds a set of cells', () {
      final rect = GridRect.bounding(const [
        GridCoord(4, 1),
        GridCoord(-2, 7),
        GridCoord(0, 0),
      ]);
      expect(rect!.min, const GridCoord(-2, 0));
      expect(rect.max, const GridCoord(4, 7));
      expect(GridRect.bounding(const <GridCoord>[]), isNull);
    });

    test('clamps and expands', () {
      final rect = GridRect(const GridCoord(0, 0), const GridCoord(4, 4));
      expect(rect.clamp(const GridCoord(9, -3)), const GridCoord(4, 0));
      expect(rect.expanded(2).min, const GridCoord(-2, -2));
    });
  });

  group('SquareGrid', () {
    const grid = SquareGrid(cellSize: 2.0);

    test('centres cell (0, 0) on the origin', () {
      expect(grid.center(GridCoord.origin).x, closeTo(0.0, 1e-9));
      expect(grid.center(GridCoord.origin).z, closeTo(0.0, 1e-9));
      expect(grid.center(const GridCoord(2, -1)).x, closeTo(4.0, 1e-9));
      expect(grid.center(const GridCoord(2, -1)).z, closeTo(-2.0, 1e-9));
    });

    test('round-trips every cell through world space', () {
      for (var x = -5; x <= 5; x++) {
        for (var y = -5; y <= 5; y++) {
          final cell = GridCoord(x, y);
          expect(grid.cellAt(grid.center(cell)), cell);
        }
      }
    });

    test('assigns a point to the cell it falls in, not the nearest corner', () {
      // Cell (0,0) spans -1..1 with cellSize 2.
      expect(grid.cellAtXZ(0.9, -0.9), GridCoord.origin);
      expect(grid.cellAtXZ(1.1, 0.0), const GridCoord(1, 0));
    });

    test('honours an offset origin and elevation', () {
      const shifted = SquareGrid(
        cellSize: 1.0,
        origin: (x: 10.0, z: -4.0),
        elevation: 3.0,
      );
      final middle = shifted.center(const GridCoord(1, 1));
      expect(middle.x, closeTo(11.0, 1e-9));
      expect(middle.y, closeTo(3.0, 1e-9));
      expect(middle.z, closeTo(-3.0, 1e-9));
      expect(shifted.cellAt(middle), const GridCoord(1, 1));
    });

    test('measures Manhattan distance without diagonals', () {
      expect(grid.neighborCount, 4);
      expect(grid.distance(GridCoord.origin, const GridCoord(3, 4)), 7);
      expect(grid.neighborsOf(GridCoord.origin).length, 4);
    });

    test('measures Chebyshev distance with diagonals', () {
      const diagonal = SquareGrid(cellSize: 1.0, allowDiagonals: true);
      expect(diagonal.neighborCount, 8);
      expect(diagonal.distance(GridCoord.origin, const GridCoord(3, 4)), 4);
      expect(diagonal.neighborsOf(GridCoord.origin).length, 8);
    });

    test('cellsWithin is a diamond without diagonals, a square with', () {
      expect(grid.cellsWithin(GridCoord.origin, 1).length, 5);
      const diagonal = SquareGrid(cellSize: 1.0, allowDiagonals: true);
      expect(diagonal.cellsWithin(GridCoord.origin, 1).length, 9);
    });

    test('ring returns exactly the cells at that distance', () {
      final ring = grid.ring(GridCoord.origin, 2).toList();
      expect(ring.length, 8);
      for (final cell in ring) {
        expect(grid.distance(GridCoord.origin, cell), 2);
      }
      expect(grid.ring(GridCoord.origin, 0).toList(), [GridCoord.origin]);
    });

    test('corners outline the cell', () {
      final corners = grid.corners(GridCoord.origin);
      expect(corners.length, 4);
      for (final corner in corners) {
        expect(corner.x.abs(), closeTo(1.0, 1e-9));
        expect(corner.z.abs(), closeTo(1.0, 1e-9));
        expect(corner.y, closeTo(0.0, 1e-9));
      }
    });

    test('snap puts a world point on the cell centre', () {
      final snapped = grid.snap(Vector3(3.7, 12.0, -0.4));
      expect(snapped.x, closeTo(4.0, 1e-9));
      expect(snapped.z, closeTo(0.0, 1e-9));
      expect(snapped.y, closeTo(0.0, 1e-9));
    });

    test('lineTo walks a connected run of cells', () {
      final line = grid.lineTo(GridCoord.origin, const GridCoord(4, 2));
      expect(line.first, GridCoord.origin);
      expect(line.last, const GridCoord(4, 2));
      for (var i = 1; i < line.length; i++) {
        expect(grid.distance(line[i - 1], line[i]), lessThanOrEqualTo(2));
      }
    });

    test('cellsInXZRect covers a drag selection', () {
      final rect = grid.cellsInXZRect(-2.5, -0.5, 4.5, 4.5);
      expect(rect.contains(GridCoord.origin), isTrue);
      expect(rect.contains(const GridCoord(2, 2)), isTrue);
      expect(rect.contains(const GridCoord(3, 0)), isFalse);
    });
  });

  group('HexGrid', () {
    const grid = HexGrid(cellSize: 1.0);

    test('round-trips every cell through world space', () {
      for (final orientation in HexOrientation.values) {
        final hex = HexGrid(cellSize: 1.5, orientation: orientation);
        for (var q = -6; q <= 6; q++) {
          for (var r = -6; r <= 6; r++) {
            final cell = GridCoord(q, r);
            expect(
              hex.cellAt(hex.center(cell)),
              cell,
              reason: '$orientation $cell',
            );
          }
        }
      }
    });

    test('rounds a point near a corner into the right hexagon', () {
      // Rounding each axial coordinate on its own lands in the wrong cell near
      // the corners; the cube repair in _roundAxial is what keeps it correct.
      // Every sample here is inside the hexagon: the inradius bounds what is
      // safe in an arbitrary direction, while a point 95% of the way out along
      // a corner direction is inside too, and is exactly where naive rounding
      // goes wrong.
      final inradius = grid.cellWidth / 2;
      for (var i = 0; i < 360; i++) {
        final angle = i / 360 * math.pi * 2;
        final point = Vector3(
          math.cos(angle) * inradius * 0.99,
          0.0,
          math.sin(angle) * inradius * 0.99,
        );
        expect(grid.cellAt(point), GridCoord.origin, reason: 'angle $angle');
      }
      for (final corner in grid.corners(GridCoord.origin)) {
        expect(grid.cellAt(corner * 0.95), GridCoord.origin);
      }
    });

    test('every neighbour is exactly one step away', () {
      expect(grid.neighborCount, 6);
      final neighbours = grid.neighborsOf(const GridCoord(2, -3));
      expect(neighbours.length, 6);
      for (final neighbour in neighbours) {
        expect(grid.distance(const GridCoord(2, -3), neighbour), 1);
      }
    });

    test('every neighbour is the same world distance away', () {
      // The property hexes exist for: no direction is a shortcut.
      final middle = grid.center(GridCoord.origin);
      final spans = grid
          .neighborsOf(GridCoord.origin)
          .map((cell) => (grid.center(cell) - middle).length);
      for (final span in spans) {
        expect(span, closeTo(math.sqrt(3.0), 1e-6));
      }
    });

    test('measures cube distance', () {
      expect(grid.distance(GridCoord.origin, const GridCoord(3, -1)), 3);
      expect(grid.distance(GridCoord.origin, const GridCoord(-2, -2)), 4);
    });

    test('cellsWithin grows as a hexagon', () {
      // 1, 7, 19, 37: the centred hexagonal numbers.
      expect(grid.cellsWithin(GridCoord.origin, 0).length, 1);
      expect(grid.cellsWithin(GridCoord.origin, 1).length, 7);
      expect(grid.cellsWithin(GridCoord.origin, 2).length, 19);
      expect(grid.cellsWithin(GridCoord.origin, 3).length, 37);
    });

    test('ring returns 6 * radius cells, all at that distance', () {
      for (var radius = 1; radius <= 4; radius++) {
        final ring = grid.ring(const GridCoord(1, 1), radius).toList();
        expect(ring.length, 6 * radius);
        expect(ring.toSet().length, 6 * radius);
        for (final cell in ring) {
          expect(grid.distance(const GridCoord(1, 1), cell), radius);
        }
      }
    });

    test('corners sit on the circumradius', () {
      final corners = grid.corners(const GridCoord(1, -2));
      final middle = grid.center(const GridCoord(1, -2));
      expect(corners.length, 6);
      for (final corner in corners) {
        expect((corner - middle).length, closeTo(1.0, 1e-6));
      }
    });

    test('reports the width and height of its cells', () {
      expect(grid.cellWidth, closeTo(math.sqrt(3.0), 1e-9));
      expect(grid.cellHeight, closeTo(2.0, 1e-9));

      const flat = HexGrid(cellSize: 1.0, orientation: HexOrientation.flatTop);
      expect(flat.cellWidth, closeTo(2.0, 1e-9));
      expect(flat.cellHeight, closeTo(math.sqrt(3.0), 1e-9));
    });
  });

  group('GridMap', () {
    test('stores, reads, and removes', () {
      final map = GridMap<String>();
      expect(map.isEmpty, isTrue);

      map[const GridCoord(1, 2)] = 'tree';
      expect(map[const GridCoord(1, 2)], 'tree');
      expect(map.contains(const GridCoord(1, 2)), isTrue);
      expect(map[const GridCoord(9, 9)], isNull);
      expect(map.valueAt(const GridCoord(9, 9), 'grass'), 'grass');
      expect(map.length, 1);

      expect(map.remove(const GridCoord(1, 2)), 'tree');
      expect(map.isEmpty, isTrue);
    });

    test('tracks its bounds as cells come and go', () {
      final map = GridMap<int>();
      expect(map.bounds, isNull);

      map[const GridCoord(0, 0)] = 1;
      map[const GridCoord(5, -2)] = 2;
      expect(map.bounds!.min, const GridCoord(0, -2));
      expect(map.bounds!.max, const GridCoord(5, 0));

      map.remove(const GridCoord(5, -2));
      expect(map.bounds!.min, const GridCoord(0, 0));
      expect(map.bounds!.max, const GridCoord(0, 0));
    });

    test('fills a region', () {
      final map = GridMap<bool>.filled(
        GridRect.sized(GridCoord.origin, 3, 3),
        true,
      );
      expect(map.length, 9);
      expect(map[const GridCoord(2, 2)], isTrue);
    });

    test('queries and transforms', () {
      final map = GridMap<int>.from({
        const GridCoord(0, 0): 1,
        const GridCoord(1, 0): 5,
        const GridCoord(2, 0): 9,
      });
      expect(map.where((cell, value) => value > 4).length, 2);
      expect(
        map.mapValues((cell, value) => value * 2)[const GridCoord(2, 0)],
        18,
      );
    });
  });

  group('findGridPath', () {
    const grid = SquareGrid(cellSize: 1.0);
    double? open(GridCoord from, GridCoord to) => 1.0;

    test('routes across open ground in the fewest steps', () {
      final path = findGridPath(
        grid,
        GridCoord.origin,
        const GridCoord(5, 3),
        stepCost: open,
      );
      expect(path.reachedGoal, isTrue);
      expect(path.cells.first, GridCoord.origin);
      expect(path.cells.last, const GridCoord(5, 3));
      expect(path.cost, closeTo(8.0, 1e-9));
      expect(path.length, 9);
    });

    test('a trivial route is the start cell alone', () {
      final path = findGridPath(
        grid,
        GridCoord.origin,
        GridCoord.origin,
        stepCost: open,
      );
      expect(path.reachedGoal, isTrue);
      expect(path.cells, [GridCoord.origin]);
      expect(path.cost, 0.0);
    });

    test('walks around a wall', () {
      // A wall down x = 2, with a gap at y = 4.
      double? blocked(GridCoord from, GridCoord to) {
        if (to.x == 2 && to.y != 4) return null;
        return 1.0;
      }

      final path = findGridPath(
        grid,
        GridCoord.origin,
        const GridCoord(4, 0),
        stepCost: blocked,
      );
      expect(path.reachedGoal, isTrue);
      expect(path.cells, contains(const GridCoord(2, 4)));
      for (final cell in path.cells) {
        expect(blocked(cell, cell), isNotNull);
      }
    });

    test('takes a longer route to avoid expensive ground', () {
      // One expensive cell sits directly on the shortest route. Going around
      // it costs four cheap steps instead of one cheap and one dear.
      double? mud(GridCoord from, GridCoord to) =>
          to == const GridCoord(0, 1) ? 20.0 : 1.0;
      final path = findGridPath(
        grid,
        GridCoord.origin,
        const GridCoord(0, 2),
        stepCost: mud,
      );
      expect(path.reachedGoal, isTrue);
      expect(path.cells, isNot(contains(const GridCoord(0, 1))));
      expect(path.cost, closeTo(4.0, 1e-9));
    });

    test('drives through expensive ground when there is no way round', () {
      // The whole band is dear, so paying once is cheaper than any detour.
      double? band(GridCoord from, GridCoord to) => to.y == 1 ? 20.0 : 1.0;
      final path = findGridPath(
        grid,
        GridCoord.origin,
        const GridCoord(0, 2),
        stepCost: band,
      );
      expect(path.reachedGoal, isTrue);
      expect(path.cost, closeTo(21.0, 1e-9));
      expect(path.cells.where((cell) => cell.y == 1).length, 1);
    });

    test('returns the closest approach when the goal is walled off', () {
      double? sealed(GridCoord from, GridCoord to) => to.x >= 3 ? null : 1.0;
      final path = findGridPath(
        grid,
        GridCoord.origin,
        const GridCoord(6, 0),
        stepCost: sealed,
        maxVisited: 5000,
      );
      expect(path.reachedGoal, isFalse);
      expect(path.isEmpty, isFalse);
      expect(path.cells.last.x, 2);
    });

    test('returns nothing for an unreachable goal when partials are off', () {
      double? sealed(GridCoord from, GridCoord to) => to.x >= 3 ? null : 1.0;
      final path = findGridPath(
        grid,
        GridCoord.origin,
        const GridCoord(6, 0),
        stepCost: sealed,
        allowPartial: false,
        maxVisited: 5000,
      );
      expect(path.isEmpty, isTrue);
      expect(path.reachedGoal, isFalse);
    });

    test('respects its work budget', () {
      final path = findGridPath(
        grid,
        GridCoord.origin,
        const GridCoord(10000, 10000),
        stepCost: open,
        maxVisited: 200,
      );
      expect(path.reachedGoal, isFalse);
      expect(path.isEmpty, isFalse);
    });

    test('routes over a hex grid the same way', () {
      const hex = HexGrid(cellSize: 1.0);
      final path = findGridPath(
        hex,
        GridCoord.origin,
        const GridCoord(4, -2),
        stepCost: open,
      );
      expect(path.reachedGoal, isTrue);
      expect(path.cost, closeTo(4.0, 1e-9));
      for (var i = 1; i < path.cells.length; i++) {
        expect(hex.distance(path.cells[i - 1], path.cells[i]), 1);
      }
    });

    test('every step of a route is between adjacent cells', () {
      final path = findGridPath(
        grid,
        const GridCoord(-3, -3),
        const GridCoord(3, 4),
        stepCost: open,
      );
      for (var i = 1; i < path.cells.length; i++) {
        expect(grid.distance(path.cells[i - 1], path.cells[i]), 1);
      }
    });
  });
}
