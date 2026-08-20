// Behavior tests for the Cloth example's solver. Cloth is judged by eye, so
// these pin down the invariants that a screenshot hides: the sheet stays
// finite, it does not stretch, pins hold, and nothing ends up inside a
// collider or through the floor.

import 'dart:math' as math;

import 'package:example_app/cloth/cloth_solver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

ClothSolver _sheet({
  int columns = 20,
  int rows = 20,
  double spacing = 0.06,
  double height = 2.0,
  bool vertical = true,
}) {
  return ClothSolver(
    columns: columns,
    rows: rows,
    layout: (c, r) => vertical
        ? Vector3((c - columns / 2) * spacing, height - r * spacing, 0.0)
        : Vector3(
            (c - columns / 2) * spacing,
            height,
            (r - rows / 2) * spacing,
          ),
  );
}

void _run(ClothSolver solver, int steps) {
  for (var i = 0; i < steps; i++) {
    solver.step(_dt);
  }
}

Vector3 _positionOf(ClothSolver solver, int index) => Vector3(
  solver.positions[index * 3],
  solver.positions[index * 3 + 1],
  solver.positions[index * 3 + 2],
);

/// The worst grid-neighbor stretch, as a fraction of the rest spacing.
double _maxStrain(ClothSolver solver, double spacing) {
  var worst = 0.0;
  for (var r = 0; r < solver.rows; r++) {
    for (var c = 0; c < solver.columns; c++) {
      final i = r * solver.columns + c;
      if (c + 1 < solver.columns) {
        final d = _positionOf(solver, i).distanceTo(_positionOf(solver, i + 1));
        worst = math.max(worst, (d - spacing).abs() / spacing);
      }
      if (r + 1 < solver.rows) {
        final d = _positionOf(
          solver,
          i,
        ).distanceTo(_positionOf(solver, i + solver.columns));
        worst = math.max(worst, (d - spacing).abs() / spacing);
      }
    }
  }
  return worst;
}

void main() {
  test('a hanging sheet settles without stretching or diverging', () {
    final solver = _sheet()..groundHeight = null;
    for (var c = 0; c < solver.columns; c++) {
      solver.setPinned(c, true);
    }
    _run(solver, 240);

    for (var i = 0; i < solver.positions.length; i++) {
      expect(solver.positions[i].isFinite, isTrue, reason: 'float $i');
    }
    // Woven fabric barely stretches, which is the whole point of solving the
    // distance constraints at zero compliance.
    expect(_maxStrain(solver, 0.06), lessThan(0.02));
  });

  test('pinned particles do not move', () {
    final solver = _sheet();
    solver.pinTopEdge();
    final before = [
      for (var c = 0; c < solver.columns; c++) _positionOf(solver, c),
    ];
    _run(solver, 120);
    for (var c = 0; c < solver.columns; c++) {
      expect(_positionOf(solver, c).distanceTo(before[c]), lessThan(1e-6));
    }
  });

  test('a sheet dropped on a sphere drapes over it, not through it', () {
    final solver = _sheet(vertical: false, height: 1.4, spacing: 0.07);
    final sphere = ClothSphere(center: Vector3(0.0, 0.5, 0.0), radius: 0.35);
    solver.colliders.add(sphere);
    solver.groundHeight = 0.0;
    _run(solver, 300);

    for (var i = 0; i < solver.particleCount; i++) {
      final p = _positionOf(solver, i);
      expect(
        p.distanceTo(sphere.center),
        greaterThan(sphere.radius * 0.98),
        reason: 'particle $i sank into the sphere',
      );
      expect(p.y, greaterThan(-1e-3), reason: 'particle $i fell through');
    }
    // The middle of the sheet should be resting on top of the sphere.
    final center = solver.rows ~/ 2 * solver.columns + solver.columns ~/ 2;
    expect(_positionOf(solver, center).y, greaterThan(0.7));
  });

  test('self-collision keeps folds apart', () {
    // A sheet dropped from a height onto the floor buckles and piles up, so
    // its own layers are the only thing it can collide with.
    final solver = _sheet(vertical: false, height: 0.5, spacing: 0.05);
    solver.groundHeight = 0.0;
    solver.selfCollision = true;
    _run(solver, 240);

    final minimum = solver.thickness * 2.0;
    var worst = double.infinity;
    for (var i = 0; i < solver.particleCount; i++) {
      for (var j = i + 1; j < solver.particleCount; j++) {
        final di = (i ~/ solver.columns) - (j ~/ solver.columns);
        final dj = (i % solver.columns) - (j % solver.columns);
        if (di.abs() <= 1 && dj.abs() <= 1) continue;
        worst = math.min(
          worst,
          _positionOf(solver, i).distanceTo(_positionOf(solver, j)),
        );
      }
    }
    // Position-based contacts are approximate, so this checks that layers
    // stay apart rather than that the separation is exact.
    expect(worst, greaterThan(minimum * 0.5));
  });

  test('wind carries the sheet downwind', () {
    final solver = _sheet(columns: 16, rows: 12, spacing: 0.08);
    for (var r = 0; r < solver.rows; r++) {
      solver.setPinned(r * solver.columns, true);
    }
    solver.groundHeight = null;
    solver.wind.setValues(0.0, 0.0, 9.0);
    _run(solver, 180);

    var meanZ = 0.0;
    for (var i = 0; i < solver.particleCount; i++) {
      meanZ += solver.positions[i * 3 + 2];
    }
    meanZ /= solver.particleCount;
    expect(meanZ, greaterThan(0.2));
  });

  test('a flag in a gale stays bounded', () {
    final solver = _sheet(columns: 40, rows: 26, spacing: 0.06);
    for (var r = 0; r < solver.rows; r++) {
      solver.setPinned(r * solver.columns, true);
    }
    solver.selfCollision = false;
    for (var i = 0; i < 600; i++) {
      // Swing the wind the way the example does, which is what keeps a flag
      // fluttering instead of settling.
      final swing = math.sin(i / 60 * 0.6) * 0.28;
      solver.wind.setValues(
        math.cos(swing) * 16.0,
        0.5,
        math.sin(swing) * 16.0,
      );
      solver.step(_dt);
    }
    for (var i = 0; i < solver.particleCount; i++) {
      final p = _positionOf(solver, i);
      expect(p.length, lessThan(10.0), reason: 'particle $i flew off');
    }
    // Looser than the quiet hang: a gale loads the sheet hard enough that a
    // single sweep per substep leaves a few percent on the worst edge.
    expect(_maxStrain(solver, 0.06), lessThan(0.1));
  });

  test(
    'a capsule walking through a sheet parts it instead of passing through',
    () {
      // The walkthrough scene's case: a body crossing a pinned sheet faster than
      // the sheet's own spacing, which only holds because the solver sweeps the
      // collider across the substeps rather than teleporting it once a frame.
      final solver = _sheet(columns: 24, rows: 20, spacing: 0.14, height: 2.6);
      solver.pinTopEdge();
      solver.groundHeight = 0.0;
      solver.substeps = 8;
      final body = ClothCapsule(
        start: Vector3(0.0, 0.4, 2.0),
        end: Vector3(0.0, 1.35, 2.0),
        radius: 0.4,
      );
      solver.colliders.add(body);

      final normal = Vector3.zero();
      var deepest = 0.0;
      for (var i = 0; i < 240; i++) {
        body.standAt(Vector3(0.0, 0.0, 2.0 - i / 60 * 4.0), 1.75);
        solver.step(_dt);
        for (var k = 0; k < solver.particleCount; k++) {
          final p = _positionOf(solver, k);
          deepest = math.max(
            deepest,
            body.contact(p.x, p.y, p.z, 1.0, 0.0, normal),
          );
        }
      }
      expect(deepest, lessThan(1e-6));
      // And the sheet is left hanging, not dragged away with him.
      expect(_maxStrain(solver, 0.14), lessThan(0.05));
    },
  );

  test('reset restores the starting shape', () {
    final solver = _sheet();
    final before = List<double>.of(solver.positions);
    _run(solver, 60);
    solver.reset();
    for (var i = 0; i < before.length; i++) {
      expect(solver.positions[i], closeTo(before[i], 1e-6));
    }
  });
}
