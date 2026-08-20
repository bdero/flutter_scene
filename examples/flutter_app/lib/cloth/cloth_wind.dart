// The wind shared by the cloth demos, plus its controls.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'cloth_solver.dart';

/// A configurable wind: a heading, a speed, and how much the direction
/// wanders around that heading.
///
/// The wander is not decoration. A sheet edge-on to a wind that never changes
/// direction sits in a balanced state and stops moving, so a flag in a
/// perfectly steady breeze goes limp.
class ClothWind {
  /// Wind speed, meters per second.
  double speed = 6.0;

  /// Compass heading the wind blows toward, degrees clockwise from +X.
  double headingDegrees = 0.0;

  /// Gust strength, as a fraction of [speed] varying over the sheet.
  double gust = 0.35;

  /// How far the heading swings either side, radians.
  double swing = 0.28;

  /// How fast the heading swings, radians per second.
  double swingRate = 0.6;

  /// The wind vector at [seconds].
  vm.Vector3 vectorAt(double seconds) {
    final heading =
        headingDegrees * math.pi / 180.0 +
        math.sin(seconds * swingRate) * swing;
    return vm.Vector3(
      math.cos(heading) * speed,
      // A slow vertical breath, so a sheet lifts and settles rather than
      // staying in one plane.
      math.sin(seconds * 0.9) * speed * 0.07,
      math.sin(heading) * speed,
    );
  }

  /// Points [solver] into this wind at [seconds].
  void applyTo(ClothSolver solver, double seconds) {
    solver.wind.setFrom(vectorAt(seconds));
    solver.windGust = gust;
  }
}

/// Speed, direction, and gust sliders for a [ClothWind].
class ClothWindControls extends StatelessWidget {
  const ClothWindControls({
    super.key,
    required this.wind,
    required this.onChanged,
  });

  final ClothWind wind;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClothSliderRow(
          label: 'Speed',
          value: wind.speed,
          min: 0.0,
          max: 18.0,
          suffix: ' m/s',
          onChanged: (value) {
            wind.speed = value;
            onChanged();
          },
        ),
        ClothSliderRow(
          label: 'Direction',
          value: wind.headingDegrees,
          min: 0.0,
          max: 360.0,
          fractionDigits: 0,
          suffix: '°',
          onChanged: (value) {
            wind.headingDegrees = value;
            onChanged();
          },
        ),
        ClothSliderRow(
          label: 'Gust',
          value: wind.gust,
          min: 0.0,
          max: 1.0,
          onChanged: (value) {
            wind.gust = value;
            onChanged();
          },
        ),
      ],
    );
  }
}

/// A labelled slider sized for the cloth control panels.
class ClothSliderRow extends StatelessWidget {
  const ClothSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.fractionDigits = 2,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int fractionDigits;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      '$label ${value.toStringAsFixed(fractionDigits)}$suffix',
      style: const TextStyle(color: Colors.white, fontSize: 12),
    );
    final slider = Slider(
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
    // A slider has a minimum width of its own, so on a narrow panel the label
    // goes above it rather than squeezing it off the edge.
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 260
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, slider],
            )
          : Row(
              children: [
                SizedBox(width: 112, child: text),
                Expanded(child: slider),
              ],
            ),
    );
  }
}
