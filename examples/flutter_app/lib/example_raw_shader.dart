// Raw shader pair: a ShaderMaterial that owns both stages.
//
// The Toon example customizes only the fragment stage and lets the engine
// drive vertices; the Custom vertices example customizes both through a
// managed `.fmat`. This one hands ShaderMaterial a hand-written vertex shader
// as well as a fragment shader, so the material owns the whole pipeline and
// the engine's standard vertex shader never runs:
//   1. Author both shaders (shaders/example_ripple.vert / .frag) against the
//      engine contract documented in MATERIALS.md.
//   2. Compile them through the `flutter_gpu_shaders` build hook.
//   3. Hand both to ShaderMaterial and set each stage's uniforms by name.
//
// The vertex stage displaces the mesh along its normal with a travelling
// ripple, which is not something the fragment stage could fake.

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

class ExampleRawShader extends StatefulWidget {
  const ExampleRawShader({super.key});

  @override
  State<ExampleRawShader> createState() => _ExampleRawShaderState();
}

class _ExampleRawShaderState extends State<ExampleRawShader> {
  final Scene scene = Scene();
  bool loaded = false;

  double amplitude = 0.5;
  double wavelength = 1.4;
  double speed = 2.4;

  ShaderMaterial? _material;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final library = await gpu.loadShaderLibraryAsync(
      await gpu.resolveShaderBundleKey('example'),
    );
    final vertexShader = library?['RippleVertex'];
    final fragmentShader = library?['RippleFragment'];
    if (vertexShader == null || fragmentShader == null) {
      throw StateError(
        'Ripple shaders missing from example.shaderbundle. The build hook '
        'should have produced them; rerun `flutter run` with a clean build.',
      );
    }
    if (!mounted) return;

    final material = ShaderMaterial(
      vertexShader: vertexShader,
      fragmentShader: fragmentShader,
    );
    // Fragment-stage parameters. The stage defaults to fragment, matching the
    // fragment-only workflow.
    material.setUniformBlockFromFloats('TintInfo', [
      0.45, 0.85, 1.0, 1.0, // crest
      0.04, 0.16, 0.42, 1.0, // trough
    ]);
    _material = material;
    _setRippleUniforms(0);

    scene.add(Node(mesh: Mesh(_grid(), material)));
    setState(() => loaded = true);
  }

  // The ripple moves vertices, so the surface needs enough of them to bend
  // smoothly.
  MeshGeometry _grid() {
    const n = 140;
    const size = 24.0;
    final count = (n + 1) * (n + 1);
    final positions = Float32List(count * 3);
    final normals = Float32List(count * 3);
    var v = 0;
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c <= n; c++) {
        positions[v * 3] = (c / n - 0.5) * size;
        positions[v * 3 + 2] = (r / n - 0.5) * size;
        normals[v * 3 + 1] = 1.0;
        v++;
      }
    }
    final indices = <int>[];
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final i0 = r * (n + 1) + c;
        final i2 = i0 + (n + 1);
        indices.addAll([i0, i2, i0 + 1, i0 + 1, i2, i2 + 1]);
      }
    }
    return MeshGeometry.fromArrays(
      positions: positions,
      normals: normals,
      indices: indices,
    );
  }

  // Must match the `RippleInfo` block in example_ripple.vert, packed std140.
  // Four floats fill one 16-byte row, so there is no padding to add.
  void _setRippleUniforms(double time) {
    _material?.setUniformBlock(
      'RippleInfo',
      ByteData.sublistView(
        Float32List.fromList([time, amplitude, wavelength, speed]),
      ),
      stage: ShaderStage.vertex,
    );
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
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
            camera: PerspectiveCamera(
              position: vm.Vector3(0, 6.0, 11.0),
              target: vm.Vector3(0, 0, 0),
            ),
            onTick: (elapsed, deltaSeconds) {
              _setRippleUniforms(elapsed.inMicroseconds / 1e6);
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          child: ExamplePanelCard(
            icon: Icons.waves,
            title: 'Ripple',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SliderRow(
                  label: 'Amplitude',
                  value: amplitude,
                  min: 0,
                  max: 1.5,
                  onChanged: (val) => setState(() => amplitude = val),
                ),
                _SliderRow(
                  label: 'Wavelength',
                  value: wavelength,
                  min: 0.3,
                  max: 4.0,
                  onChanged: (val) => setState(() => wavelength = val),
                ),
                _SliderRow(
                  label: 'Speed',
                  value: speed,
                  min: 0,
                  max: 6,
                  onChanged: (val) => setState(() => speed = val),
                ),
              ],
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
          width: 96,
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
