// Custom-vertex-stage showcase. A dropdown switches between sub-demos, each a
// `.fmat` whose vertex stage drives the look:
//   - Ocean: an animated, curved ocean (waves + world curve, a per-vertex
//     wave_seed attribute, a time param, a perturbed normal, and foam/horizon
//     varyings).
//   - Runner: an endless road that curves down over the horizon while rows of
//     pillars scroll toward the camera.

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_settings.dart';

enum _Demo {
  ocean('Ocean'),
  runner('Runner');

  const _Demo(this.label);
  final String label;
}

class ExampleVertexCurve extends StatefulWidget {
  const ExampleVertexCurve({super.key});

  @override
  State<ExampleVertexCurve> createState() => _ExampleVertexCurveState();
}

class _ExampleVertexCurveState extends State<ExampleVertexCurve> {
  _Demo _demo = _Demo.ocean;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The selected sub-demo owns its own Scene and SceneView; the ValueKey
        // rebuilds it (and disposes the old scene) when the selection changes.
        Positioned.fill(
          child: switch (_demo) {
            _Demo.ocean => const _OceanDemo(key: ValueKey('ocean')),
            _Demo.runner => const _RunnerDemo(key: ValueKey('runner')),
          },
        ),
        ExampleOverlay.topLeft(
          child: SizedBox(
            width: 150,
            child: ExampleDropdown<_Demo>(
              value: _demo,
              items: [
                for (final d in _Demo.values)
                  DropdownMenuItem(value: d, child: Text(d.label)),
              ],
              onChanged: (d) {
                if (d != null) setState(() => _demo = d);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ocean sub-demo.
// ---------------------------------------------------------------------------

class _OceanDemo extends StatefulWidget {
  const _OceanDemo({super.key});

  @override
  State<_OceanDemo> createState() => _OceanDemoState();
}

class _OceanDemoState extends State<_OceanDemo> {
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
    final material = await loadFmatMaterial('assets/vertex_ocean.fmat');
    if (!mounted) return;
    _material = material;
    material.parameters
      ..setFloat('curvature', curvature)
      ..setFloat('amplitude', amplitude);
    scene.add(Node(mesh: Mesh(_oceanGrid(), material)));
    setState(() => loaded = true);
  }

  /// A large, finely tessellated grid with a per-vertex `wave_seed` attribute
  /// (a hashed pseudo-random phase) so the waves vary organically.
  MeshGeometry _oceanGrid() {
    const n = 120;
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
    // TODO(gles-swiftshader): custom vertex attributes read wrong on the
    // x86_64 SwiftShader GLES stack the Android emulator uses (fine on real
    // devices and every other backend), so the wave color is off there.
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
            // Angled down over the ocean so the wave surface and the curved
            // horizon both read clearly.
            camera: PerspectiveCamera(
              position: vm.Vector3(0, 10.0, 8.0),
              target: vm.Vector3(0, 0.0, -12.0),
            ),
            onTick: (elapsed, deltaSeconds) {
              _material?.parameters.setFloat(
                'time',
                elapsed.inMicroseconds / 1e6,
              );
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        _Controls(
          rows: [
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
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Runner sub-demo.
// ---------------------------------------------------------------------------

const double _rowSpacing = 6.0;
const int _rowCount = 26;

class _RunnerDemo extends StatefulWidget {
  const _RunnerDemo({super.key});

  @override
  State<_RunnerDemo> createState() => _RunnerDemoState();
}

class _RunnerDemoState extends State<_RunnerDemo> {
  final Scene scene = Scene();
  final Node _road = Node();
  bool loaded = false;
  double curvature = 0.008;
  PreprocessedMaterial? _material;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final material = await loadFmatMaterial('assets/vertex_road.fmat');
    if (!mounted) return;
    _material = material;
    material.parameters.setFloat('curvature', curvature);

    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 80, depth: 160, segmentsX: 80, segmentsZ: 160),
          material,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0, -50)),
    );
    for (var row = 0; row < _rowCount; row++) {
      final z = -row * _rowSpacing;
      for (final x in const [-6.0, -3.0, 3.0, 6.0]) {
        _road.add(
          Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.0, 2.0, 1.0)), material))
            ..localTransform = vm.Matrix4.translation(vm.Vector3(x, 1.0, z)),
        );
      }
    }
    scene.add(_road);
    setState(() => loaded = true);
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
              position: vm.Vector3(0, 4.0, 8.0),
              target: vm.Vector3(0, 1.2, -12.0),
            ),
            onTick: (elapsed, deltaSeconds) {
              // Scroll the pillars toward the camera, wrapping by one row.
              final offset = (elapsed.inMicroseconds / 1e6 * 6.0) % _rowSpacing;
              _road.localTransform = vm.Matrix4.translation(
                vm.Vector3(0, 0, offset),
              );
              _road.markBoundsDirty();
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        _Controls(
          rows: [
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
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared controls.
// ---------------------------------------------------------------------------

class _Controls extends StatefulWidget {
  const _Controls({required this.rows});

  final List<Widget> rows;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return ExampleOverlay.bottomLeftPanel(
      child: Card(
        color: Colors.black54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.waves_outlined, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Vertex controls',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            if (_open) ...[
              const Divider(height: 1, color: Colors.white24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.rows,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
