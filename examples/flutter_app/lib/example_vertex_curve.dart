// Vertex-stage showcase: a curved, animated ocean authored entirely in a
// `.fmat` vertex stage (assets/vertex_curve.fmat). One material exercises the
// whole vertex surface at once:
//   - vertex displacement (animated waves + the Animal Crossing world curve),
//   - a custom per-vertex attribute (wave_seed) for organic waves,
//   - a `time` parameter updated every frame to animate the surface,
//   - writing world_normal so lighting shades the wave shape, and
//   - two custom varyings (foam on crests, horizon fade) read in the fragment.
// The sliders drive the curvature and wave amplitude live.

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

class ExampleVertexCurve extends StatefulWidget {
  const ExampleVertexCurve({super.key});

  @override
  State<ExampleVertexCurve> createState() => _ExampleVertexCurveState();
}

class _ExampleVertexCurveState extends State<ExampleVertexCurve> {
  final Scene scene = Scene();
  bool loaded = false;

  double curvature = 0.006;
  double amplitude = 0.35;
  PreprocessedMaterial? _material;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final material = await loadFmatMaterial('assets/vertex_curve.fmat');
    if (!mounted) return;
    _material = material;
    material.parameters
      ..setFloat('curvature', curvature)
      ..setFloat('amplitude', amplitude);

    scene.add(Node(mesh: Mesh(_oceanGrid(), material)));
    setState(() => loaded = true);
  }

  /// A large, finely tessellated grid in the XZ plane, with a per-vertex
  /// `wave_seed` custom attribute (a hashed pseudo-random phase) so the waves
  /// vary organically instead of marching in a perfect grid.
  MeshGeometry _oceanGrid() {
    const n = 120; // cells per side; (n + 1)^2 vertices
    const size = 90.0;
    final count = (n + 1) * (n + 1);
    final positions = Float32List(count * 3);
    final seeds = Float32List(count);
    var v = 0;
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c <= n; c++) {
        positions[v * 3] = (c / n - 0.5) * size;
        positions[v * 3 + 2] = (r / n - 0.5) * size;
        final hash = (r * 73856093) ^ (c * 19349663);
        seeds[v] = (hash & 0xffff) / 0xffff * 6.2831853;
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
    return MeshGeometry.fromArrays(positions: positions, indices: indices)
      ..setCustomAttribute('wave_seed', seeds, components: 1);
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
            // Fixed camera looking out over the ocean toward the curved
            // horizon; the world curve is relative to this camera.
            camera: PerspectiveCamera(
              position: vm.Vector3(0, 6.0, 14.0),
              target: vm.Vector3(0, 0.5, -28.0),
            ),
            onTick: (elapsed, deltaSeconds) {
              // Animate the waves by advancing the material's time parameter.
              _material?.parameters.setFloat(
                'time',
                elapsed.inMicroseconds / 1e6,
              );
              exampleSettings.applyTo(scene);
            },
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
                    label: 'Curvature',
                    value: curvature,
                    min: 0.0,
                    max: 0.02,
                    onChanged: (val) => setState(() {
                      curvature = val;
                      _material?.parameters.setFloat('curvature', val);
                    }),
                  ),
                  _SliderRow(
                    label: 'Wave height',
                    value: amplitude,
                    min: 0.0,
                    max: 0.8,
                    onChanged: (val) => setState(() {
                      amplitude = val;
                      _material?.parameters.setFloat('amplitude', val);
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
          width: 110,
          child: Text(
            '$label: ${value.toStringAsFixed(4)}',
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
