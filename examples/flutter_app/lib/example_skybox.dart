// Custom skybox example: draws a procedural sky from a caller-authored
// fragment shader.
//
// Demonstrates the ShaderSkySource workflow:
//   1. Author a sky fragment (shaders/example_gradient_sky.frag) that reads
//      the engine-supplied world view direction `v_ray` and outputs color.
//   2. Compile it into build/shaderbundles/example.shaderbundle (build hook).
//   3. Load the bundle, pull the fragment, wrap it in a ShaderSkySource, set
//      its uniform block, and assign it to scene.skybox.
// The engine owns the full-screen draw, depth, and draw order; no geometry is
// placed for the sky.

import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/gpu.dart' as gpu;
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

  ShaderSkySource? _sky;

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
    final shaderLibrary = await gpu.loadShaderLibraryAsync(
      'build/shaderbundles/example.shaderbundle',
    );
    final skyShader = shaderLibrary?['GradientSkyFragment'];
    if (skyShader == null) {
      throw StateError(
        'GradientSkyFragment missing from example.shaderbundle. The build '
        'hook should have produced it; rerun `flutter run` with a clean build.',
      );
    }
    if (!mounted) return;

    final sky = ShaderSkySource(fragmentShader: skyShader);
    _sky = sky;
    _refreshSky();
    scene.skybox = Skybox(sky);

    // A spinning reference cuboid so the scene reads as 3D.
    final mesh = Mesh(
      CuboidGeometry(vm.Vector3(1.5, 1.5, 1.5), debugColors: true),
      UnlitMaterial(),
    );
    scene.add(Node(mesh: mesh)..addComponent(_Spin(0.5)));

    setState(() => loaded = true);
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
    // GradientSkyInfo, std140: four vec4 (zenith, horizon, ground, sun).
    sky.setUniformBlockFromFloats('GradientSkyInfo', <double>[
      0.05, 0.18, 0.55, 1.0, // zenith
      0.45, 0.62, 0.90, 1.0, // horizon
      0.16, 0.14, 0.12, 1.0, // ground
      dir.x, dir.y, dir.z, _sunSharpness, // sun
    ]);
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

class _Spin extends Component {
  _Spin(this.radiansPerSecond);
  final double radiansPerSecond;

  @override
  void update(double deltaSeconds) {
    node.localTransform =
        node.localTransform *
        vm.Matrix4.rotationY(radiansPerSecond * deltaSeconds);
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
