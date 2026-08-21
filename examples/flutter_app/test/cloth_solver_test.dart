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
    // single sweep per substep leaves some on the worst edge, and the hem
    // drags along the floor rather than bouncing off it now that contacts do
    // not manufacture momentum.
    expect(_maxStrain(solver, 0.06), lessThan(0.15));
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

  test('the wind is billed for rest area, not stretched area', () {
    // A sheet forced past its rest size by a body sweeping through it used to
    // feed itself: bigger triangles caught more wind, which stretched them
    // further, until the sheet exploded. Real cloth barely changes area, so
    // the force is billed against the rest pose and that loop cannot close.
    final solver = _sheet(columns: 32, rows: 26, spacing: 0.116, height: 3.0);
    solver.pinTopEdge();
    solver.groundHeight = 0.0;
    solver.substeps = 2;
    solver.contactOffset = 0.30;
    solver.wind.setValues(4.0, 0.0, 2.0);

    final torso = ClothCapsule(
      start: Vector3(0.0, 1.44, 4.0),
      end: Vector3(0.0, 1.44, 4.0),
      radius: 1.0,
    );
    final body = ClothColliderSet([torso]);
    solver.colliders.add(body);

    for (var i = 0; i < 600; i++) {
      final z = 4.0 - i / 60.0 * 2.5;
      torso.placeAt(Vector3(0.0, 1.44, z), Vector3(0.0, 1.44, z));
      body.setBounds(Vector3(0.0, 1.44, z), 1.05);
      solver.step(_dt);
    }
    for (var i = 0; i < solver.positions.length; i++) {
      expect(solver.positions[i].isFinite, isTrue, reason: 'float $i');
    }
    for (var i = 0; i < solver.particleCount; i++) {
      expect(_positionOf(solver, i).length, lessThan(20.0));
    }
  });

  test('a contact does not manufacture velocity as substeps rise', () {
    // Velocity is read back as the position change over a substep, so a
    // contact correction of a fixed size reports a speed of that size over h.
    // Left alone, halving the substep doubles the speed a resting overlap
    // hands back, which is what made self-collision buzz harder the more
    // substeps it was given. Separation carries the previous position with it,
    // so the speed after contact must not track the substep count.
    double speedAfterContact(int substeps) {
      // A sheet draped over a sphere and left to settle, so the contact is a
      // steady rest rather than a first-frame overlap.
      final solver =
          _sheet(
              columns: 12,
              rows: 12,
              spacing: 0.1,
              height: 1.0,
              vertical: false,
            )
            ..substeps = substeps
            ..selfCollision = false
            ..dragCoefficient = 0.0
            ..liftCoefficient = 0.0;
      solver.colliders.add(
        ClothSphere(center: Vector3(0.0, 0.55, 0.0), radius: 0.3),
      );
      // Let it settle onto the collider first: a contact that is already
      // resting is the case that buzzes, not a first-frame overlap (resolving
      // that legitimately yanks the neighbours through the weave).
      for (var i = 0; i < 420; i++) {
        solver.step(_dt);
      }
      // How far the sheet coasts on the next step is the velocity the contact
      // left behind.
      final before = [
        for (var i = 0; i < solver.particleCount; i++) _positionOf(solver, i),
      ];
      solver.step(_dt);
      var worst = 0.0;
      for (var i = 0; i < solver.particleCount; i++) {
        worst = math.max(worst, _positionOf(solver, i).distanceTo(before[i]));
      }
      return worst / _dt;
    }

    final slow = speedAfterContact(2);
    final fast = speedAfterContact(24);
    expect(fast, lessThan(slow * 2.0 + 0.1), reason: 'slow $slow fast $fast');
  });

  test('an uneven frame rate does not shake the sheet apart', () {
    // Velocity in position-based dynamics is the position change over the
    // step, so the step size is baked into every velocity in the sheet. Handed
    // the raw frame time, a short frame reports inflated velocities and the
    // long frame that follows integrates them into a large displacement, whose
    // correction reports larger velocities again. Anything that makes frames
    // uneven (a costly effect, a window resize, self-collision switching on)
    // then shakes the cloth, which is a timing bug wearing the costume of a
    // cloth bug. [ClothSolver.advance] runs fixed steps so this cannot happen.
    final solver = _sheet(columns: 24, rows: 20, spacing: 0.12, height: 3.0);
    solver.pinTopEdge();
    solver.wind.setValues(3.0, 0.0, 1.0);

    for (var i = 0; i < 600; i++) {
      // The pathological pacing: 240 fps and 30 fps alternating.
      solver.advance(i.isEven ? 1 / 240 : 1 / 30);
    }
    for (var i = 0; i < solver.particleCount; i++) {
      final p = _positionOf(solver, i);
      expect(
        p.x.isFinite && p.y.isFinite && p.z.isFinite,
        isTrue,
        reason: 'particle $i diverged',
      );
      expect(p.length, lessThan(20.0), reason: 'particle $i flew off');
    }
    expect(_maxStrain(solver, 0.12), lessThan(0.2));
  });

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
