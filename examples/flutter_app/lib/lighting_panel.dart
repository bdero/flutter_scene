// A shared, self-contained lighting HUD for the examples: the environment
// menu plus skybox toggle, sky blur, exposure, IBL intensity, and
// environment rotation, applied directly to the scene it is given. Used by
// the stress tests and the widget-texture example.

import 'dart:async';
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
    this.manageSkybox = true,
    this.onEnvironmentResolved,
    this.initialEnvironmentId,
    this.initialSkyBlur = 0.0,
    this.initialExposure = 1.0,
    this.initialIblIntensity = 1.0,
    this.initialRotationDegrees,
  });

  final Scene scene;
  final EnvironmentSelector selector;

  /// Whether the skybox starts enabled.
  final bool showSkybox;

  /// Whether the panel owns the scene's skybox (the toggle plus sky blur).
  /// Pass false when the example manages its own skybox; the panel then
  /// never touches `scene.skybox` and hides those controls.
  final bool manageSkybox;

  /// Called with the resolved [EnvironmentMap] after each successful
  /// selection (null means the renderer's built-in studio default), including
  /// the [initialEnvironmentId] load.
  final void Function(EnvironmentMap? map)? onEnvironmentResolved;

  /// The [ExampleEnvironment.id] to select at startup, or null to keep the
  /// selector's current environment. Loads (from the cache when possible)
  /// in the background.
  final String? initialEnvironmentId;

  /// Starting values for the sliders, applied to the scene at startup so an
  /// example can ship its own lighting defaults.
  final double initialSkyBlur;
  final double initialExposure;
  final double initialIblIntensity;

  /// Starting environment rotation Euler angles in degrees (x, y, z), or
  /// null for none.
  final vm.Vector3? initialRotationDegrees;

  @override
  State<LightingPanel> createState() => _LightingPanelState();
}

class _LightingPanelState extends State<LightingPanel> {
  late bool _showSkybox = widget.showSkybox;
  final EnvironmentSkySource _skySource = EnvironmentSkySource();
  late double _exposure = widget.initialExposure;
  late double _environmentIntensity = widget.initialIblIntensity;
  late double _envRotationX = widget.initialRotationDegrees?.x ?? 0.0;
  late double _envRotationY = widget.initialRotationDegrees?.y ?? 0.0;
  late double _envRotationZ = widget.initialRotationDegrees?.z ?? 0.0;

  @override
  void initState() {
    super.initState();
    _skySource.blurriness = widget.initialSkyBlur;
    widget.scene.exposure = _exposure;
    widget.scene.environmentIntensity = _environmentIntensity;
    _applyEnvironmentRotation();
    if (widget.manageSkybox) _applySkybox();
    widget.selector.addListener(_onSelectorChanged);
    final environmentId = widget.initialEnvironmentId;
    if (environmentId != null && widget.selector.active.id != environmentId) {
      for (final environment in exampleEnvironments) {
        if (environment.id == environmentId) {
          unawaited(_selectEnvironment(environment));
          break;
        }
      }
    }
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
      final map = await widget.selector.select(environment, widget.scene);
      widget.onEnvironmentResolved?.call(map);
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
            if (widget.manageSkybox) ...[
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
            ],
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
