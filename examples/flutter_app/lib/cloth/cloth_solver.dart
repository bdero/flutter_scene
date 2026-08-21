// A cloth solver over a quad grid: XPBD distance constraints for the weave,
// a dihedral angle constraint for bending, per-triangle aerodynamics, sphere
// and ground contacts with friction, and particle self-collision.
//
// The schedule is one constraint iteration per substep ("small steps"), which
// buys accuracy from substepping instead of from iteration count and keeps the
// cloth inextensible without a stiff solve.
//
// References:
//   Macklin, Muller, Chentanez, "XPBD: Position-Based Simulation of Compliant
//     Constrained Dynamics" (2016).
//   Macklin et al., "Small Steps in Physics Simulation" (2019).
//   Muller, Heidelberger, Hennix, Ratcliff, "Position Based Dynamics" (2007),
//     appendix A, for the dihedral bending constraint.
//   Teschner et al., "Optimized Spatial Hashing for Collision Detection of
//     Deformable Objects" (2003), for the self-collision broadphase.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// A shape the cloth collides against.
///
/// A collider is posed by the scene between steps. It remembers where it was,
/// and the solver sweeps it across the substeps, so a shape crossing the sheet
/// faster than the sheet's own spacing still parts it instead of teleporting
/// through it once a frame.
///
/// Posing a collider is what starts a new sweep ([ClothSphere.moveTo],
/// [ClothCapsule.placeAt]), rather than stepping a solver, so one collider can
/// be shared by several sheets without the first sheet stepped eating the
/// sweep. Mutating the pose vectors directly needs a [snapshot] first.
abstract class ClothCollider {
  /// Ends the current sweep, making the present pose the next one's start.
  void snapshot();

  /// The contact against a particle at `(px, py, pz)`, with the shape posed at
  /// sweep fraction [t] (0 at the last pose, 1 at the current one) and held
  /// [margin] clear of the cloth.
  ///
  /// Returns the penetration depth, zero or less when there is no contact, and
  /// writes the unit direction that pushes the particle out into [normal].
  double contact(
    double px,
    double py,
    double pz,
    double t,
    double margin,
    Vector3 normal,
  );
}

/// A sphere the cloth collides against.
class ClothSphere extends ClothCollider {
  ClothSphere({required Vector3 center, required this.radius})
    : center = center.clone(),
      _from = center.clone();

  /// World-space center, mutable so the scene can animate the collider.
  final Vector3 center;

  /// Collision radius.
  double radius;

  final Vector3 _from;

  @override
  void snapshot() => _from.setFrom(center);

  /// Sweeps the sphere to [target] over the coming step.
  void moveTo(Vector3 target) {
    snapshot();
    center.setFrom(target);
  }

  @override
  double contact(
    double px,
    double py,
    double pz,
    double t,
    double margin,
    Vector3 normal,
  ) {
    final dx = px - (_from.x + (center.x - _from.x) * t);
    final dy = py - (_from.y + (center.y - _from.y) * t);
    final dz = pz - (_from.z + (center.z - _from.z) * t);
    return _pushOut(dx, dy, dz, radius + margin, normal);
  }
}

/// A capsule the cloth collides against: a segment with a radius.
///
/// A handful of these fitted to a character's bones wrap cloth around the
/// actual body, where a single capsule around the whole character leaves the
/// limbs poking through.
class ClothCapsule extends ClothCollider {
  ClothCapsule({
    required Vector3 start,
    required Vector3 end,
    required this.radius,
  }) : start = start.clone(),
       end = end.clone(),
       _fromStart = start.clone(),
       _fromEnd = end.clone();

  /// The segment's ends, mutable so the scene can pose the capsule.
  final Vector3 start;
  final Vector3 end;

  /// Collision radius around the segment.
  double radius;

  final Vector3 _fromStart;
  final Vector3 _fromEnd;

  /// The segment ends at both ends of the current sweep, for bounding a body
  /// that has to cover everywhere it passes through this step.
  Iterable<Vector3> get sweepPoints => [_fromStart, _fromEnd, start, end];

  @override
  void snapshot() {
    _fromStart.setFrom(start);
    _fromEnd.setFrom(end);
  }

  /// Sweeps the capsule onto the segment from [a] to [b] over the coming step.
  void placeAt(Vector3 a, Vector3 b) {
    snapshot();
    start.setFrom(a);
    end.setFrom(b);
  }

  /// Sweeps the capsule to stand upright with its base at [base].
  void standAt(Vector3 base, double height) {
    snapshot();
    start.setValues(base.x, base.y + radius, base.z);
    end.setValues(base.x, base.y + math.max(height - radius, radius), base.z);
  }

  @override
  double contact(
    double px,
    double py,
    double pz,
    double t,
    double margin,
    Vector3 normal,
  ) {
    final ax = _fromStart.x + (start.x - _fromStart.x) * t;
    final ay = _fromStart.y + (start.y - _fromStart.y) * t;
    final az = _fromStart.z + (start.z - _fromStart.z) * t;
    final ex = _fromEnd.x + (end.x - _fromEnd.x) * t - ax;
    final ey = _fromEnd.y + (end.y - _fromEnd.y) * t - ay;
    final ez = _fromEnd.z + (end.z - _fromEnd.z) * t - az;
    final lengthSquared = ex * ex + ey * ey + ez * ez;
    final along = lengthSquared < 1e-12
        ? 0.0
        : (((px - ax) * ex + (py - ay) * ey + (pz - az) * ez) / lengthSquared)
              .clamp(0.0, 1.0);
    return _pushOut(
      px - (ax + ex * along),
      py - (ay + ey * along),
      pz - (az + ez * along),
      radius + margin,
      normal,
    );
  }
}

/// Several colliders resolved as one body, behind a bounding sphere.
///
/// A character fitted with a dozen shapes is otherwise a dozen distance tests
/// per particle per substep; the bound rejects the whole body in one test for
/// the particles nowhere near it, which is nearly all of them.
class ClothColliderSet extends ClothCollider {
  ClothColliderSet(this.parts);

  final List<ClothCollider> parts;

  final Vector3 _boundCenter = Vector3.zero();
  double _boundRadius = 0.0;

  /// Sets the sphere that must contain every part over the whole sweep.
  void setBounds(Vector3 center, double radius) {
    _boundCenter.setFrom(center);
    _boundRadius = radius;
  }

  @override
  void snapshot() {
    for (final part in parts) {
      part.snapshot();
    }
  }

  @override
  double contact(
    double px,
    double py,
    double pz,
    double t,
    double margin,
    Vector3 normal,
  ) {
    final dx = px - _boundCenter.x;
    final dy = py - _boundCenter.y;
    final dz = pz - _boundCenter.z;
    final reach = _boundRadius + margin;
    if (dx * dx + dy * dy + dz * dz > reach * reach) return 0.0;

    // The deepest part wins this substep; a particle wedged between two of
    // them is pushed out of the other on the next one.
    var deepest = 0.0;
    for (final part in parts) {
      final depth = part.contact(px, py, pz, t, margin, _scratch);
      if (depth <= deepest) continue;
      deepest = depth;
      normal.setFrom(_scratch);
    }
    return deepest;
  }

  final Vector3 _scratch = Vector3.zero();
}

/// Shared push-out for a particle at offset `(dx, dy, dz)` from a shape's core
/// point, given the shape's [reach] (radius plus margin).
double _pushOut(double dx, double dy, double dz, double reach, Vector3 normal) {
  final distanceSquared = dx * dx + dy * dy + dz * dz;
  if (distanceSquared >= reach * reach) return 0.0;
  final distance = math.sqrt(distanceSquared);
  if (distance < 1e-9) {
    // Dead centre: any direction works, and up is the least surprising.
    normal.setValues(0.0, 1.0, 0.0);
    return reach;
  }
  normal.setValues(dx / distance, dy / distance, dz / distance);
  return reach - distance;
}

/// A rectangular sheet of cloth simulated as a grid of particles.
///
/// Particle `(column, row)` lives at index `row * columns + column`, and the
/// [positions] / [normals] streams are laid out to feed a `MeshGeometry`
/// directly.
class ClothSolver {
  /// Builds a sheet whose particles start where [layout] places them.
  ///
  /// [arealDensity] is mass per square meter, so the wind pushes a fine grid
  /// and a coarse one the same way.
  ClothSolver({
    required this.columns,
    required this.rows,
    required Vector3 Function(int column, int row) layout,
    this.arealDensity = 0.22,
  }) : positions = Float32List(columns * rows * 3),
       normals = Float32List(columns * rows * 3),
       texCoords = Float32List(columns * rows * 2),
       _previous = Float32List(columns * rows * 3),
       _velocities = Float32List(columns * rows * 3),
       _forces = Float32List(columns * rows * 3),
       _restPositions = Float32List(columns * rows * 3),
       _inverseMasses = Float32List(columns * rows),
       _pinned = Uint8List(columns * rows) {
    if (columns < 2 || rows < 2) {
      throw ArgumentError('A cloth grid needs at least two rows and columns');
    }
    _layout(layout);
    _buildTriangles();
    _measureTriangles();
    _buildConstraints();
    _buildSpatialHash();
  }

  /// Particles across the sheet.
  final int columns;

  /// Particles down the sheet.
  final int rows;

  /// Mass per square meter of sheet.
  final double arealDensity;

  /// World-space particle positions, three floats each.
  final Float32List positions;

  /// Vertex normals, recomputed by [updateNormals].
  final Float32List normals;

  /// Texture coordinates, `(0, 0)` at particle `(0, 0)` and `(1, 1)` at the
  /// far corner. Fixed for the sheet's lifetime.
  final Float32List texCoords;

  /// The triangle list, wound to face the same way as the engine primitives.
  late final Uint16List triangles;

  int get particleCount => columns * rows;
  int get triangleCount => triangles.length ~/ 3;
  int get constraintCount => _distanceRest.length + _bendRest.length;

  /// Constraint solver substeps per [step]. More substeps mean a stiffer,
  /// better conditioned sheet for the same wall-clock budget than more
  /// iterations would.
  int substeps = 12;

  /// Inverse stretch stiffness, in meters per newton. Zero is inextensible;
  /// real woven fabric sits very close to it.
  double stretchCompliance = 0.0;

  /// Resistance to folding, 0 (limp) to 1 (stiff as card).
  double bendStiffness = 0.25;

  /// Fraction of the along-edge relative velocity removed per substep.
  ///
  /// This is the fabric's internal viscosity, and it is what keeps the sheet
  /// from ringing: projecting a stiff constraint set one sweep at a time
  /// leaves a little residual velocity in the stretch modes every substep,
  /// and left alone that residual compounds until the sheet tears itself
  /// apart. Damping only length-changing motion leaves swinging, draping, and
  /// falling untouched.
  double stretchDamping = 0.25;

  /// Fraction of velocity shed per second, bleeding off bulk motion.
  double damping = 0.1;

  /// Gravity, meters per second squared.
  final Vector3 gravity = Vector3(0.0, -9.81, 0.0);

  /// Steady wind velocity in meters per second. The sheet feels the
  /// difference between this and its own velocity, so a still sheet in wind
  /// and a moving sheet in still air behave alike.
  final Vector3 wind = Vector3.zero();

  /// Gust strength, as a fraction of [wind] varying over space and time.
  double windGust = 0.35;

  /// Air density, scaling both aerodynamic terms.
  double airDensity = 1.2;

  /// Pressure drag across the sheet's faces. This is what makes a flag snap
  /// and billow rather than swing like a curtain of beads.
  double dragCoefficient = 1.2;

  /// Lift perpendicular to the airflow, which sets up the travelling ripple
  /// along a flag.
  double liftCoefficient = 0.35;

  /// Sliding friction against colliders and against the sheet itself.
  double friction = 0.35;

  /// Half the sheet's thickness, the closest two non-neighboring particles
  /// may come. Scales with the grid spacing, since two layers cannot be
  /// resolved any finer than the particles that carry them.
  ///
  /// Keep it under half the spacing. Self-collision holds non-adjacent
  /// particles `2 * thickness` apart, so above that it demands they stay
  /// further apart than the weave holds adjacent ones, and the two constraint
  /// sets fight over every fold tighter than a couple of cells.
  late double thickness;

  /// [thickness] as a fraction of the grid spacing, which is how the scenes
  /// set it (the spacing is not known until the sheet is laid out).
  double get thicknessRatio => thickness / _spacing;
  set thicknessRatio(double value) => thickness = _spacing * value;

  /// The gap held against colliders and the ground. Kept off [thickness] so a
  /// coarse sheet still wraps a body snugly instead of floating a cell away
  /// from it.
  double contactOffset = 0.02;

  /// Whether the sheet collides with itself. Folds stack instead of passing
  /// through each other, at the cost of the broadphase.
  bool selfCollision = true;

  /// Ground plane height, or null for no ground.
  double? groundHeight = 0.0;

  /// Shapes the sheet collides with.
  final List<ClothCollider> colliders = [];

  /// Wall-clock milliseconds the last [step] took, for the stats readout.
  double lastStepMilliseconds = 0.0;

  final Float32List _previous;
  final Float32List _velocities;
  final Float32List _forces;
  final Float32List _restPositions;
  final Float32List _inverseMasses;
  final Uint8List _pinned;

  double _inverseParticleMass = 1.0;
  double _spacing = 0.05;
  double _degenerateArea = 1e-9;
  double _time = 0.0;

  // Each triangle's area in the rest pose. The aerodynamic force uses this
  // rather than the deformed area: woven cloth barely changes area, so any
  // growth is solver error, and billing the wind for it makes a stretched
  // triangle catch more wind, which stretches it further.
  late final Float32List _triangleRestArea;

  // Distance constraints, one per mesh edge: particle pairs and rest lengths.
  late final Int32List _distancePairs;
  late final Float32List _distanceRest;

  // Dihedral bending constraints, one per interior edge. Each holds the two
  // shared-edge particles followed by the two opposite ones, plus the rest
  // angle between the adjacent triangle normals.
  late final Int32List _bendQuads;
  late final Float32List _bendRest;

  // Self-collision broadphase (Teschner-style spatial hash). The candidate
  // pairs are rebuilt once per step and resolved every substep, which is
  // sound because a substep moves a particle far less than one cell.
  late final Int32List _hashStart;
  late final Int32List _hashEntries;
  late Int32List _pairs;
  int _pairCount = 0;
  // Contacts the position solve resolved this substep, handed to the velocity
  // pass so it can damp the approach that caused them.
  late Int32List _pairContacts;
  late Float32List _pairNormals;
  int _pairContactCount = 0;
  int _hashTableSize = 0;

  int _grabbed = -1;
  final Vector3 _grabTarget = Vector3.zero();

  /// The particle nearest [point], for picking.
  int nearestParticle(Vector3 point) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < particleCount; i++) {
      final dx = positions[i * 3] - point.x;
      final dy = positions[i * 3 + 1] - point.y;
      final dz = positions[i * 3 + 2] - point.z;
      final distance = dx * dx + dy * dy + dz * dz;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /// Whether particle [index] is held in place.
  bool isPinned(int index) => _pinned[index] != 0;

  /// Holds particle [index] in place, or releases it.
  void setPinned(int index, bool pinned) {
    _pinned[index] = pinned ? 1 : 0;
    _inverseMasses[index] = pinned ? 0.0 : _inverseParticleMass;
  }

  /// Pins the row-0 edge, the usual flag and curtain attachment.
  void pinTopEdge() {
    for (var c = 0; c < columns; c++) {
      setPinned(c, true);
    }
  }

  /// Drags particle [index] to wherever [moveGrab] puts it, ignoring the
  /// forces on it, until [releaseGrab].
  void grab(int index) {
    _grabbed = index;
    _grabTarget.setValues(
      positions[index * 3],
      positions[index * 3 + 1],
      positions[index * 3 + 2],
    );
  }

  void moveGrab(Vector3 target) => _grabTarget.setFrom(target);

  void releaseGrab() => _grabbed = -1;

  bool get isGrabbing => _grabbed >= 0;

  /// The grabbed particle's position, or null when nothing is grabbed.
  Vector3? get grabbedPosition => _grabbed < 0
      ? null
      : Vector3(
          positions[_grabbed * 3],
          positions[_grabbed * 3 + 1],
          positions[_grabbed * 3 + 2],
        );

  /// Returns the sheet to its starting shape and stops it dead.
  void reset() {
    positions.setAll(0, _restPositions);
    _previous.setAll(0, _restPositions);
    _velocities.fillRange(0, _velocities.length, 0.0);
    _forces.fillRange(0, _forces.length, 0.0);
    _grabbed = -1;
    _time = 0.0;
    _accumulator = 0.0;
    updateNormals();
  }

  /// The fixed simulation timestep [advance] runs the solver at.
  static const double fixedTimeStep = 1.0 / 60.0;

  /// The most fixed steps [advance] will run for one frame. Beyond this the
  /// leftover time is dropped, so a long stall costs the sheet some simulated
  /// time rather than a frame that takes even longer and stalls again.
  static const int maxStepsPerFrame = 3;

  double _accumulator = 0.0;

  /// Advances the simulation to cover [frameSeconds] of real time, in fixed
  /// steps.
  ///
  /// Position-based dynamics reads velocity back as the position change over
  /// the step, so the timestep is baked into every velocity in the sheet. Feed
  /// it the frame time directly and an irregular frame rate feeds it a
  /// different one each frame: a short frame divides a small displacement by a
  /// small step and reports a large velocity, the next long frame integrates
  /// that velocity over a long step into a large displacement, and the
  /// constraint correction that follows reports an even larger velocity. The
  /// sheet shakes itself apart, and the trigger is whatever made the frames
  /// uneven rather than anything in the cloth. A fixed step keeps every
  /// velocity on the same footing.
  void advance(double frameSeconds) {
    if (!frameSeconds.isFinite || frameSeconds <= 0.0) return;
    _accumulator += frameSeconds;
    var steps = 0;
    while (_accumulator >= fixedTimeStep && steps < maxStepsPerFrame) {
      step(fixedTimeStep);
      _accumulator -= fixedTimeStep;
      steps++;
    }
    if (_accumulator > fixedTimeStep * maxStepsPerFrame) {
      _accumulator = 0.0;
    }
  }

  /// Advances the simulation by [deltaSeconds].
  ///
  /// This is the fixed-step primitive; scenes should call [advance] with the
  /// frame time instead, so the step size never varies.
  void step(double deltaSeconds) {
    final started = DateTime.now();
    final dt = deltaSeconds.clamp(1.0 / 240.0, 1.0 / 30.0);
    _time += dt;

    _applyAerodynamics();
    if (selfCollision) _collectSelfCollisionPairs();

    final h = dt / substeps;
    // Bending is projected once per substep, so the per-substep factor has to
    // compound to the requested stiffness over the whole step.
    final bend = bendStiffness <= 0.0
        ? 0.0
        : 1.0 - math.pow(1.0 - bendStiffness.clamp(0.0, 0.999), 1.0 / substeps);
    final stretchAlpha = stretchCompliance / (h * h);
    final velocityScale = math
        .pow(1.0 - damping.clamp(0.0, 0.99), h)
        .toDouble();

    for (var s = 0; s < substeps; s++) {
      _integrate(h);
      _solveDistances(stretchAlpha);
      if (bend > 0.0) _solveBending(bend.toDouble());
      if (selfCollision) _solveSelfCollisions();
      // Colliders sweep from where they were at the last step to where the
      // scene has now put them, one slice per substep.
      _solveColliders((s + 1) / substeps);
      _updateVelocities(h, velocityScale);
      _solveContactVelocity();
      if (stretchDamping > 0.0) _dampStretchVelocity();
    }
    updateNormals();
    lastStepMilliseconds =
        DateTime.now().difference(started).inMicroseconds / 1000.0;
  }

  /// Recomputes area-weighted vertex normals from the current positions.
  void updateNormals() {
    normals.fillRange(0, normals.length, 0.0);
    final tris = triangles;
    for (var t = 0; t < tris.length; t += 3) {
      final a = tris[t] * 3, b = tris[t + 1] * 3, c = tris[t + 2] * 3;
      final ux = positions[c] - positions[a];
      final uy = positions[c + 1] - positions[a + 1];
      final uz = positions[c + 2] - positions[a + 2];
      final vx = positions[b] - positions[a];
      final vy = positions[b + 1] - positions[a + 1];
      final vz = positions[b + 2] - positions[a + 2];
      // Left unnormalized so the accumulation is area weighted.
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      normals[a] += nx;
      normals[a + 1] += ny;
      normals[a + 2] += nz;
      normals[b] += nx;
      normals[b + 1] += ny;
      normals[b + 2] += nz;
      normals[c] += nx;
      normals[c + 1] += ny;
      normals[c + 2] += nz;
    }
    for (var i = 0; i < normals.length; i += 3) {
      final x = normals[i], y = normals[i + 1], z = normals[i + 2];
      final length = math.sqrt(x * x + y * y + z * z);
      if (length < 1e-12) {
        normals[i + 1] = 1.0;
        continue;
      }
      normals[i] = x / length;
      normals[i + 1] = y / length;
      normals[i + 2] = z / length;
    }
  }

  // --- Setup -------------------------------------------------------------

  void _layout(Vector3 Function(int column, int row) layout) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final i = r * columns + c;
        final p = layout(c, r);
        positions[i * 3] = p.x;
        positions[i * 3 + 1] = p.y;
        positions[i * 3 + 2] = p.z;
        texCoords[i * 2] = c / (columns - 1);
        texCoords[i * 2 + 1] = r / (rows - 1);
      }
    }
    _previous.setAll(0, positions);
    _restPositions.setAll(0, positions);

    // Cell spacing from the first row and column, which is what sets both the
    // particle mass and the default thickness.
    final across = _distanceBetween(0, 1);
    final down = _distanceBetween(0, columns);
    _spacing = math.max((across + down) * 0.5, 1e-4);
    _inverseParticleMass = 1.0 / (arealDensity * _spacing * _spacing);
    // A rest triangle's cross product is about spacing squared, so this is a
    // triangle collapsed to a thousandth of its rest area.
    _degenerateArea = _spacing * _spacing * 1e-3;
    _inverseMasses.fillRange(0, particleCount, _inverseParticleMass);
    thickness = _spacing * 0.4;
  }

  double _distanceBetween(int a, int b) {
    final dx = positions[b * 3] - positions[a * 3];
    final dy = positions[b * 3 + 1] - positions[a * 3 + 1];
    final dz = positions[b * 3 + 2] - positions[a * 3 + 2];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  void _buildTriangles() {
    final list = Uint16List((columns - 1) * (rows - 1) * 6);
    var t = 0;
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < columns - 1; c++) {
        final v00 = r * columns + c;
        final v10 = v00 + 1;
        final v01 = v00 + columns;
        final v11 = v01 + 1;
        // The diagonal alternates so the weave has no preferred fold
        // direction; a single diagonal makes the sheet drape along it.
        if ((c + r).isEven) {
          list[t++] = v00;
          list[t++] = v10;
          list[t++] = v01;
          list[t++] = v10;
          list[t++] = v11;
          list[t++] = v01;
        } else {
          list[t++] = v00;
          list[t++] = v11;
          list[t++] = v01;
          list[t++] = v00;
          list[t++] = v10;
          list[t++] = v11;
        }
      }
    }
    triangles = list;
  }

  void _measureTriangles() {
    _triangleRestArea = Float32List(triangleCount);
    for (var t = 0; t < triangles.length; t += 3) {
      final a = triangles[t] * 3,
          b = triangles[t + 1] * 3,
          c = triangles[t + 2] * 3;
      final ux = positions[c] - positions[a];
      final uy = positions[c + 1] - positions[a + 1];
      final uz = positions[c + 2] - positions[a + 2];
      final vx = positions[b] - positions[a];
      final vy = positions[b + 1] - positions[a + 1];
      final vz = positions[b + 2] - positions[a + 2];
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      _triangleRestArea[t ~/ 3] = math.sqrt(nx * nx + ny * ny + nz * nz) * 0.5;
    }
  }

  void _buildConstraints() {
    // Every mesh edge becomes a distance constraint, and every edge shared by
    // two triangles also becomes a bending constraint between the triangles'
    // opposite corners. Both fall out of one pass over the triangle list.
    final opposite = <int, int>{};
    final pairs = <int>[];
    final rest = <double>[];
    final quads = <int>[];
    final quadRest = <double>[];

    void edge(int a, int b, int other) {
      final low = a < b ? a : b;
      final high = a < b ? b : a;
      final key = low * particleCount + high;
      final seen = opposite[key];
      if (seen == null) {
        opposite[key] = other;
        pairs
          ..add(low)
          ..add(high);
        rest.add(_distanceBetween(low, high));
        return;
      }
      quads
        ..add(low)
        ..add(high)
        ..add(seen)
        ..add(other);
      quadRest.add(_dihedralAngle(low, high, seen, other));
    }

    for (var t = 0; t < triangles.length; t += 3) {
      final a = triangles[t], b = triangles[t + 1], c = triangles[t + 2];
      edge(a, b, c);
      edge(b, c, a);
      edge(c, a, b);
    }

    // Sweep the constraints in grid order rather than the order the triangle
    // pass happened to emit them. A Gauss-Seidel sweep converges far better
    // when consecutive constraints are spread across the sheet instead of
    // hammering the three edges of one triangle in a row, and the residual
    // left by a poorly ordered sweep is what feeds the stretch modes (see
    // [stretchDamping]).
    final order = List<int>.generate(rest.length, (i) => i)
      ..sort((a, b) {
        final first = pairs[a * 2].compareTo(pairs[b * 2]);
        return first != 0
            ? first
            : pairs[a * 2 + 1].compareTo(pairs[b * 2 + 1]);
      });
    _distancePairs = Int32List(rest.length * 2);
    _distanceRest = Float32List(rest.length);
    for (var i = 0; i < order.length; i++) {
      _distancePairs[i * 2] = pairs[order[i] * 2];
      _distancePairs[i * 2 + 1] = pairs[order[i] * 2 + 1];
      _distanceRest[i] = rest[order[i]];
    }

    final bendOrder = List<int>.generate(quadRest.length, (i) => i)
      ..sort((a, b) => quads[a * 4].compareTo(quads[b * 4]));
    _bendQuads = Int32List(quadRest.length * 4);
    _bendRest = Float32List(quadRest.length);
    for (var i = 0; i < bendOrder.length; i++) {
      for (var k = 0; k < 4; k++) {
        _bendQuads[i * 4 + k] = quads[bendOrder[i] * 4 + k];
      }
      _bendRest[i] = quadRest[bendOrder[i]];
    }
  }

  void _buildSpatialHash() {
    _hashTableSize = _primeAtLeast(particleCount * 2);
    _hashStart = Int32List(_hashTableSize + 1);
    _hashEntries = Int32List(particleCount);
    _pairs = Int32List(particleCount * 12);
    _pairContacts = Int32List(particleCount * 12);
    _pairNormals = Float32List(particleCount * 18);
  }

  // --- Simulation --------------------------------------------------------

  void _integrate(double h) {
    for (var i = 0; i < particleCount; i++) {
      final w = _inverseMasses[i];
      final x = i * 3;
      if (w == 0.0) {
        _previous[x] = positions[x];
        _previous[x + 1] = positions[x + 1];
        _previous[x + 2] = positions[x + 2];
        continue;
      }
      final vx = _velocities[x] + (gravity.x + _forces[x] * w) * h;
      final vy = _velocities[x + 1] + (gravity.y + _forces[x + 1] * w) * h;
      final vz = _velocities[x + 2] + (gravity.z + _forces[x + 2] * w) * h;
      _velocities[x] = vx;
      _velocities[x + 1] = vy;
      _velocities[x + 2] = vz;
      _previous[x] = positions[x];
      _previous[x + 1] = positions[x + 1];
      _previous[x + 2] = positions[x + 2];
      positions[x] += vx * h;
      positions[x + 1] += vy * h;
      positions[x + 2] += vz * h;
    }
    if (_grabbed >= 0) {
      final x = _grabbed * 3;
      positions[x] = _grabTarget.x;
      positions[x + 1] = _grabTarget.y;
      positions[x + 2] = _grabTarget.z;
    }
  }

  void _updateVelocities(double h, double velocityScale) {
    final inverseH = 1.0 / h;
    for (var i = 0; i < particleCount; i++) {
      if (_inverseMasses[i] == 0.0) continue;
      final x = i * 3;
      _velocities[x] = (positions[x] - _previous[x]) * inverseH * velocityScale;
      _velocities[x + 1] =
          (positions[x + 1] - _previous[x + 1]) * inverseH * velocityScale;
      _velocities[x + 2] =
          (positions[x + 2] - _previous[x + 2]) * inverseH * velocityScale;
    }
  }

  /// Projects the mesh-edge distance constraints.
  ///
  /// One iteration per substep means the XPBD multiplier starts at zero every
  /// time, so it drops out of the update and leaves the compliance term as
  /// the only difference from plain PBD.
  void _solveDistances(double alpha) {
    for (var k = 0; k < _distanceRest.length; k++) {
      final a = _distancePairs[k * 2] * 3;
      final b = _distancePairs[k * 2 + 1] * 3;
      final wa = _inverseMasses[_distancePairs[k * 2]];
      final wb = _inverseMasses[_distancePairs[k * 2 + 1]];
      final sum = wa + wb;
      if (sum == 0.0) continue;

      final dx = positions[b] - positions[a];
      final dy = positions[b + 1] - positions[a + 1];
      final dz = positions[b + 2] - positions[a + 2];
      final length = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (length < 1e-9) continue;

      final scale = (length - _distanceRest[k]) / (length * (sum + alpha));
      if (wa != 0.0) {
        positions[a] += dx * scale * wa;
        positions[a + 1] += dy * scale * wa;
        positions[a + 2] += dz * scale * wa;
      }
      if (wb != 0.0) {
        positions[b] -= dx * scale * wb;
        positions[b + 1] -= dy * scale * wb;
        positions[b + 2] -= dz * scale * wb;
      }
    }
  }

  /// Removes part of the relative velocity along each edge.
  ///
  /// The impulse is applied along the edge only, so it damps stretching and
  /// leaves every other motion alone. See [stretchDamping].
  void _dampStretchVelocity() {
    final k = stretchDamping.clamp(0.0, 1.0);
    for (var c = 0; c < _distanceRest.length; c++) {
      final ia = _distancePairs[c * 2];
      final ib = _distancePairs[c * 2 + 1];
      final wa = _inverseMasses[ia];
      final wb = _inverseMasses[ib];
      final sum = wa + wb;
      if (sum == 0.0) continue;
      final a = ia * 3, b = ib * 3;
      var nx = positions[b] - positions[a];
      var ny = positions[b + 1] - positions[a + 1];
      var nz = positions[b + 2] - positions[a + 2];
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length < 1e-9) continue;
      nx /= length;
      ny /= length;
      nz /= length;
      final closing =
          (_velocities[b] - _velocities[a]) * nx +
          (_velocities[b + 1] - _velocities[a + 1]) * ny +
          (_velocities[b + 2] - _velocities[a + 2]) * nz;
      final impulse = k * closing / sum;
      if (wa != 0.0) {
        _velocities[a] += nx * impulse * wa;
        _velocities[a + 1] += ny * impulse * wa;
        _velocities[a + 2] += nz * impulse * wa;
      }
      if (wb != 0.0) {
        _velocities[b] -= nx * impulse * wb;
        _velocities[b + 1] -= ny * impulse * wb;
        _velocities[b + 2] -= nz * impulse * wb;
      }
    }
  }

  /// Projects the dihedral bending constraints.
  ///
  /// The correction carries a `sqrt(1 - d^2)` factor that cancels the
  /// derivative of `acos`, so a flat sheet (the singular configuration for a
  /// naive angle constraint) is handled without a special case.
  void _solveBending(double stiffness) {
    for (var k = 0; k < _bendRest.length; k++) {
      final i1 = _bendQuads[k * 4];
      final i2 = _bendQuads[k * 4 + 1];
      final i3 = _bendQuads[k * 4 + 2];
      final i4 = _bendQuads[k * 4 + 3];
      final w1 = _inverseMasses[i1];
      final w2 = _inverseMasses[i2];
      final w3 = _inverseMasses[i3];
      final w4 = _inverseMasses[i4];
      if (w1 + w2 + w3 + w4 == 0.0) continue;

      final o = i1 * 3;
      // Everything is relative to the first shared-edge particle.
      final p2x = positions[i2 * 3] - positions[o];
      final p2y = positions[i2 * 3 + 1] - positions[o + 1];
      final p2z = positions[i2 * 3 + 2] - positions[o + 2];
      final p3x = positions[i3 * 3] - positions[o];
      final p3y = positions[i3 * 3 + 1] - positions[o + 1];
      final p3z = positions[i3 * 3 + 2] - positions[o + 2];
      final p4x = positions[i4 * 3] - positions[o];
      final p4y = positions[i4 * 3 + 1] - positions[o + 1];
      final p4z = positions[i4 * 3 + 2] - positions[o + 2];

      var n1x = p2y * p3z - p2z * p3y;
      var n1y = p2z * p3x - p2x * p3z;
      var n1z = p2x * p3y - p2y * p3x;
      var n2x = p2y * p4z - p2z * p4y;
      var n2y = p2z * p4x - p2x * p4z;
      var n2z = p2x * p4y - p2y * p4x;
      final len1 = math.sqrt(n1x * n1x + n1y * n1y + n1z * n1z);
      final len2 = math.sqrt(n2x * n2x + n2y * n2y + n2z * n2z);
      // A collapsed triangle has no meaningful normal. The floor is relative
      // to the rest geometry rather than an absolute epsilon, because these
      // cross products carry twice the triangle's area: a fixed epsilon is
      // permissive enough at cloth scale to let a folded, nearly degenerate
      // triangle drive the correction, which is how a hard fold around a body
      // turns into a blow-up.
      if (len1 < _degenerateArea || len2 < _degenerateArea) continue;
      n1x /= len1;
      n1y /= len1;
      n1z /= len1;
      n2x /= len2;
      n2y /= len2;
      n2z /= len2;

      final d = (n1x * n2x + n1y * n2y + n1z * n2z).clamp(-1.0, 1.0);

      // q3 = (p2 x n2 + (n1 x p2) d) / |p2 x p3|, and q4 mirrors it.
      final q3x =
          ((p2y * n2z - p2z * n2y) + (n1y * p2z - n1z * p2y) * d) / len1;
      final q3y =
          ((p2z * n2x - p2x * n2z) + (n1z * p2x - n1x * p2z) * d) / len1;
      final q3z =
          ((p2x * n2y - p2y * n2x) + (n1x * p2y - n1y * p2x) * d) / len1;
      final q4x =
          ((p2y * n1z - p2z * n1y) + (n2y * p2z - n2z * p2y) * d) / len2;
      final q4y =
          ((p2z * n1x - p2x * n1z) + (n2z * p2x - n2x * p2z) * d) / len2;
      final q4z =
          ((p2x * n1y - p2y * n1x) + (n2x * p2y - n2y * p2x) * d) / len2;
      final q2x =
          -((p3y * n2z - p3z * n2y) + (n1y * p3z - n1z * p3y) * d) / len1 -
          ((p4y * n1z - p4z * n1y) + (n2y * p4z - n2z * p4y) * d) / len2;
      final q2y =
          -((p3z * n2x - p3x * n2z) + (n1z * p3x - n1x * p3z) * d) / len1 -
          ((p4z * n1x - p4x * n1z) + (n2z * p4x - n2x * p4z) * d) / len2;
      final q2z =
          -((p3x * n2y - p3y * n2x) + (n1x * p3y - n1y * p3x) * d) / len1 -
          ((p4x * n1y - p4y * n1x) + (n2x * p4y - n2y * p4x) * d) / len2;
      final q1x = -q2x - q3x - q4x;
      final q1y = -q2y - q3y - q4y;
      final q1z = -q2z - q3z - q4z;

      final denominator =
          w1 * (q1x * q1x + q1y * q1y + q1z * q1z) +
          w2 * (q2x * q2x + q2y * q2y + q2z * q2z) +
          w3 * (q3x * q3x + q3y * q3y + q3z * q3z) +
          w4 * (q4x * q4x + q4y * q4y + q4z * q4z);
      if (denominator < 1e-12) continue;

      final scale =
          -stiffness *
          math.sqrt(1.0 - d * d) *
          (math.acos(d) - _bendRest[k]) /
          denominator;
      if (scale == 0.0) continue;

      positions[o] += scale * w1 * q1x;
      positions[o + 1] += scale * w1 * q1y;
      positions[o + 2] += scale * w1 * q1z;
      positions[i2 * 3] += scale * w2 * q2x;
      positions[i2 * 3 + 1] += scale * w2 * q2y;
      positions[i2 * 3 + 2] += scale * w2 * q2z;
      positions[i3 * 3] += scale * w3 * q3x;
      positions[i3 * 3 + 1] += scale * w3 * q3y;
      positions[i3 * 3 + 2] += scale * w3 * q3z;
      positions[i4 * 3] += scale * w4 * q4x;
      positions[i4 * 3 + 1] += scale * w4 * q4y;
      positions[i4 * 3 + 2] += scale * w4 * q4z;
    }
  }

  double _dihedralAngle(int i1, int i2, int i3, int i4) {
    final o = i1 * 3;
    final p2 = Vector3(
      positions[i2 * 3] - positions[o],
      positions[i2 * 3 + 1] - positions[o + 1],
      positions[i2 * 3 + 2] - positions[o + 2],
    );
    final p3 = Vector3(
      positions[i3 * 3] - positions[o],
      positions[i3 * 3 + 1] - positions[o + 1],
      positions[i3 * 3 + 2] - positions[o + 2],
    );
    final p4 = Vector3(
      positions[i4 * 3] - positions[o],
      positions[i4 * 3 + 1] - positions[o + 1],
      positions[i4 * 3 + 2] - positions[o + 2],
    );
    final n1 = p2.cross(p3);
    final n2 = p2.cross(p4);
    if (n1.length < 1e-9 || n2.length < 1e-9) return math.pi;
    return math.acos(n1.normalized().dot(n2.normalized()).clamp(-1.0, 1.0));
  }

  /// Accumulates per-triangle drag and lift into the particle force stream.
  ///
  /// Drag is the pressure on the face, so it depends on the airflow's
  /// component along the normal; lift acts across the flow and is what turns
  /// a steady wind into a travelling ripple.
  void _applyAerodynamics() {
    _forces.fillRange(0, _forces.length, 0.0);
    if (wind.length2 == 0.0 &&
        dragCoefficient == 0.0 &&
        liftCoefficient == 0.0) {
      return;
    }
    final tris = triangles;
    final half = 0.5 * airDensity;
    for (var t = 0; t < tris.length; t += 3) {
      final a = tris[t] * 3, b = tris[t + 1] * 3, c = tris[t + 2] * 3;
      final ux = positions[c] - positions[a];
      final uy = positions[c + 1] - positions[a + 1];
      final uz = positions[c + 2] - positions[a + 2];
      final vx = positions[b] - positions[a];
      final vy = positions[b + 1] - positions[a + 1];
      final vz = positions[b + 2] - positions[a + 2];
      var nx = uy * vz - uz * vy;
      var ny = uz * vx - ux * vz;
      var nz = ux * vy - uy * vx;
      final crossLength = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (crossLength < 1e-12) continue;
      final area = _triangleRestArea[t ~/ 3];
      nx /= crossLength;
      ny /= crossLength;
      nz /= crossLength;

      // Airflow past the face, gusted by a cheap divergence-free-ish swirl so
      // the sheet never settles into a steady state.
      final cx = (positions[a] + positions[b] + positions[c]) / 3.0;
      final cy = (positions[a + 1] + positions[b + 1] + positions[c + 1]) / 3.0;
      final cz = (positions[a + 2] + positions[b + 2] + positions[c + 2]) / 3.0;
      final gust = windGust == 0.0
          ? 0.0
          : windGust *
                math.sin(cx * 1.7 + cy * 0.9 + _time * 2.6) *
                math.cos(cz * 2.1 - cy * 1.3 + _time * 1.7);
      // Airflow relative to the face: the gusted wind less the face's own
      // velocity, so a sheet moving downwind feels less of it.
      final gusted = 1.0 + gust;
      final rx =
          wind.x * gusted -
          (_velocities[a] + _velocities[b] + _velocities[c]) / 3.0;
      final ry =
          wind.y * gusted -
          (_velocities[a + 1] + _velocities[b + 1] + _velocities[c + 1]) / 3.0;
      final rz =
          wind.z * gusted -
          (_velocities[a + 2] + _velocities[b + 2] + _velocities[c + 2]) / 3.0;
      final speed = math.sqrt(rx * rx + ry * ry + rz * rz);
      if (speed < 1e-6) continue;

      final normalFlow = nx * rx + ny * ry + nz * rz;
      final pressure = half * area * dragCoefficient * normalFlow.abs();
      var fx = pressure * normalFlow * nx;
      var fy = pressure * normalFlow * ny;
      var fz = pressure * normalFlow * nz;

      if (liftCoefficient != 0.0) {
        // Lift acts along (n x r) x r, perpendicular to the flow and in the
        // plane the normal leans into.
        final sx = ny * rz - nz * ry;
        final sy = nz * rx - nx * rz;
        final sz = nx * ry - ny * rx;
        var lx = sy * rz - sz * ry;
        var ly = sz * rx - sx * rz;
        var lz = sx * ry - sy * rx;
        final liftLength = math.sqrt(lx * lx + ly * ly + lz * lz);
        if (liftLength > 1e-9) {
          final magnitude =
              half * area * liftCoefficient * speed * normalFlow.abs();
          lx /= liftLength;
          ly /= liftLength;
          lz /= liftLength;
          fx += lx * magnitude;
          fy += ly * magnitude;
          fz += lz * magnitude;
        }
      }

      final third = 1.0 / 3.0;
      _forces[a] += fx * third;
      _forces[a + 1] += fy * third;
      _forces[a + 2] += fz * third;
      _forces[b] += fx * third;
      _forces[b + 1] += fy * third;
      _forces[b + 2] += fz * third;
      _forces[c] += fx * third;
      _forces[c + 1] += fy * third;
      _forces[c + 2] += fz * third;
    }
  }

  /// Pushes the sheet out of the ground and the colliders, then damps the
  /// sliding it did this substep so it grips instead of skating.
  ///
  /// [sweep] is how far through the step's collider motion this substep sits.
  void _solveColliders(double sweep) {
    final ground = groundHeight;
    _contactFlags.fillRange(0, particleCount, 0);
    for (var i = 0; i < particleCount; i++) {
      if (_inverseMasses[i] == 0.0) continue;
      final x = i * 3;

      if (ground != null) {
        // The floor holds the sheet off by its own half-thickness, not by
        // [contactOffset]. That margin is tuned for whatever body the scene
        // sweeps through the cloth, and a body-sized gap applied to the floor
        // raises it out from under a sheet that was cut to hang lower,
        // clamping the hem up into the rows above it and compressing the
        // lattice against itself for as long as the scene runs.
        final floor = ground + thickness;
        if (positions[x + 1] < floor) {
          final depth = floor - positions[x + 1];
          _separate(x, 0.0, depth, 0.0);
          _recordContact(x, 0.0, 1.0, 0.0);
          _applyContactFriction(x, 0.0, 1.0, 0.0, depth);
        }
      }

      for (final collider in colliders) {
        final depth = collider.contact(
          positions[x],
          positions[x + 1],
          positions[x + 2],
          sweep,
          contactOffset,
          _contactNormal,
        );
        if (depth <= 0.0) continue;
        _separate(
          x,
          _contactNormal.x * depth,
          _contactNormal.y * depth,
          _contactNormal.z * depth,
        );
        _recordContact(x, _contactNormal.x, _contactNormal.y, _contactNormal.z);
        _applyContactFriction(
          x,
          _contactNormal.x,
          _contactNormal.y,
          _contactNormal.z,
          depth,
        );
      }
    }
  }

  final Vector3 _contactNormal = Vector3.zero();

  // One contact slot per particle, filled by the collider pass and consumed by
  // the velocity pass in the same substep.
  late final Uint8List _contactFlags = Uint8List(particleCount);
  late final Float32List _contactNormals = Float32List(particleCount * 3);

  /// Cancels the velocity a contact is still driving into the surface.
  ///
  /// [_separate] deliberately leaves velocity alone, so this is where a
  /// contact actually stops the cloth: it removes the part of the velocity
  /// heading into whatever was touched, and leaves everything along the
  /// surface for friction and the weave to deal with. Without it the sheet
  /// keeps accelerating into a collider it is already resting on.
  void _solveContactVelocity() {
    for (var i = 0; i < particleCount; i++) {
      if (_contactFlags[i] == 0 || _inverseMasses[i] == 0.0) continue;
      final x = i * 3;
      final nx = _contactNormals[x];
      final ny = _contactNormals[x + 1];
      final nz = _contactNormals[x + 2];
      final into =
          _velocities[x] * nx +
          _velocities[x + 1] * ny +
          _velocities[x + 2] * nz;
      if (into >= 0.0) continue;
      _velocities[x] -= nx * into;
      _velocities[x + 1] -= ny * into;
      _velocities[x + 2] -= nz * into;
    }
    // Pairs the position solve actually separated this substep, with the
    // normal it used. Testing for overlap again here would find none: the
    // solve just pushed them to exactly the separation distance, so every
    // pair would be filtered out and nothing would ever damp a contact.
    for (var k = 0; k < _pairContactCount; k++) {
      final i = _pairContacts[k * 2];
      final j = _pairContacts[k * 2 + 1];
      final wi = _inverseMasses[i];
      final wj = _inverseMasses[j];
      final sum = wi + wj;
      if (sum == 0.0) continue;
      final x = i * 3, y = j * 3;
      final nx = _pairNormals[k * 3];
      final ny = _pairNormals[k * 3 + 1];
      final nz = _pairNormals[k * 3 + 2];
      final closing =
          (_velocities[y] - _velocities[x]) * nx +
          (_velocities[y + 1] - _velocities[x + 1]) * ny +
          (_velocities[y + 2] - _velocities[x + 2]) * nz;
      if (closing >= 0.0) continue;
      final impulse = closing / sum;
      _velocities[x] += nx * impulse * wi;
      _velocities[x + 1] += ny * impulse * wi;
      _velocities[x + 2] += nz * impulse * wi;
      _velocities[y] -= nx * impulse * wj;
      _velocities[y + 1] -= ny * impulse * wj;
      _velocities[y + 2] -= nz * impulse * wj;
    }
  }

  void _recordPairContact(int i, int j, double nx, double ny, double nz) {
    if (_pairContactCount >= _pairs.length ~/ 2) return;
    _pairContacts[_pairContactCount * 2] = i;
    _pairContacts[_pairContactCount * 2 + 1] = j;
    _pairNormals[_pairContactCount * 3] = nx;
    _pairNormals[_pairContactCount * 3 + 1] = ny;
    _pairNormals[_pairContactCount * 3 + 2] = nz;
    _pairContactCount++;
  }

  void _recordContact(int offset, double nx, double ny, double nz) {
    _contactFlags[offset ~/ 3] = 1;
    _contactNormals[offset] = nx;
    _contactNormals[offset + 1] = ny;
    _contactNormals[offset + 2] = nz;
  }

  /// Moves a particle out of a contact without that showing up as velocity.
  ///
  /// Velocity is read back as the position change over the substep, so a
  /// correction of a fixed size reports a speed of that size over h: halve the
  /// substep and the same overlap hands back twice the speed. Unlike the weave
  /// constraints, whose per-substep violation shrinks with the substep, a
  /// contact's depth is set by where the surfaces are, so nothing damps that
  /// out and the sheet buzzes harder the more substeps it is given. Carrying
  /// the previous position along with the correction leaves the particle's
  /// actual motion for the substep unchanged, so separation stays a matter of
  /// position and never invents momentum.
  void _separate(int offset, double dx, double dy, double dz) {
    positions[offset] += dx;
    positions[offset + 1] += dy;
    positions[offset + 2] += dz;
    _previous[offset] += dx;
    _previous[offset + 1] += dy;
    _previous[offset + 2] += dz;
  }

  // Removes up to `friction * depth` of the tangential motion this substep,
  // the standard position-level Coulomb approximation.
  void _applyContactFriction(
    int x,
    double nx,
    double ny,
    double nz,
    double depth,
  ) {
    if (friction <= 0.0) return;
    var dx = positions[x] - _previous[x];
    var dy = positions[x + 1] - _previous[x + 1];
    var dz = positions[x + 2] - _previous[x + 2];
    final along = dx * nx + dy * ny + dz * nz;
    dx -= nx * along;
    dy -= ny * along;
    dz -= nz * along;
    final slide = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (slide < 1e-9) return;
    final scale = math.min(1.0, friction * depth / slide);
    positions[x] -= dx * scale;
    positions[x + 1] -= dy * scale;
    positions[x + 2] -= dz * scale;
  }

  // --- Self-collision ----------------------------------------------------

  void _collectSelfCollisionPairs() {
    _pairCount = 0;
    final cell = thickness * 2.0;
    final inverseCell = 1.0 / cell;
    final table = _hashTableSize;

    _hashStart.fillRange(0, table + 1, 0);
    for (var i = 0; i < particleCount; i++) {
      _hashStart[_hashOf(i, inverseCell)]++;
    }
    var running = 0;
    for (var h = 0; h < table; h++) {
      running += _hashStart[h];
      _hashStart[h] = running;
    }
    _hashStart[table] = running;
    for (var i = 0; i < particleCount; i++) {
      final h = _hashOf(i, inverseCell);
      _hashStart[h]--;
      _hashEntries[_hashStart[h]] = i;
    }

    final maxPairs = _pairs.length ~/ 2;
    final minimum = thickness * 2.0;
    // Widened so a pair that drifts together mid-step is already on the list.
    final search = minimum * 1.5;
    final searchSquared = search * search;
    for (var i = 0; i < particleCount; i++) {
      final x = i * 3;
      final cx = (positions[x] * inverseCell).floor();
      final cy = (positions[x + 1] * inverseCell).floor();
      final cz = (positions[x + 2] * inverseCell).floor();
      for (var gx = cx - 1; gx <= cx + 1; gx++) {
        for (var gy = cy - 1; gy <= cy + 1; gy++) {
          for (var gz = cz - 1; gz <= cz + 1; gz++) {
            final h = _hashCell(gx, gy, gz);
            for (var s = _hashStart[h]; s < _hashStart[h + 1]; s++) {
              final j = _hashEntries[s];
              // Each pair once, and never one the weave already constrains.
              if (j <= i) continue;
              if (_tooCloseOnSheet(i, j)) continue;
              final y = j * 3;
              final dx = positions[y] - positions[x];
              final dy = positions[y + 1] - positions[x + 1];
              final dz = positions[y + 2] - positions[x + 2];
              if (dx * dx + dy * dy + dz * dz > searchSquared) continue;
              if (_pairCount >= maxPairs) return;
              _pairs[_pairCount * 2] = i;
              _pairs[_pairCount * 2 + 1] = j;
              _pairCount++;
            }
          }
        }
      }
    }
  }

  void _solveSelfCollisions() {
    _pairContactCount = 0;
    final minimum = thickness * 2.0;
    for (var k = 0; k < _pairCount; k++) {
      final i = _pairs[k * 2];
      final j = _pairs[k * 2 + 1];
      final wi = _inverseMasses[i];
      final wj = _inverseMasses[j];
      final sum = wi + wj;
      if (sum == 0.0) continue;
      final x = i * 3, y = j * 3;
      final dx = positions[y] - positions[x];
      final dy = positions[y + 1] - positions[x + 1];
      final dz = positions[y + 2] - positions[x + 2];
      final distanceSquared = dx * dx + dy * dy + dz * dz;
      if (distanceSquared >= minimum * minimum || distanceSquared < 1e-12) {
        continue;
      }
      final distance = math.sqrt(distanceSquared);
      final depth = minimum - distance;
      final scale = depth / (distance * sum);
      _separate(x, -dx * scale * wi, -dy * scale * wi, -dz * scale * wi);
      _separate(y, dx * scale * wj, dy * scale * wj, dz * scale * wj);
      final nx = dx / distance, ny = dy / distance, nz = dz / distance;
      _recordPairContact(i, j, nx, ny, nz);
      if (wi != 0.0) _applyContactFriction(x, -nx, -ny, -nz, depth);
      if (wj != 0.0) _applyContactFriction(y, nx, ny, nz, depth);
    }
  }

  /// Whether two particles are close enough along the sheet that a contact
  /// between them would be nonsense.
  ///
  /// Self-collision is for two layers of fabric meeting. Particles a few cells
  /// apart are not two layers, they are the same piece of cloth: a crease
  /// folds them together legitimately, and there is no separation the solver
  /// can enforce that the weave will not immediately undo. Left in, they
  /// generate contacts a whole cell deep every frame and the sheet thrashes.
  ///
  /// The exclusion has to reach far enough that the surface between the pair
  /// is longer than the separation being enforced, so it scales with the
  /// thickness rather than being fixed at the immediate neighbours.
  bool _tooCloseOnSheet(int i, int j) {
    final di = ((i ~/ columns) - (j ~/ columns)).abs();
    if (di > _selfCollisionSkip) return false;
    final dj = ((i % columns) - (j % columns)).abs();
    return dj <= _selfCollisionSkip;
  }

  int get _selfCollisionSkip {
    final cells = (thickness * 2.0 / _spacing).ceil() + 1;
    return cells < 2 ? 2 : cells;
  }

  int _hashOf(int particle, double inverseCell) => _hashCell(
    (positions[particle * 3] * inverseCell).floor(),
    (positions[particle * 3 + 1] * inverseCell).floor(),
    (positions[particle * 3 + 2] * inverseCell).floor(),
  );

  // The multiply-xor hash from Teschner et al. The constants are theirs; only
  // the spread matters, so the 32-bit truncation dart2js applies to `^` is
  // harmless here.
  int _hashCell(int x, int y, int z) =>
      ((x * 92837111) ^ (y * 689287499) ^ (z * 283923481)) % _hashTableSize;

  static int _primeAtLeast(int value) {
    var candidate = value | 1;
    while (!_isPrime(candidate)) {
      candidate += 2;
    }
    return candidate;
  }

  static bool _isPrime(int value) {
    if (value < 2) return false;
    if (value.isEven) return value == 2;
    for (var d = 3; d * d <= value; d += 2) {
      if (value % d == 0) return false;
    }
    return true;
  }
}
