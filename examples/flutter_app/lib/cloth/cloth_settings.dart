// Solver settings shared by the cloth demos.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'cloth_solver.dart';
import 'cloth_wind.dart';

/// How finely the sheets are tessellated.
enum ClothQuality {
  low('Low', 0.55),
  medium('Medium', 0.75),
  high('High', 1.0);

  const ClothQuality(this.label, this.scale);

  final String label;

  /// Multiplies each scene's base grid resolution.
  final double scale;

  /// This tier's grid size for a scene whose base resolution is [base].
  int gridSize(int base) => math.max(4, (base * scale).round());
}

/// Everything the control panel drives, held outside the demo widgets so a
/// scene change or a rebuild does not reset it.
///
/// The defaults here are the tuned ones every demo starts from; a scene
/// overrides one only where it has to (the multi-sheet corridor cannot afford
/// self-collision).
///
/// [applyTo] is cheap enough to run on every sheet every frame, which is what
/// the demos do; a slider then takes effect immediately with no wiring.
class ClothSettings {
  final ClothWind wind = ClothWind();

  /// Tessellation. Unlike the rest, this cannot be applied in place; the scene
  /// has to be rebuilt.
  ClothQuality quality = ClothQuality.high;

  /// Constraint solver substeps per frame. The single biggest cost, and what
  /// buys inextensibility.
  int substeps = 2;

  /// Inverse stretch stiffness. Zero is inextensible; woven fabric is close to
  /// it, and a knit gives a little.
  double stretchCompliance = 3.29e-6;

  /// Resistance to folding, 0 (limp) to 1 (stiff as card).
  double bending = 0.15;

  /// The fabric's internal viscosity; see [ClothSolver.stretchDamping].
  double stretchDamping = 0.49;

  /// Bulk velocity shed per second.
  double damping = 0.50;

  /// Grip against colliders and the sheet itself.
  double friction = 0.51;

  /// Gravity, meters per second squared.
  double gravity = 9.8;

  /// Air density, scaling both aerodynamic terms.
  double airDensity = 1.20;

  /// Pressure drag across the faces: what makes a sheet snap and billow.
  double dragCoefficient = 1.20;

  /// Lift across the airflow: what sets up the travelling ripple.
  double liftCoefficient = 0.35;

  /// The gap the sheet is held off colliders and the ground.
  double contactOffset = 0.02;

  /// The sheet's half-thickness, as a fraction of the grid spacing.
  ///
  /// Only self-collision uses it, and it is the single most important number
  /// there. The solver holds non-adjacent particles two of these apart, in
  /// metres, so tying it to the spacing means a coarse sheet pretends to be
  /// thick fabric: at 0.4 a 12 cm grid is a 9 cm thick duvet, and ordinary
  /// wind ripples read as two layers colliding. The solver then shoves them
  /// apart while the weave pulls them back, and the sheet buzzes. Keep this
  /// small enough that only a real fold registers.
  double thicknessRatio = 0.15;

  /// How high a hanging sheet's hem sits above the floor.
  ///
  /// Unlike the rest, this is a shape rather than a solver value, so the
  /// scene has to be rebuilt for a change to take: the sheet is cut to reach
  /// from its rail down to here.
  double groundOffset = 0.25;

  /// Whether sheets collide with themselves.
  bool selfCollision = true;

  /// Applies everything but the wind vector (which is time-varying, see
  /// [ClothWind.applyTo]) and the tessellation to [solver].
  void applyTo(ClothSolver solver) {
    solver
      ..substeps = substeps
      ..stretchCompliance = stretchCompliance
      ..bendStiffness = bending
      ..stretchDamping = stretchDamping
      ..damping = damping
      ..friction = friction
      ..airDensity = airDensity
      ..dragCoefficient = dragCoefficient
      ..liftCoefficient = liftCoefficient
      ..contactOffset = contactOffset
      ..thicknessRatio = thicknessRatio
      ..selfCollision = selfCollision;
    solver.gravity.setValues(0.0, -gravity, 0.0);
  }

  /// Overwrites every value from [other], including the wind.
  void copyFrom(ClothSettings other) {
    quality = other.quality;
    substeps = other.substeps;
    stretchCompliance = other.stretchCompliance;
    bending = other.bending;
    stretchDamping = other.stretchDamping;
    damping = other.damping;
    friction = other.friction;
    gravity = other.gravity;
    airDensity = other.airDensity;
    dragCoefficient = other.dragCoefficient;
    liftCoefficient = other.liftCoefficient;
    contactOffset = other.contactOffset;
    thicknessRatio = other.thicknessRatio;
    groundOffset = other.groundOffset;
    selfCollision = other.selfCollision;
    wind
      ..speed = other.wind.speed
      ..headingDegrees = other.wind.headingDegrees
      ..gust = other.wind.gust;
  }

  /// Prints these settings to the console as the Dart that reproduces them.
  ///
  /// Tuning happens on the sliders, so the panel's print button emits a
  /// cascade that can be pasted straight over the defaults above.
  void printSource() => debugPrint(toSource());

  String toSource() {
    String f(double value, [int digits = 2]) => value.toStringAsFixed(digits);
    return '''
ClothSettings()
  ..quality = ClothQuality.${quality.name}
  ..substeps = $substeps
  ..stretchCompliance = ${f(stretchCompliance * 1e6)}e-6
  ..bending = ${f(bending)}
  ..stretchDamping = ${f(stretchDamping)}
  ..damping = ${f(damping)}
  ..friction = ${f(friction)}
  ..gravity = ${f(gravity, 1)}
  ..airDensity = ${f(airDensity)}
  ..dragCoefficient = ${f(dragCoefficient)}
  ..liftCoefficient = ${f(liftCoefficient)}
  ..contactOffset = ${f(contactOffset, 3)}
  ..thicknessRatio = ${f(thicknessRatio)}
  ..groundOffset = ${f(groundOffset, 3)}
  ..selfCollision = $selfCollision
  ..wind.speed = ${f(wind.speed)}
  ..wind.headingDegrees = ${f(wind.headingDegrees, 1)}
  ..wind.gust = ${f(wind.gust)};''';
  }
}
