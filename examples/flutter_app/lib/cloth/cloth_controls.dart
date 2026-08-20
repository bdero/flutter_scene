// The control panel shared by the cloth demos.

import 'package:flutter/material.dart';

import '../example_action_hint.dart';
import '../example_panel.dart';
import 'cloth_settings.dart';
import 'cloth_wind.dart';

/// The full solver surface over a [ClothSettings].
///
/// The panel only writes to [settings]; the demos apply them to their solvers
/// every frame. Tessellation is the exception, since it cannot be applied in
/// place, so it goes to [onQualityChanged], which rebuilds the scene.
class ClothControlPanel extends StatelessWidget {
  const ClothControlPanel({
    super.key,
    required this.settings,
    required this.stats,
    required this.onChanged,
    required this.onReset,
    this.onQualityChanged,
    this.showSelfCollision = true,
    this.width,
  });

  final ClothSettings settings;

  /// A line of counters under the controls (particles, solve time).
  final String stats;

  final VoidCallback onChanged;
  final VoidCallback onReset;

  /// Supplied only by scenes that can rebuild their sheets at a new
  /// tessellation; the quality row is hidden without it.
  final VoidCallback? onQualityChanged;

  /// Whether the scene can afford self-collision.
  final bool showSelfCollision;

  /// Needed in overlay slots that do not constrain width (the top-right one).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final onQualityChanged = this.onQualityChanged;
    return ExamplePanelCard(
      icon: Icons.air,
      title: 'Cloth',
      width: width,
      maxBodyHeight: 420,
      bodyPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Section('Wind'),
          ClothWindControls(wind: settings.wind, onChanged: onChanged),
          _slider('Air density', settings.airDensity, 0.0, 4.0, (v) {
            settings.airDensity = v;
          }),
          _slider('Drag', settings.dragCoefficient, 0.0, 4.0, (v) {
            settings.dragCoefficient = v;
          }),
          _slider('Lift', settings.liftCoefficient, 0.0, 2.0, (v) {
            settings.liftCoefficient = v;
          }),

          const _Section('Fabric'),
          // Compliance is in meters per newton and lives near zero, so the
          // slider is in millionths.
          _slider(
            'Give',
            settings.stretchCompliance * 1e6,
            0.0,
            5.0,
            (v) => settings.stretchCompliance = v * 1e-6,
            suffix: ' um/N',
          ),
          _slider('Bending', settings.bending, 0.0, 1.0, (v) {
            settings.bending = v;
          }),
          _slider('Viscosity', settings.stretchDamping, 0.0, 1.0, (v) {
            settings.stretchDamping = v;
          }),
          _slider('Air drag', settings.damping, 0.0, 1.0, (v) {
            settings.damping = v;
          }),
          _slider('Friction', settings.friction, 0.0, 1.0, (v) {
            settings.friction = v;
          }),
          _slider(
            'Gravity',
            settings.gravity,
            0.0,
            25.0,
            (v) => settings.gravity = v,
            fractionDigits: 1,
          ),

          const _Section('Solver'),
          _slider(
            'Substeps',
            settings.substeps.toDouble(),
            2.0,
            24.0,
            (v) => settings.substeps = v.round(),
            fractionDigits: 0,
          ),
          _slider(
            'Contact gap',
            settings.contactOffset * 100.0,
            0.0,
            50.0,
            (v) => settings.contactOffset = v / 100.0,
            fractionDigits: 1,
            suffix: ' cm',
          ),
          if (showSelfCollision)
            _Labelled(
              label: 'Self-collision',
              child: Switch(
                value: settings.selfCollision,
                onChanged: (value) {
                  settings.selfCollision = value;
                  onChanged();
                },
              ),
            ),
          if (onQualityChanged != null)
            _Labelled(
              label: 'Quality',
              // A dropdown has to be given a width. In a Row it would be laid
              // out with an unbounded one, which fails layout outright.
              child: SizedBox(
                width: 116,
                child: ExampleDropdown<ClothQuality>(
                  value: settings.quality,
                  isDense: true,
                  items: [
                    for (final quality in ClothQuality.values)
                      DropdownMenuItem(
                        value: quality,
                        child: Text(quality.label),
                      ),
                  ],
                  onChanged: (quality) {
                    if (quality == null || quality == settings.quality) return;
                    settings.quality = quality;
                    onQualityChanged();
                  },
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            stats,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> write, {
    int fractionDigits = 2,
    String suffix = '',
  }) => ClothSliderRow(
    label: label,
    value: value,
    min: min,
    max: max,
    fractionDigits: fractionDigits,
    suffix: suffix,
    onChanged: (v) {
      write(v);
      onChanged();
    },
  );
}

class _Section extends StatelessWidget {
  const _Section(this.label);

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

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // The label takes what the control leaves, so a narrow panel elides it
      // instead of overflowing.
      Expanded(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      child,
    ],
  );
}
