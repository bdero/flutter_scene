// A shared, self-contained lighting HUD for the examples: the environment
// menu plus skybox toggle, sky blur, exposure, IBL intensity, and
// environment rotation, applied directly to the scene it is given. Used by
// the stress tests and the widget-texture example.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';

/// The lighting controls panel. Owns its state and applies every change to
/// [scene]; environments resolve through [selector] (shared with any other
/// menu in the example so the active selection stays consistent).
class LightingPanel extends StatefulWidget {
  const LightingPanel({
    super.key,
    required this.scene,
    required this.selector,
    this.showSkybox = true,
  });

  final Scene scene;
  final EnvironmentSelector selector;

  /// Whether the skybox starts enabled.
  final bool showSkybox;

  @override
  State<LightingPanel> createState() => _LightingPanelState();
}

class _LightingPanelState extends State<LightingPanel> {
  late bool _showSkybox = widget.showSkybox;
  final EnvironmentSkySource _skySource = EnvironmentSkySource();
  double _exposure = 1.0;
  double _environmentIntensity = 1.0;
  double _envRotationX = 0.0;
  double _envRotationY = 0.0;
  double _envRotationZ = 0.0;

  @override
  void initState() {
    super.initState();
    _applySkybox();
    widget.selector.addListener(_onSelectorChanged);
  }

  @override
  void dispose() {
    widget.selector.removeListener(_onSelectorChanged);
    super.dispose();
  }

  void _onSelectorChanged() {
    if (mounted) setState(() {});
  }

  // Sets or clears the scene's skybox from the toggle. The source samples
  // the scene's environment, so selecting a different environment or
  // rotating it updates the backdrop automatically.
  void _applySkybox() {
    widget.scene.skybox = _showSkybox ? Skybox(_skySource) : null;
  }

  // Rebuilds the scene's environment rotation from the three Euler angles.
  void _applyEnvironmentRotation() {
    const degToRad = pi / 180.0;
    widget.scene.environmentTransform =
        vm.Matrix3.rotationY(_envRotationY * degToRad) *
        vm.Matrix3.rotationX(_envRotationX * degToRad) *
        vm.Matrix3.rotationZ(_envRotationZ * degToRad);
  }

  Future<void> _selectEnvironment(ExampleEnvironment environment) async {
    try {
      await widget.selector.select(environment, widget.scene);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to load ${environment.title}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      constraints: const BoxConstraints(maxHeight: 440),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EnvironmentMenu(
              active: widget.selector.active,
              loading: widget.selector.loading,
              onSelected: _selectEnvironment,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Skybox',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Switch(
                  value: _showSkybox,
                  onChanged: (value) => setState(() {
                    _showSkybox = value;
                    _applySkybox();
                  }),
                ),
              ],
            ),
            LabeledSlider(
              label: 'Sky blur',
              value: _skySource.blurriness,
              min: 0.0,
              max: 1.0,
              onChanged: _showSkybox
                  ? (value) => setState(() => _skySource.blurriness = value)
                  : null,
            ),
            LabeledSlider(
              label: 'Exposure',
              value: _exposure,
              min: 0.1,
              max: 8.0,
              onChanged: (value) => setState(() {
                _exposure = value;
                widget.scene.exposure = value;
              }),
            ),
            LabeledSlider(
              label: 'IBL intensity',
              value: _environmentIntensity,
              min: 0.0,
              max: 4.0,
              onChanged: (value) => setState(() {
                _environmentIntensity = value;
                widget.scene.environmentIntensity = value;
              }),
            ),
            LabeledSlider(
              label: 'Env rotation X',
              value: _envRotationX,
              min: -180.0,
              max: 180.0,
              onChanged: (value) => setState(() {
                _envRotationX = value;
                _applyEnvironmentRotation();
              }),
            ),
            LabeledSlider(
              label: 'Env rotation Y',
              value: _envRotationY,
              min: -180.0,
              max: 180.0,
              onChanged: (value) => setState(() {
                _envRotationY = value;
                _applyEnvironmentRotation();
              }),
            ),
            LabeledSlider(
              label: 'Env rotation Z',
              value: _envRotationZ,
              min: -180.0,
              max: 180.0,
              onChanged: (value) => setState(() {
                _envRotationZ = value;
                _applyEnvironmentRotation();
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact labeled slider for HUD panels: label and current value above a
/// thin slider. Null [onChanged] disables (greys out) the slider.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
