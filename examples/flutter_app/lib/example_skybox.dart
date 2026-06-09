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

class _ExampleSkyboxState extends State<ExampleSkybox> {
  final Scene scene = Scene();
  bool loaded = false;

  PreprocessedSky? _sky;

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
    _sky = sky;
    _refreshSky();
    scene.skybox = Skybox(sky);
    // Bake the sky into the scene's image-based lighting so it also lights and
    // reflects on objects. The visible sky draws every frame; this bake runs
    // only when invoked (here on load, and from the "Re-bake lighting" button).
    await _rebakeLighting();
    if (!mounted) return;

    // A smooth metallic sphere mirrors the baked environment.
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 1.3),
          PhysicallyBasedMaterial()
            ..metallicFactor = 1.0
            ..roughnessFactor = 0.08,
        ),
      ),
    );

    setState(() => loaded = true);
  }

  Future<void> _rebakeLighting() async {
    final sky = _sky;
    if (sky == null) return;
    scene.environment = await EnvironmentMap.fromSky(sky);
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  void _refreshSky() {
    final sky = _sky;
    if (sky == null) return;
    final dir = vm.Vector3(
      cos(_sunElevation) * sin(_sunAzimuth),
      sin(_sunElevation),
      cos(_sunElevation) * cos(_sunAzimuth),
    );
    // Typed, name-addressed parameters from the .fmat sidecar; the colors keep
    // their .fmat defaults.
    sky.parameters.setVec3('sun_direction', dir);
    sky.parameters.setFloat('sun_sharpness', _sunSharpness);
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _rebakeLighting();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Re-bake lighting'),
                    ),
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
