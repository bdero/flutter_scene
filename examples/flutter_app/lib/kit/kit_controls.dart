import 'package:flutter/material.dart';

/// A labelled slider row styled for the gameplay kit control panel.
class KitSliderRow extends StatelessWidget {
  const KitSliderRow({
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
      '$label: ${value.toStringAsFixed(fractionDigits)}$suffix',
      style: const TextStyle(color: Colors.white, fontSize: 12),
    );
    final slider = Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      onChanged: onChanged,
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 260
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, slider],
            )
          : Row(
              children: [
                SizedBox(width: 120, child: text),
                Expanded(child: slider),
              ],
            ),
    );
  }
}

class KitSectionHeader extends StatelessWidget {
  const KitSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 10,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Settings and parameters for the gameplay kit demo scenarios.
class KitDemoSettings {
  // Character & Camera
  double walkSpeed = 5.0;
  double jumpVelocity = 7.0;
  double armLength = 5.0;
  double lagSpeed = 8.0;
  bool enableLag = true;

  // Day & Night
  double timeOfDay = 14.0;
  double timeSpeed = 0.5;
  double latitude = 34.0;
  bool isTimePlaying = true;

  // Water & Buoyancy
  double waveAmplitude = 0.4;
  double waveSpeed = 1.4;
  double waveSteepness = 0.8;

  // Flocking
  double boidCount = 24;
  double separationDistance = 1.5;
  double maxSteerSpeed = 6.0;

  // Spawner & Pooling
  double minDistance = 3.5;
  int poolMaxSize = 48;
  bool autoFire = true;
  double fireInterval = 0.18;
  int activeProjectiles = 0;
  int poolCapacity = 48;
  int totalSpawns = 0;

  // Debug Visuals
  bool showWireframeBoxes = true;
  bool showSpheres = true;
  bool showAxes = true;
}
