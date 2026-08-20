// Solver settings shared by the cloth demos.

import 'dart:math' as math;

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
/// [applyTo] is cheap enough to run on every sheet every frame, which is what
/// the demos do; a slider then takes effect immediately with no wiring.
class ClothSettings {
  final ClothWind wind = ClothWind();

  /// Tessellation. Unlike the rest, this cannot be applied in place; the scene
  /// has to be rebuilt.
  ClothQuality quality = ClothQuality.medium;

  /// Constraint solver substeps per frame. The single biggest cost, and what
  /// buys inextensibility.
  int substeps = 12;

  /// Inverse stretch stiffness. Zero is inextensible; woven fabric is close to
  /// it, and a knit gives a little.
  double stretchCompliance = 0.0;

  /// Resistance to folding, 0 (limp) to 1 (stiff as card).
  double bending = 0.25;

  /// The fabric's internal viscosity; see [ClothSolver.stretchDamping].
  double stretchDamping = 0.25;

  /// Bulk velocity shed per second.
  double damping = 0.1;

  /// Grip against colliders and the sheet itself.
  double friction = 0.35;

  /// Gravity, meters per second squared.
  double gravity = 9.81;

  /// Air density, scaling both aerodynamic terms.
  double airDensity = 1.2;

  /// Pressure drag across the faces: what makes a sheet snap and billow.
  double dragCoefficient = 1.2;

  /// Lift across the airflow: what sets up the travelling ripple.
  double liftCoefficient = 0.35;

  /// The gap the sheet is held off colliders and the ground.
  double contactOffset = 0.02;

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
      ..selfCollision = selfCollision;
    solver.gravity.setValues(0.0, -gravity, 0.0);
  }
}
