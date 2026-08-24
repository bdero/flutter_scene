import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

/// Demonstrates the world-space irradiance field: an interior whose colored
/// walls bleed onto everything near them, an alcove lit by nothing but an
/// emissive panel, and a key light that can be swung across the room or
/// switched off entirely so the field is visibly the only thing lighting it.
///
/// The field caches bounce light in world space, so it keeps lighting a
/// surface after whatever lit it leaves the frame, and it converges over a
/// few frames rather than snapping. Turning it off is the A/B that makes the
/// difference obvious.
class ExampleGlobalIllumination extends StatefulWidget {
  const ExampleGlobalIllumination({super.key});

  @override
  State<ExampleGlobalIllumination> createState() =>
      _ExampleGlobalIlluminationState();
}

class _ExampleGlobalIlluminationState extends State<ExampleGlobalIllumination> {
  final Scene scene = Scene();

  // The key light's compass angle, and whether it is on at all. Night leaves
  // the emissive panel as the only source in the room, which nothing but the
  // probe field can carry onto the walls and floor.
  double _sunAngle = 0.6;
  bool _night = false;
  double _elapsed = 0;

  static const _keyIntensity = 3.2;

  @override
  void initState() {
    super.initState();

    // A dim sky so the room is not pitch black before the field converges,
    // and so switching the key light off still leaves the walls readable.
    scene.environmentIntensity = 0.06;
    scene.exposure = 1.4;
    scene.antiAliasingMode = AntiAliasingMode.taa;

    scene.ambientOcclusion
      ..enabled = true
      ..method = AmbientOcclusionMethod.groundTruth
      ..radius = 0.8
      ..intensity = 1.0
      ..halfResolution = false;

    // The field carries the far-field bounce; the occlusion above carries the
    // near-field contact darkening. Composing the two is the whole reason the
    // field can be this coarse.
    exampleSettings.globalIllumination
      ..enabled = true
      ..volumeMode = IrradianceVolumeMode.fitScene
      ..resolution.setValues(14, 8, 14)
      ..intensity = 1.0
      ..hysteresis = 0.92
      ..visibility = 0.6
      ..emissiveGiBoost = 2.0
      ..injectionResolution = IrradianceInjectionResolution.quarter;
    exampleSettings.applyTo(scene);

    _applySun();
    _buildRoom();
  }

  void _applySun() {
    scene.directionalLight = _night
        ? null
        : DirectionalLight(
            direction: vm.Vector3(sin(_sunAngle) * 0.6, -0.9, cos(_sunAngle)),
            intensity: _keyIntensity,
            castsShadow: true,
            shadowMaxDistance: 26.0,
          );
  }

  PhysicallyBasedMaterial _matte(
    double r,
    double g,
    double b, {
    vm.Vector4? emissive,
  }) => PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(r, g, b, 1.0)
    ..emissiveFactor = emissive ?? vm.Vector4.zero()
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.92
    ..vertexColorWeight = 0.0;

  void _box(vm.Vector3 size, vm.Vector3 at, PhysicallyBasedMaterial material) {
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(size), material))
        ..localTransform = vm.Matrix4.translation(at),
    );
  }

  void _buildRoom() {
    final white = _matte(0.86, 0.86, 0.84);
    final warm = _matte(0.78, 0.16, 0.10);
    final cool = _matte(0.10, 0.32, 0.72);

    // A room open toward the camera, with the two long walls carrying the
    // colors that have to bleed. Walls are solids a probe spacing thick; a
    // zero-thickness plane leaks light through no matter how the visibility
    // term is tuned.
    _box(vm.Vector3(9.0, 0.4, 9.0), vm.Vector3(0, -0.2, 0), white);
    _box(vm.Vector3(9.0, 0.4, 9.0), vm.Vector3(0, 4.2, 0), white);
    _box(vm.Vector3(9.0, 4.4, 0.4), vm.Vector3(0, 2.0, -4.3), white);
    _box(vm.Vector3(0.4, 4.4, 9.0), vm.Vector3(-4.3, 2.0, 0), warm);
    _box(vm.Vector3(0.4, 4.4, 9.0), vm.Vector3(4.3, 2.0, 0), cool);

    // A partition splitting the room, so one half can be in shadow while the
    // other is sunlit and the field carries light around it.
    _box(vm.Vector3(0.5, 3.0, 3.4), vm.Vector3(-0.6, 1.5, -1.4), white);

    // The alcove: a recess behind the partition with an emissive panel and no
    // analytic light reaching it. Everything visible in there arrived through
    // the probe field.
    _box(
      vm.Vector3(2.4, 1.1, 0.3),
      vm.Vector3(-2.4, 2.4, -4.0),
      _matte(0.02, 0.02, 0.02, emissive: vm.Vector4(5.0, 1.6, 0.35, 1.0)),
    );
    _box(
      vm.Vector3(0.3, 2.2, 2.2),
      vm.Vector3(2.6, 1.1, -2.6),
      _matte(0.02, 0.02, 0.02, emissive: vm.Vector4(0.3, 2.2, 4.6, 1.0)),
    );

    // Neutral props, so the bleed reads against something that has no color
    // of its own.
    scene.add(
      Node(mesh: Mesh(SphereGeometry(radius: 0.85), white))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(1.7, 0.85, 0.4)),
    );
    _box(vm.Vector3(1.3, 1.3, 1.3), vm.Vector3(-2.4, 0.65, 1.6), white);
    _box(vm.Vector3(0.9, 2.2, 0.9), vm.Vector3(2.9, 1.1, 2.2), white);
  }

  PerspectiveCamera _orbitCamera() => PerspectiveCamera(
    position: vm.Vector3(
      sin(_elapsed * 0.14) * 3.4,
      2.3 + sin(_elapsed * 0.09) * 0.5,
      7.4,
    ),
    target: vm.Vector3(0, 1.6, -1.0),
  );

  @override
  Widget build(BuildContext context) {
    final settings = exampleSettings.globalIllumination;
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) => _orbitCamera(),
            onTick: (elapsed, deltaSeconds) {
              _elapsed = elapsed.inMicroseconds / 1e6;
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        ExampleOverlay.bottomRightPanel(
          paired: true,
          child: ExamplePanelCard(
            icon: Icons.lightbulb_outline,
            title: 'Global illumination',
            width: 350,
            maxBodyHeight: 560,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SwitchRow(
                  label: 'Irradiance field',
                  value: settings.enabled,
                  onChanged: (v) => setState(() {
                    settings.enabled = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Intensity',
                  value: settings.intensity,
                  min: 0,
                  max: 3,
                  onChanged: (v) => setState(() {
                    settings.intensity = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Hysteresis',
                  value: settings.hysteresis,
                  min: 0.5,
                  max: 0.99,
                  onChanged: (v) => setState(() {
                    settings.hysteresis = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Shadow bias',
                  value: settings.shadowBias,
                  min: 0,
                  max: 1.5,
                  onChanged: (v) => setState(() {
                    settings.shadowBias = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Visibility',
                  value: settings.visibility,
                  min: 0,
                  max: 1,
                  onChanged: (v) => setState(() {
                    settings.visibility = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Vis bias',
                  value: settings.visibilityBias,
                  min: 0,
                  max: 0.4,
                  onChanged: (v) => setState(() {
                    settings.visibilityBias = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Emissive GI',
                  value: settings.emissiveGiBoost,
                  min: 1,
                  max: 8,
                  onChanged: (v) => setState(() {
                    settings.emissiveGiBoost = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Firefly',
                  value: settings.fireflyClamp,
                  min: 0,
                  max: 32,
                  onChanged: (v) => setState(() {
                    settings.fireflyClamp = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                _SliderRow(
                  label: 'Probes/axis',
                  value: settings.resolution.x,
                  min: 4,
                  max: 24,
                  onChanged: (v) => setState(() {
                    final n = v.roundToDouble();
                    settings.resolution.setValues(
                      n,
                      (n * 0.6).roundToDouble(),
                      n,
                    );
                    exampleSettings.applyTo(scene);
                  }),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Injection',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    DropdownButton<IrradianceInjectionResolution>(
                      value: settings.injectionResolution,
                      dropdownColor: Colors.black87,
                      style: const TextStyle(color: Colors.white),
                      items: [
                        for (final r in IrradianceInjectionResolution.values)
                          DropdownMenuItem(value: r, child: Text(r.name)),
                      ],
                      onChanged: (v) => setState(() {
                        if (v != null) {
                          settings.injectionResolution = v;
                          exampleSettings.applyTo(scene);
                        }
                      }),
                    ),
                  ],
                ),
                _SwitchRow(
                  label: 'Update when idle only',
                  value: settings.updateWhenIdleOnly,
                  onChanged: (v) => setState(() {
                    settings.updateWhenIdleOnly = v;
                    exampleSettings.applyTo(scene);
                  }),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Refill from scratch',
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () =>
                        setState(scene.invalidateGlobalIllumination),
                  ),
                ),
              ],
            ),
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          paired: true,
          child: ExamplePanelCard(
            icon: Icons.wb_sunny_outlined,
            title: 'Key light',
            width: 320,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SwitchRow(
                  label: 'Night (emissive only)',
                  value: _night,
                  onChanged: (v) => setState(() {
                    _night = v;
                    _applySun();
                  }),
                ),
                _SliderRow(
                  label: 'Sun angle',
                  value: _sunAngle,
                  min: -1.3,
                  max: 1.3,
                  onChanged: (v) => setState(() {
                    _sunAngle = v;
                    _applySun();
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Swing the sun and watch the colored bounce follow it a '
                    'few frames later. At night the room is lit only by the '
                    'two emissive panels, through the probe field.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
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
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
