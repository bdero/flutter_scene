import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' show ColorLut;

/// Procedurally generated `.cube` film looks for the color-grading panel,
/// built once on first use (the GPU context must be live).
final Map<String, ColorLut?> exampleLuts = {'None': null};

void ensureExampleLuts() {
  if (exampleLuts.length > 1) return;
  exampleLuts['Teal & orange'] = ColorLut.fromCubeString(
    _generateCube(17, (r, g, b) {
      final luma = 0.299 * r + 0.587 * g + 0.114 * b;
      final shadow = 1.0 - _smooth(luma);
      return (
        r * (1.0 + 0.14 * (1.0 - shadow)) * (1.0 - 0.10 * shadow),
        g * (1.0 + 0.02 * shadow),
        b * (1.0 + 0.16 * shadow) * (1.0 - 0.12 * (1.0 - shadow)),
      );
    }),
  );
  exampleLuts['Silver film'] = ColorLut.fromCubeString(
    _generateCube(17, (r, g, b) {
      final luma = 0.299 * r + 0.587 * g + 0.114 * b;
      double mix(double c) => c + (luma - c) * 0.82;
      double lift(double c) => 0.035 + c * 0.94;
      return (lift(mix(r)), lift(mix(g)), lift(mix(b) * 1.03));
    }),
  );
}

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

String _generateCube(
  int size,
  (double, double, double) Function(double r, double g, double b) grade,
) {
  final buffer = StringBuffer('LUT_3D_SIZE $size\n');
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final graded = grade(r / (size - 1), g / (size - 1), b / (size - 1));
        String f(double v) =>
            math.min(1.0, math.max(0.0, v)).toStringAsFixed(5);
        buffer.writeln('${f(graded.$1)} ${f(graded.$2)} ${f(graded.$3)}');
      }
    }
  }
  return buffer.toString();
}
