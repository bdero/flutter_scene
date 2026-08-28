/// Sculpting a [HeightField]: the brushes that raise, lower, smooth and
/// flatten ground.
///
/// Pure edits over the samples. A brush takes a world position and changes
/// the field; rebuilding the mesh and writing the payload are the caller's
/// job, because a stroke is many of these and only wants one rebuild.
library;

import 'dart:math' as math;

import 'package:flutter_scene/src/geometry/terrain.dart';

/// What a stroke does to the ground under it.
/// {@category Geometry}
enum TerrainBrushKind {
  /// Pushes the ground up, or down when the strength is negative.
  raise,

  /// Pulls samples toward the average of their neighbours.
  smooth,

  /// Pulls samples toward one height, for a plateau or a road.
  flatten,
}

/// A brush: where it reaches and how hard.
/// {@category Geometry}
class TerrainBrush {
  /// Creates a brush.
  const TerrainBrush({
    this.kind = TerrainBrushKind.raise,
    this.radius = 4.0,
    this.strength = 1.0,
    this.falloff = 0.5,
    this.targetHeight = 0.0,
  });

  /// What the stroke does.
  final TerrainBrushKind kind;

  /// How far the brush reaches, in world units.
  final double radius;

  /// How much it moves the ground per second of stroke. Negative digs.
  final double strength;

  /// Where the brush stops being at full strength, as a fraction of the
  /// radius: `0` is a hard edge, `1` a dome that peaks only at the centre.
  final double falloff;

  /// The height [TerrainBrushKind.flatten] pulls toward.
  final double targetHeight;

  /// The brush's weight at [distance] from its centre, `0` to `1`.
  ///
  /// Smoothstep between the falloff edge and the rim rather than a linear
  /// ramp, so a stroke leaves a rounded hill instead of a cone.
  double weightAt(double distance) {
    if (distance >= radius) return 0.0;
    final inner = radius * falloff.clamp(0.0, 1.0);
    if (distance <= inner) return 1.0;
    final span = radius - inner;
    if (span <= 0) return 1.0;
    final t = 1.0 - ((distance - inner) / span);
    return t * t * (3.0 - 2.0 * t);
  }
}

/// Applies [brush] to [field] centred on world ([x], [z]) for [deltaSeconds]
/// of stroke, and reports the sample range it touched.
///
/// The range is returned so a caller can rebuild only what moved; null means
/// the stroke fell outside the field entirely.
/// {@category Geometry}
({int minColumn, int minRow, int maxColumn, int maxRow})? sculptTerrain(
  HeightField field, {
  required TerrainBrush brush,
  required double x,
  required double z,
  double deltaSeconds = 1.0,
}) {
  if (brush.radius <= 0 || deltaSeconds <= 0) return null;

  final stepX = field.width / (field.columns - 1);
  final stepZ = field.depth / (field.rows - 1);
  final centreColumn = (x + field.width / 2) / stepX;
  final centreRow = (z + field.depth / 2) / stepZ;
  final spanColumns = (brush.radius / stepX).ceil();
  final spanRows = (brush.radius / stepZ).ceil();

  final minColumn = math.max(0, (centreColumn - spanColumns).floor());
  final maxColumn = math.min(
    field.columns - 1,
    (centreColumn + spanColumns).ceil(),
  );
  final minRow = math.max(0, (centreRow - spanRows).floor());
  final maxRow = math.min(field.rows - 1, (centreRow + spanRows).ceil());
  if (minColumn > maxColumn || minRow > maxRow) return null;

  // Smoothing reads neighbours, so it reads from a snapshot: sampling
  // half-updated ground makes the result depend on which corner the loop
  // started from.
  final source = brush.kind == TerrainBrushKind.smooth
      ? List<double>.from(field.heights)
      : null;

  var touched = false;
  for (var r = minRow; r <= maxRow; r++) {
    final sampleZ = -field.depth / 2 + stepZ * r;
    for (var c = minColumn; c <= maxColumn; c++) {
      final sampleX = -field.width / 2 + stepX * c;
      final dx = sampleX - x;
      final dz = sampleZ - z;
      final weight = brush.weightAt(math.sqrt(dx * dx + dz * dz));
      if (weight <= 0) continue;
      touched = true;

      final index = r * field.columns + c;
      final current = field.heights[index];
      final amount = weight * brush.strength * deltaSeconds;
      field.heights[index] = switch (brush.kind) {
        TerrainBrushKind.raise => current + amount,
        TerrainBrushKind.flatten =>
          current + (brush.targetHeight - current) * amount.clamp(0.0, 1.0),
        TerrainBrushKind.smooth => () {
          final samples = source!;
          var total = 0.0;
          var count = 0;
          for (var nr = r - 1; nr <= r + 1; nr++) {
            for (var nc = c - 1; nc <= c + 1; nc++) {
              if (nr < 0 || nc < 0) continue;
              if (nr >= field.rows || nc >= field.columns) continue;
              total += samples[nr * field.columns + nc];
              count++;
            }
          }
          final average = total / count;
          return current + (average - current) * amount.clamp(0.0, 1.0);
        }(),
      };
    }
  }
  if (!touched) return null;
  return (
    minColumn: minColumn,
    minRow: minRow,
    maxColumn: maxColumn,
    maxRow: maxRow,
  );
}
