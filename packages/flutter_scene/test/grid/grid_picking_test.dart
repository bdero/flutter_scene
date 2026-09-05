// Covers turning a pointer into a grid cell: the ray/plane crossing, the
// screen-space entry points, and the marquee rectangle.

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_scene/grid.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  const grid = SquareGrid(cellSize: 2.0);
  const viewSize = Size(400.0, 400.0);

  // Straight down at the origin, so the middle of the view is cell (0, 0).
  OrthographicCamera overhead({double height = 40.0}) => OrthographicCamera(
    position: Vector3(0.0, height, 0.0),
    target: Vector3.zero(),
    up: Vector3(0.0, 0.0, 1.0),
    height: 40.0,
    near: 0.1,
    far: 200.0,
  );

  group('planePointOf', () {
    test('crosses the plane below the ray origin', () {
      final point = grid.planePointOf(
        Ray.originDirection(Vector3(3.0, 10.0, -7.0), Vector3(0.0, -1.0, 0.0)),
      );
      expect(point!.x, closeTo(3.0, 1e-6));
      expect(point.y, closeTo(0.0, 1e-6));
      expect(point.z, closeTo(-7.0, 1e-6));
    });

    test('crosses at an angle', () {
      final point = grid.planePointOf(
        Ray.originDirection(Vector3(0.0, 10.0, 0.0), Vector3(1.0, -1.0, 0.0)),
      );
      expect(point!.x, closeTo(10.0, 1e-6));
      expect(point.z, closeTo(0.0, 1e-6));
    });

    test('misses when the ray runs along the plane', () {
      expect(
        grid.planePointOf(
          Ray.originDirection(Vector3(0.0, 5.0, 0.0), Vector3(1.0, 0.0, 0.0)),
        ),
        isNull,
      );
    });

    test('misses when the ray points away from the plane', () {
      expect(
        grid.planePointOf(
          Ray.originDirection(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 1.0, 0.0)),
        ),
        isNull,
      );
      expect(
        grid.cellUnderRay(
          Ray.originDirection(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 1.0, 0.0)),
        ),
        isNull,
      );
    });

    test('respects the grid elevation', () {
      const raised = SquareGrid(cellSize: 1.0, elevation: 4.0);
      final point = raised.planePointOf(
        Ray.originDirection(Vector3(0.0, 10.0, 0.0), Vector3(1.0, -1.0, 0.0)),
      );
      expect(point!.y, closeTo(4.0, 1e-6));
      expect(point.x, closeTo(6.0, 1e-6));
    });
  });

  group('cellAtScreenPoint', () {
    test('the middle of the view is the cell under the camera', () {
      final cell = grid.cellAtScreenPoint(
        const Offset(200.0, 200.0),
        camera: overhead(),
        viewSize: viewSize,
      );
      expect(cell, GridCoord.origin);
    });

    test('moves a cell at a time across the view', () {
      // The view spans 40 world units over 400 pixels, so 10 pixels is one
      // world unit and a 2-unit cell is 20 pixels.
      final camera = overhead();
      final right = grid.cellAtScreenPoint(
        const Offset(240.0, 200.0),
        camera: camera,
        viewSize: viewSize,
      );
      expect(right, const GridCoord(2, 0));

      // Screen-down is +Z with this camera's up pointing along +Z... which is
      // to say the far edge of the board is at the top of the view.
      final down = grid.cellAtScreenPoint(
        const Offset(200.0, 240.0),
        camera: camera,
        viewSize: viewSize,
      );
      expect(down, const GridCoord(0, -2));
    });

    test('reports the unrounded point too', () {
      final point = grid.planePointAtScreenPoint(
        const Offset(205.0, 200.0),
        camera: overhead(),
        viewSize: viewSize,
      );
      expect(point!.x, closeTo(0.5, 1e-4));
      expect(point.y, closeTo(0.0, 1e-6));
    });

    test('misses when the pointer is on the horizon', () {
      final camera = PerspectiveCamera(
        position: Vector3(0.0, 2.0, 0.0),
        target: Vector3(0.0, 12.0, 10.0),
      );
      final cell = grid.cellAtScreenPoint(
        const Offset(200.0, 0.0),
        camera: camera,
        viewSize: viewSize,
      );
      expect(cell, isNull);
    });
  });

  group('cellsInScreenRect', () {
    test('covers the cells a marquee is dragged over', () {
      final region = grid.cellsInScreenRect(
        const Rect.fromLTRB(180.0, 180.0, 260.0, 260.0),
        camera: overhead(),
        viewSize: viewSize,
      );
      expect(region, isNotNull);
      expect(region!.contains(GridCoord.origin), isTrue);
      expect(region.contains(const GridCoord(2, 0)), isTrue);
      expect(region.contains(const GridCoord(0, -2)), isTrue);
      expect(region.contains(const GridCoord(6, 0)), isFalse);
    });

    test('is null when the marquee never meets the plane', () {
      final camera = PerspectiveCamera(
        position: Vector3(0.0, 2.0, 0.0),
        target: Vector3(0.0, 20.0, 4.0),
      );
      expect(
        grid.cellsInScreenRect(
          const Rect.fromLTRB(0.0, 0.0, 400.0, 4.0),
          camera: camera,
          viewSize: viewSize,
        ),
        isNull,
      );
    });
  });

  test('a hex grid picks through the same entry points', () {
    const hex = HexGrid(cellSize: 2.0);
    final cell = hex.cellAtScreenPoint(
      const Offset(200.0, 200.0),
      camera: overhead(),
      viewSize: viewSize,
    );
    expect(cell, GridCoord.origin);
  });
}
