import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vm;

/// Poisson-disc spatial point distribution generator for natural obstacle and foliage scattering.
/// {@category Gameplay kit}
class PoissonDiscSampler {
  /// Generates a set of 2D points within a rectangular area with minimum separation [minDistance].
  ///
  /// When [seed] is null, a fresh random sequence is used. Pass a specific integer [seed]
  /// for deterministic generation across runs.
  static List<vm.Vector2> sampleRect(
    double width,
    double height,
    double minDistance, {
    int maxCandidates = 30,
    int? seed,
  }) {
    if (minDistance <= 0.0) {
      throw ArgumentError.value(
        minDistance,
        'minDistance',
        'minDistance must be positive.',
      );
    }
    if (width <= 0.0 || height <= 0.0) {
      throw ArgumentError('width and height must be positive.');
    }

    final rng = seed != null ? math.Random(seed) : math.Random();
    final cellSize = minDistance / math.sqrt(2);
    final gridWidth = (width / cellSize).ceil();
    final gridHeight = (height / cellSize).ceil();

    final grid = List<int?>.filled(gridWidth * gridHeight, null);
    final points = <vm.Vector2>[];
    final active = <int>[];

    // Initial seed point
    final p0 = vm.Vector2(rng.nextDouble() * width, rng.nextDouble() * height);
    points.add(p0);
    grid[(p0.y ~/ cellSize) * gridWidth + (p0.x ~/ cellSize)] = 0;
    active.add(0);

    while (active.isNotEmpty) {
      final randIdx = rng.nextInt(active.length);
      final pointIdx = active[randIdx];
      final point = points[pointIdx];
      var found = false;

      for (var i = 0; i < maxCandidates; i++) {
        final angle = rng.nextDouble() * 2 * math.pi;
        final dist = minDistance * (1.0 + rng.nextDouble());
        final candidate =
            point + vm.Vector2(math.cos(angle), math.sin(angle)) * dist;

        if (candidate.x >= 0 &&
            candidate.x < width &&
            candidate.y >= 0 &&
            candidate.y < height) {
          final cellX = candidate.x ~/ cellSize;
          final cellY = candidate.y ~/ cellSize;

          var fits = true;
          for (var dy = -2; dy <= 2 && fits; dy++) {
            for (var dx = -2; dx <= 2 && fits; dx++) {
              final nx = cellX + dx;
              final ny = cellY + dy;
              if (nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridHeight) {
                final neighborIdx = grid[ny * gridWidth + nx];
                if (neighborIdx != null) {
                  if ((candidate - points[neighborIdx]).length < minDistance) {
                    fits = false;
                  }
                }
              }
            }
          }

          if (fits) {
            points.add(candidate);
            grid[cellY * gridWidth + cellX] = points.length - 1;
            active.add(points.length - 1);
            found = true;
            break;
          }
        }
      }

      if (!found) {
        active.removeAt(randIdx);
      }
    }

    return points;
  }
}
