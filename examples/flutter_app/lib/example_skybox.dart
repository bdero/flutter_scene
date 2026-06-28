// Custom skybox example: draws a procedural sky authored as a `.fmat` sky.
//
// Demonstrates the recommended custom-sky workflow:
//   1. Author assets/gradient_sky.fmat with a `sky { vec3 Sky(vec3 direction) }`
//      block and typed parameters.
//   2. The build hook (buildMaterials) compiles it into the materials bundle.
//   3. loadFmatSky returns a PreprocessedSky (a SkySource) with typed,
//      hot-reloadable parameters; assign it to scene.skybox.
// The engine owns the full-screen draw, depth, and draw order; no geometry is
// placed for the sky. (For a raw fragment shader instead, see ShaderSkySource.)

import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

class ExampleSkybox extends StatefulWidget {
  const ExampleSkybox({super.key});

  @override
  State<ExampleSkybox> createState() => _ExampleSkyboxState();
}

enum _SkyType {
  fmatGradient('Gradient (.fmat)'),
  gradient('Gradient (built-in)'),
  physical('Physical atmosphere');

  const _SkyType(this.label);
  final String label;
}

class _ExampleSkyboxState extends State<ExampleSkybox> {
  final Scene scene = Scene();
  bool loaded = false;

  PreprocessedSky? _fmatSky;
  GradientSkySource? _gradientSky;
  PhysicalSkySource? _physicalSky;
  _SkyType _skyType = _SkyType.fmatGradient;
  SkyEnvironment? _skyEnvironment;

  // Sun controls, surfaced as sliders.
  double _sunElevation = 0.5; // radians above the horizon
  double _sunAzimuth = 0.6; // radians around +Y
  double _sunSharpness = 400.0; // higher = tighter sun disk

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sky = await loadFmatSky('assets/gradient_sky.fmat');
    if (!mounted) return;
    _fmatSky = sky;
    _applySkyType(_skyType);

    // Left: a smooth metallic sphere mirrors the baked environment (specular).
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 1.0),
          PhysicallyBasedMaterial()
            ..metallicFactor = 1.0
            ..roughnessFactor = 0.08,
        ),
      )..localTransform = vm.Matrix4.translationValues(-1.5, 0, 0),
    );
    // Right: a matte sphere lit by the sky's diffuse irradiance (the SH term).
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 1.0),
          PhysicallyBasedMaterial()
            ..metallicFactor = 0.0
            ..roughnessFactor = 1.0
            ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.85, 1.0),
        ),
      )..localTransform = vm.Matrix4.translationValues(1.5, 0, 0),
    );

    setState(() => loaded = true);
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  // The source for [type], created on first use. The built-in sources are
  // plain ShaderSkySource subclasses, so all three drive the skybox and the
  // lighting identically.
  ShaderSkySource _sourceFor(_SkyType type) {
    return switch (type) {
      _SkyType.fmatGradient => _fmatSky!,
      _SkyType.gradient => _gradientSky ??= GradientSkySource(),
      _SkyType.physical => _physicalSky ??= PhysicalSkySource(),
    };
  }

  // Shows [type] as the background and rebinds the lighting to it. A fresh
  // binding bakes synchronously, so switching skies relights immediately; the
  // refresh mode carries over.
  void _applySkyType(_SkyType type) {
    _skyType = type;
    final source = _sourceFor(type);
    _refreshSky();
    scene.skybox = Skybox(source);
    _skyEnvironment = SkyEnvironment(
      source,
      refresh: _skyEnvironment?.refresh ?? SkyEnvironmentRefresh.manual,
      // Bake the procedural sky at a higher resolution than the default so the
      // sun and horizon stay crisp and the poles do not pinch into a sunburst.
      faceResolution: 256,
      equirectWidth: 1024,
    );
    scene.skyEnvironment = _skyEnvironment;
  }

  void _refreshSky() {
    final dir = vm.Vector3(
      cos(_sunElevation) * sin(_sunAzimuth),
      sin(_sunElevation),
      cos(_sunElevation) * cos(_sunAzimuth),
    );
    switch (_skyType) {
      case _SkyType.fmatGradient:
        // Typed, name-addressed parameters from the .fmat sidecar; the colors
        // keep their .fmat defaults.
        final sky = _fmatSky;
        if (sky == null) return;
        sky.parameters.setVec3('sun_direction', dir);
        sky.parameters.setFloat('sun_sharpness', _sunSharpness);
      case _SkyType.gradient:
        _gradientSky!
          ..sunDirection = dir
          ..sunSharpness = _sunSharpness;
      case _SkyType.physical:
        // The physical sun is a disk with a fixed angular size; the sharpness
        // slider does not apply.
        _physicalSky!.sunDirection = dir;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) {
              final t = elapsed.inMicroseconds / 1e6 * 0.25;
              return PerspectiveCamera(
                position: vm.Vector3(sin(t) * 6, 2, cos(t) * 6),
                target: vm.Vector3(0, 0, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Card(
            color: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Sky:', style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 8),
                      DropdownButton<_SkyType>(
                        value: _skyType,
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
                        items: [
                          for (final type in _SkyType.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(type.label),
                            ),
                        ],
                        onChanged: (type) => setState(() {
                          if (type != null) _applySkyType(type);
                        }),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text(
                        'Lighting refresh:',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<SkyEnvironmentRefresh>(
                        value:
                            _skyEnvironment?.refresh ??
                            SkyEnvironmentRefresh.manual,
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(
                            value: SkyEnvironmentRefresh.manual,
                            child: Text('Manual'),
                          ),
                          DropdownMenuItem(
                            value: SkyEnvironmentRefresh.interval,
                            child: Text('Interval (1s)'),
                          ),
                          DropdownMenuItem(
                            value: SkyEnvironmentRefresh.everyFrame,
                            child: Text('Every frame'),
                          ),
                        ],
                        onChanged: (mode) => setState(() {
                          if (mode != null) _skyEnvironment?.refresh = mode;
                        }),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => _skyEnvironment?.invalidate(),
                        child: const Text('Re-bake lighting'),
                      ),
                    ],
                  ),
                  _SliderRow(
                    label: 'Sun elevation',
                    value: _sunElevation,
                    min: -0.3,
                    max: 1.4,
                    onChanged: (v) => setState(() {
                      _sunElevation = v;
                      _refreshSky();
                    }),
                  ),
                  _SliderRow(
                    label: 'Sun azimuth',
                    value: _sunAzimuth,
                    min: -pi,
                    max: pi,
                    onChanged: (v) => setState(() {
                      _sunAzimuth = v;
                      _refreshSky();
                    }),
                  ),
                  _SliderRow(
                    label: 'Sun sharpness',
                    value: _sunSharpness,
                    min: 16,
                    max: 2000,
                    onChanged: (v) => setState(() {
                      _sunSharpness = v;
                      _refreshSky();
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
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
          width: 120,
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
